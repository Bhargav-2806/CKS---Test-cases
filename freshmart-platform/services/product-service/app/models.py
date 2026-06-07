from sqlalchemy import Column, Integer, String, Numeric, Boolean, Text, DateTime
from sqlalchemy.sql import func
from .database import Base


class Product(Base):
    __tablename__ = "products"

    id          = Column(Integer, primary_key=True, index=True)
    name        = Column(String(255), nullable=False)
    price       = Column(Numeric(10, 2), nullable=False)
    category    = Column(String(100), nullable=False, index=True)
    image       = Column(Text, nullable=True)
    description = Column(Text, nullable=True)
    in_stock    = Column(Boolean, default=True, nullable=False)
    badge       = Column(String(50), nullable=True)
    created_at  = Column(DateTime(timezone=True), server_default=func.now())
    updated_at  = Column(DateTime(timezone=True), onupdate=func.now())
