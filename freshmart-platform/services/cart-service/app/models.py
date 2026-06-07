from sqlalchemy import Column, Integer, String, Numeric, DateTime, UniqueConstraint, ForeignKey
from sqlalchemy.sql import func
from .database import Base


class CartSession(Base):
    __tablename__ = "cart_sessions"

    session_id = Column(String(255), primary_key=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class CartItem(Base):
    __tablename__ = "cart_items"
    __table_args__ = (UniqueConstraint("session_id", "product_id", name="uq_session_product"),)

    id            = Column(Integer, primary_key=True, autoincrement=True)
    session_id    = Column(String(255), ForeignKey("cart_sessions.session_id", ondelete="CASCADE"), nullable=False, index=True)
    product_id    = Column(Integer, nullable=False)
    product_name  = Column(String(255), nullable=False)
    product_price = Column(Numeric(10, 2), nullable=False)
    quantity      = Column(Integer, nullable=False, default=1)
