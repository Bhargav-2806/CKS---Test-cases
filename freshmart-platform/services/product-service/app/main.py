import logging
from contextlib import asynccontextmanager
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import insert as sa_insert
from sqlalchemy.orm import Session

from .config import settings
from .database import engine, get_db, Base
from .models import Product
from .schemas import ProductResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ─── Seed data (matches frontend mock) ───────────────────────────────────────

SEED_PRODUCTS = [
    # in_stock is explicit (nullable=False, no server_default) — required for bulk insert
    dict(id=1,  name="Organic Bananas",    price=1.50, category="Fruit",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1603833665858-e61d17a86224?auto=format&fit=crop&w=400&q=80",
         description="Sweet, ripe organic bananas. A great source of potassium and natural energy."),
    dict(id=2,  name="Whole Milk (2L)",    price=2.10, category="Dairy",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1550583724-1255818c053b?auto=format&fit=crop&w=400&q=80",
         description="Fresh whole milk from grass-fed cows. Rich in calcium and vitamins."),
    dict(id=3,  name="Sourdough Bread",    price=3.20, category="Bakery",   in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1585478259715-876acc5be8eb?auto=format&fit=crop&w=400&q=80",
         description="Crusty, artisanal sourdough baked fresh every morning. Slow-fermented for 24 hours."),
    dict(id=4,  name="Avocados (2pk)",     price=2.50, category="Fruit",    in_stock=True, badge="Bestseller",
         image="https://images.unsplash.com/photo-1523049673857-eb18f1d7b578?auto=format&fit=crop&w=400&q=80",
         description="Creamy, ripe avocados perfect for salads or toast. Locally sourced and organic."),
    dict(id=5,  name="Vine Tomatoes",      price=1.80, category="Vegetables", in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=400&q=80",
         description="Juicy vine-ripened tomatoes bursting with flavour."),
    dict(id=6,  name="Greek Yogurt",       price=1.95, category="Dairy",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=400&q=80",
         description="Thick, creamy Greek yogurt. High in protein and probiotics."),
    dict(id=7,  name="Spinach (200g)",     price=1.20, category="Vegetables", in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=400&q=80",
         description="Fresh baby spinach leaves, pre-washed and ready to eat. Packed with iron."),
    dict(id=8,  name="Pink Lady Apples",   price=2.00, category="Fruit",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1560806887-1e480c8ca0ff?auto=format&fit=crop&w=400&q=80",
         description="Crisp, sweet-tart Pink Lady apples. Sustainably grown in Kent."),
    dict(id=9,  name="Fresh Strawberries", price=2.80, category="Fruit",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1464965911861-746a04b4bca6?auto=format&fit=crop&w=400&q=80",
         description="Sweet, juicy British strawberries picked at peak ripeness."),
    dict(id=10, name="Free Range Eggs",    price=2.40, category="Dairy",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1506976785307-8732e854ad03?auto=format&fit=crop&w=400&q=80",
         description="A dozen large free-range eggs from happy hens. Rich golden yolks."),
    dict(id=11, name="Red Bell Pepper",    price=0.80, category="Vegetables", in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1563513130-18458788448d?auto=format&fit=crop&w=400&q=80",
         description="Sweet, crunchy red peppers. Great for stir-fries or eating raw."),
    dict(id=12, name="Unsalted Butter",    price=1.75, category="Dairy",    in_stock=True, badge=None,
         image="https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?auto=format&fit=crop&w=400&q=80",
         description="Churned from the finest cream. Ideal for baking and cooking."),
]


# ─── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup: create tables + seed
    Base.metadata.create_all(bind=engine)
    _seed_if_empty()
    logger.info("Product service started on port %s", settings.port)
    yield
    logger.info("Product service shutting down")


def _seed_if_empty():
    from .database import SessionLocal
    db = SessionLocal()
    try:
        if db.query(Product).count() == 0:
            logger.info("Seeding %d products...", len(SEED_PRODUCTS))
            # SQLAlchemy 2.0 bulk insert (replaces deprecated bulk_insert_mappings)
            db.execute(sa_insert(Product), SEED_PRODUCTS)
            db.commit()
    except Exception as e:
        logger.error("Seed failed: %s", e)
        db.rollback()
    finally:
        db.close()


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="FreshMart — Product Service",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "OPTIONS"],
    allow_headers=["*"],
)


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "healthy", "service": "product-service"}


@app.get("/api/products", response_model=List[ProductResponse])
def list_products(
    category: Optional[str] = None,
    db: Session = Depends(get_db),
):
    q = db.query(Product).filter(Product.in_stock.is_(True))
    if category:
        q = q.filter(Product.category == category)
    return q.order_by(Product.id).all()


@app.get("/api/products/{product_id}", response_model=ProductResponse)
def get_product(product_id: int, db: Session = Depends(get_db)):
    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product
