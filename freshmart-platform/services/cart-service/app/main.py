import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from .config import settings
from .database import engine, get_db, Base
from .models import CartSession, CartItem
from .schemas import AddItemRequest, UpdateItemRequest, CartResponse, CartItemResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ─── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    logger.info("Cart service started on port %s", settings.port)
    yield
    logger.info("Cart service shutting down")


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="FreshMart — Cart Service",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _get_or_create_session(session_id: str, db: Session) -> CartSession:
    session = db.query(CartSession).filter(CartSession.session_id == session_id).first()
    if not session:
        session = CartSession(session_id=session_id)
        db.add(session)
        db.commit()
        db.refresh(session)
    return session


def _build_cart_response(session_id: str, items: list) -> CartResponse:
    item_responses = [
        CartItemResponse(
            product_id=i.product_id,
            product_name=i.product_name,
            product_price=float(i.product_price),
            quantity=i.quantity,
        )
        for i in items
    ]
    subtotal = sum(r.product_price * r.quantity for r in item_responses)
    return CartResponse(
        session_id=session_id,
        items=item_responses,
        subtotal=round(subtotal, 2),
        item_count=sum(r.quantity for r in item_responses),
    )


async def _fetch_product(product_id: int) -> dict:
    """Fetch product details from product-service."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{settings.product_service_url}/api/products/{product_id}")
            resp.raise_for_status()
            return resp.json()
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Product service unavailable: {e}")


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "healthy", "service": "cart-service"}


@app.get("/api/cart/{session_id}", response_model=CartResponse)
def get_cart(session_id: str, db: Session = Depends(get_db)):
    items = (
        db.query(CartItem)
        .filter(CartItem.session_id == session_id)
        .order_by(CartItem.id)
        .all()
    )
    return _build_cart_response(session_id, items)


@app.post("/api/cart/{session_id}/items", response_model=CartResponse, status_code=201)
async def add_item(session_id: str, body: AddItemRequest, db: Session = Depends(get_db)):
    # Fetch product details from product-service
    product = await _fetch_product(body.product_id)

    _get_or_create_session(session_id, db)

    existing = (
        db.query(CartItem)
        .filter(CartItem.session_id == session_id, CartItem.product_id == body.product_id)
        .first()
    )

    if existing:
        existing.quantity += body.quantity
    else:
        item = CartItem(
            session_id=session_id,
            product_id=body.product_id,
            product_name=product["name"],
            product_price=product["price"],
            quantity=body.quantity,
        )
        db.add(item)

    db.commit()
    items = db.query(CartItem).filter(CartItem.session_id == session_id).all()
    return _build_cart_response(session_id, items)


@app.put("/api/cart/{session_id}/items/{product_id}", response_model=CartResponse)
def update_item(
    session_id: str,
    product_id: int,
    body: UpdateItemRequest,
    db: Session = Depends(get_db),
):
    item = (
        db.query(CartItem)
        .filter(CartItem.session_id == session_id, CartItem.product_id == product_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item not in cart")

    if body.quantity <= 0:
        db.delete(item)
    else:
        item.quantity = body.quantity

    db.commit()
    items = db.query(CartItem).filter(CartItem.session_id == session_id).all()
    return _build_cart_response(session_id, items)


@app.delete("/api/cart/{session_id}/items/{product_id}", response_model=CartResponse)
def remove_item(session_id: str, product_id: int, db: Session = Depends(get_db)):
    item = (
        db.query(CartItem)
        .filter(CartItem.session_id == session_id, CartItem.product_id == product_id)
        .first()
    )
    if item:
        db.delete(item)
        db.commit()

    items = db.query(CartItem).filter(CartItem.session_id == session_id).all()
    return _build_cart_response(session_id, items)


@app.delete("/api/cart/{session_id}", status_code=204)
def clear_cart(session_id: str, db: Session = Depends(get_db)):
    db.query(CartItem).filter(CartItem.session_id == session_id).delete()
    db.commit()
