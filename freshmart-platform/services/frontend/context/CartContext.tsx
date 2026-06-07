'use client'

import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react'
import { CartItem, Product } from '@/lib/types'
import { addToCartAPI, updateCartItemAPI, removeCartItemAPI, getCartAPI } from '@/lib/api'

// ─── Session ID (anonymous cart key) ─────────────────────────────────────────

function getOrCreateSessionId(): string {
  if (typeof window === 'undefined') return ''
  let id = localStorage.getItem('fm_session_id')
  if (!id) {
    id = typeof crypto !== 'undefined' && crypto.randomUUID
      ? crypto.randomUUID()
      : Math.random().toString(36).slice(2)
    localStorage.setItem('fm_session_id', id)
  }
  return id
}

// ─── Context types ────────────────────────────────────────────────────────────

interface CartContextType {
  items: CartItem[]
  sessionId: string
  count: number
  subtotal: number
  addItem: (product: Product, quantity?: number) => void
  removeItem: (productId: number) => void
  updateQuantity: (productId: number, quantity: number) => void
  clearCart: () => void
}

const CartContext = createContext<CartContextType | null>(null)

// ─── Provider ─────────────────────────────────────────────────────────────────

export function CartProvider({ children }: { children: ReactNode }) {
  const [items, setItems]       = useState<CartItem[]>([])
  const [sessionId, setSession] = useState('')

  // Initialise on mount (client only)
  useEffect(() => {
    const sid = getOrCreateSessionId()
    setSession(sid)

    // Try loading from backend, fall back to localStorage
    getCartAPI(sid)
      .then(apiItems => {
        if (apiItems.length > 0) {
          setItems(apiItems)
        } else {
          const stored = localStorage.getItem('fm_cart')
          if (stored) setItems(JSON.parse(stored))
        }
      })
      .catch(() => {
        const stored = localStorage.getItem('fm_cart')
        if (stored) setItems(JSON.parse(stored))
      })
  }, [])

  const persist = (next: CartItem[]) => {
    localStorage.setItem('fm_cart', JSON.stringify(next))
    setItems(next)
  }

  const addItem = useCallback((product: Product, quantity = 1) => {
    setItems(prev => {
      const idx = prev.findIndex(i => i.product.id === product.id)
      const next = idx >= 0
        ? prev.map((it, i) => i === idx ? { ...it, quantity: it.quantity + quantity } : it)
        : [...prev, { product, quantity }]
      localStorage.setItem('fm_cart', JSON.stringify(next))
      return next
    })
    addToCartAPI(sessionId, product.id, quantity).catch(() => {})
  }, [sessionId])

  const removeItem = useCallback((productId: number) => {
    setItems(prev => {
      const next = prev.filter(i => i.product.id !== productId)
      localStorage.setItem('fm_cart', JSON.stringify(next))
      return next
    })
    removeCartItemAPI(sessionId, productId).catch(() => {})
  }, [sessionId])

  const updateQuantity = useCallback((productId: number, quantity: number) => {
    if (quantity <= 0) { removeItem(productId); return }
    setItems(prev => {
      const next = prev.map(i => i.product.id === productId ? { ...i, quantity } : i)
      localStorage.setItem('fm_cart', JSON.stringify(next))
      return next
    })
    updateCartItemAPI(sessionId, productId, quantity).catch(() => {})
  }, [sessionId, removeItem])

  const clearCart = useCallback(() => {
    persist([])
    localStorage.removeItem('fm_cart')
  }, [])

  const count    = items.reduce((s, i) => s + i.quantity, 0)
  const subtotal = items.reduce((s, i) => s + i.product.price * i.quantity, 0)

  return (
    <CartContext.Provider value={{ items, sessionId, count, subtotal, addItem, removeItem, updateQuantity, clearCart }}>
      {children}
    </CartContext.Provider>
  )
}

export function useCart(): CartContextType {
  const ctx = useContext(CartContext)
  if (!ctx) throw new Error('useCart must be used inside <CartProvider>')
  return ctx
}
