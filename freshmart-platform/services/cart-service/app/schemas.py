from pydantic import BaseModel, ConfigDict
from typing import List


class AddItemRequest(BaseModel):
    product_id: int
    quantity: int = 1


class UpdateItemRequest(BaseModel):
    quantity: int


class CartItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    product_id:    int
    product_name:  str
    product_price: float
    quantity:      int


class CartResponse(BaseModel):
    session_id: str
    items:      List[CartItemResponse]
    subtotal:   float
    item_count: int
