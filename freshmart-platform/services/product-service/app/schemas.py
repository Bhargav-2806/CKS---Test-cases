from pydantic import BaseModel, ConfigDict
from typing import Optional


class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id:          int
    name:        str
    price:       float
    category:    str
    image:       Optional[str] = None
    description: Optional[str] = None
    in_stock:    bool = True
    badge:       Optional[str] = None
