import { Product, CartItem, Order, CreateOrderPayload } from './types'
import { MOCK_PRODUCTS } from './data'

const PRODUCT_URL = process.env.NEXT_PUBLIC_PRODUCT_SERVICE_URL || ''
const CART_URL    = process.env.NEXT_PUBLIC_CART_SERVICE_URL    || ''
const ORDER_URL   = process.env.NEXT_PUBLIC_ORDER_SERVICE_URL   || ''

// ─── Products ────────────────────────────────────────────────────────────────

export async function getProducts(): Promise<Product[]> {
  if (!PRODUCT_URL) return MOCK_PRODUCTS
  const res = await fetch(`${PRODUCT_URL}/api/products`, { next: { revalidate: 60 } })
  if (!res.ok) return MOCK_PRODUCTS
  return res.json()
}

export async function getProduct(id: number): Promise<Product | null> {
  if (!PRODUCT_URL) return MOCK_PRODUCTS.find(p => p.id === id) ?? null
  const res = await fetch(`${PRODUCT_URL}/api/products/${id}`)
  if (!res.ok) return MOCK_PRODUCTS.find(p => p.id === id) ?? null
  return res.json()
}

// ─── Cart ────────────────────────────────────────────────────────────────────

export async function getCartAPI(sessionId: string): Promise<CartItem[]> {
  if (!CART_URL || !sessionId) return []
  const res = await fetch(`${CART_URL}/api/cart/${sessionId}`)
  if (!res.ok) return []
  const data = await res.json()
  return data.items ?? []
}

export async function addToCartAPI(sessionId: string, productId: number, quantity: number): Promise<void> {
  if (!CART_URL || !sessionId) return
  await fetch(`${CART_URL}/api/cart/${sessionId}/items`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ product_id: productId, quantity }),
  })
}

export async function updateCartItemAPI(sessionId: string, productId: number, quantity: number): Promise<void> {
  if (!CART_URL || !sessionId) return
  await fetch(`${CART_URL}/api/cart/${sessionId}/items/${productId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ quantity }),
  })
}

export async function removeCartItemAPI(sessionId: string, productId: number): Promise<void> {
  if (!CART_URL || !sessionId) return
  await fetch(`${CART_URL}/api/cart/${sessionId}/items/${productId}`, { method: 'DELETE' })
}

// ─── Orders ──────────────────────────────────────────────────────────────────

export async function createOrder(payload: CreateOrderPayload): Promise<Order> {
  if (!ORDER_URL) {
    // Mock order for development
    return {
      id: `FM-${Date.now()}`,
      sessionId: payload.sessionId,
      items: [],
      subtotal: 0,
      deliveryFee: 3.99,
      total: 3.99,
      status: 'confirmed',
      deliveryAddress: payload.deliveryAddress,
      createdAt: new Date().toISOString(),
    }
  }
  const res = await fetch(`${ORDER_URL}/api/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  if (!res.ok) throw new Error('Failed to create order')
  return res.json()
}

export async function getOrder(orderId: string): Promise<Order | null> {
  if (!ORDER_URL) return null
  const res = await fetch(`${ORDER_URL}/api/orders/${orderId}`)
  if (!res.ok) return null
  return res.json()
}
