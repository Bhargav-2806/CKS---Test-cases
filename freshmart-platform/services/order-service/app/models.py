from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey
from sqlalchemy.sql import func
from .database import Base


class Order(Base):
    __tablename__ = "orders"

    id           = Column(String(50),  primary_key=True, index=True)
    session_id   = Column(String(255), nullable=False, index=True)
    status       = Column(String(50),  nullable=False, default="pending")
    subtotal     = Column(Numeric(10, 2), nullable=False)
    delivery_fee = Column(Numeric(10, 2), nullable=False, default=3.99)
    total        = Column(Numeric(10, 2), nullable=False)
    # Delivery address (denormalised for simplicity)
    full_name    = Column(String(255))
    address_line1 = Column(String(500))
    city         = Column(String(100))
    postcode     = Column(String(20))
    created_at   = Column(DateTime(timezone=True), server_default=func.now())
    updated_at   = Column(DateTime(timezone=True), onupdate=func.now())


class OrderItem(Base):
    __tablename__ = "order_items"

    id            = Column(Integer,     primary_key=True, autoincrement=True)
    order_id      = Column(String(50),  ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id    = Column(Integer,     nullable=False)
    product_name  = Column(String(255), nullable=False)
    product_price = Column(Numeric(10, 2), nullable=False)
    quantity      = Column(Integer,     nullable=False)
