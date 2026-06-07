export interface Product {
  id: number
  name: string
  price: number
  category: string
  image: string
  description?: string
  inStock?: boolean
  badge?: string
}

export interface CartItem {
  product: Product
  quantity: number
}

export interface DeliveryAddress {
  fullName: string
  addressLine1: string
  city: string
  postcode: string
}

export interface PaymentDetails {
  cardNumber: string
  expiry: string
  cvv: string
}

export interface Order {
  id: string
  sessionId: string
  items: CartItem[]
  subtotal: number
  deliveryFee: number
  total: number
  status: 'pending' | 'confirmed' | 'processing' | 'shipped' | 'delivered'
  deliveryAddress: DeliveryAddress
  createdAt: string
}

export interface CreateOrderPayload {
  sessionId: string
  deliveryAddress: DeliveryAddress
  paymentDetails: Omit<PaymentDetails, 'cvv'>
}
