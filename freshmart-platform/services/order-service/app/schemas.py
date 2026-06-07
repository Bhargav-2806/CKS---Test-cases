from pydantic import BaseModel, ConfigDict
from typing import List, Optional


class DeliveryAddress(BaseModel):
    full_name:     str
    address_line1: str
    city:          str
    postcode:      str


class PaymentDetails(BaseModel):
    card_number: str
    expiry:      str
    # CVV is intentionally NOT stored or forwarded — PCI compliance


class CreateOrderRequest(BaseModel):
    session_id:       str
    delivery_address: DeliveryAddress
    payment_details:  PaymentDetails


class OrderItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    product_id:    int
    product_name:  str
    product_price: float
    quantity:      int


class OrderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id:           str
    session_id:   str
    status:       str
    subtotal:     float
    delivery_fee: float
    total:        float
    full_name:    Optional[str] = None
    address_line1: Optional[str] = None
    city:         Optional[str] = None
    postcode:     Optional[str] = None
