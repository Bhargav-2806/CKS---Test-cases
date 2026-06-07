import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import List, Optional

import httpx
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from .config import settings
from .database import engine, get_db, Base
from .models import Order, OrderItem
from .schemas import CreateOrderRequest, OrderResponse
from . import kafka_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DELIVERY_FEE = 3.99


# ─── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    if settings.kafka_enabled:
        await kafka_client.init_producer(settings.kafka_bootstrap_servers)
    logger.info("Order service started on port %s", settings.port)
    yield
    await kafka_client.close_producer()
    logger.info("Order service shutting down")


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="FreshMart — Order Service",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def _get_cart(session_id: str) -> dict:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{settings.cart_service_url}/api/cart/{session_id}")
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Cart service unavailable: {e}")


async def _process_payment(order_id: str, amount: float, card_number: str) -> dict:
    """Call payment-service synchronously. Demonstrates inter-service mTLS in K8s."""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                f"{settings.payment_service_url}/api/payments",
                json={
                    "order_id": order_id,
                    "amount": amount,
                    "card_last_four": card_number[-4:] if len(card_number) >= 4 else "0000",
                },
            )
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 402:
            raise HTTPException(status_code=402, detail="Payment declined")
        raise HTTPException(status_code=502, detail=f"Payment service error: {e}")
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Payment service unavailable: {e}")


async def _clear_cart(session_id: str) -> None:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.delete(f"{settings.cart_service_url}/api/cart/{session_id}")
    except Exception:
        pass  # best-effort; cart TTL will clean up anyway


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "healthy", "service": "order-service"}


@app.post("/api/orders", response_model=OrderResponse, status_code=201)
async def create_order(body: CreateOrderRequest, db: Session = Depends(get_db)):
    # 1. Fetch cart
    cart = await _get_cart(body.session_id)
    if not cart["items"]:
        raise HTTPException(status_code=400, detail="Cart is empty")

    # 2. Calculate totals
    subtotal = round(cart["subtotal"], 2)
    total    = round(subtotal + DELIVERY_FEE, 2)
    order_id = f"FM-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{str(uuid.uuid4())[:8].upper()}"

    # 3. Create order record (status=pending)
    order = Order(
        id=order_id,
        session_id=body.session_id,
        status="pending",
        subtotal=subtotal,
        delivery_fee=DELIVERY_FEE,
        total=total,
        full_name=body.delivery_address.full_name,
        address_line1=body.delivery_address.address_line1,
        city=body.delivery_address.city,
        postcode=body.delivery_address.postcode,
    )
    db.add(order)

    for item in cart["items"]:
        db.add(OrderItem(
            order_id=order_id,
            product_id=item["product_id"],
            product_name=item["product_name"],
            product_price=item["product_price"],
            quantity=item["quantity"],
        ))

    db.commit()

    # 4. Call payment-service
    try:
        payment = await _process_payment(
            order_id=order_id,
            amount=total,
            card_number=body.payment_details.card_number,
        )
        order.status = "confirmed" if payment.get("status") == "success" else "payment_failed"
    except HTTPException:
        order.status = "payment_failed"
        db.commit()
        raise

    db.commit()
    db.refresh(order)

    # 5. Publish event (best-effort)
    await kafka_client.publish("order.confirmed", {
        "order_id": order_id,
        "session_id": body.session_id,
        "total": total,
        "status": order.status,
    })

    # 6. Clear cart
    await _clear_cart(body.session_id)

    return order


@app.get("/api/orders/{order_id}", response_model=OrderResponse)
def get_order(order_id: str, db: Session = Depends(get_db)):
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


@app.get("/api/orders", response_model=List[OrderResponse])
def list_orders(session_id: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(Order)
    if session_id:
        q = q.filter(Order.session_id == session_id)
    return q.order_by(Order.created_at.desc()).limit(50).all()
