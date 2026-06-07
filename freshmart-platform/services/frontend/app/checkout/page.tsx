'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useCart } from '@/context/CartContext'
import { createOrder } from '@/lib/api'
import { DeliveryAddress, PaymentDetails } from '@/lib/types'

const DELIVERY_FEE = 3.99

const STEPS = ['Cart', 'Delivery', 'Payment', 'Confirm']

export default function CheckoutPage() {
  const router = useRouter()
  const { items, subtotal, sessionId, clearCart } = useCart()

  const [loading, setLoading] = useState(false)
  const [error, setError]     = useState('')

  const [address, setAddress] = useState<DeliveryAddress>({
    fullName: '', addressLine1: '', city: '', postcode: '',
  })
  const [payment, setPayment] = useState<PaymentDetails>({
    cardNumber: '', expiry: '', cvv: '',
  })

  const total = subtotal + DELIVERY_FEE

  const handlePlaceOrder = async () => {
    setError('')
    if (!address.fullName || !address.addressLine1 || !address.city || !address.postcode) {
      setError('Please fill in your delivery address.')
      return
    }
    if (!payment.cardNumber || !payment.expiry || !payment.cvv) {
      setError('Please fill in your payment details.')
      return
    }

    setLoading(true)
    try {
      const order = await createOrder({
        sessionId,
        deliveryAddress: address,
        paymentDetails: { cardNumber: payment.cardNumber, expiry: payment.expiry },
      })
      clearCart()
      router.push(`/order-confirmed/${order.id}`)
    } catch {
      setError('Something went wrong. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="pt-xxl pb-xxl px-margin-mobile md:px-margin-desktop max-w-container-max mx-auto mt-4">
      {/* Step indicator */}
      <div className="flex items-center justify-center mb-xxl overflow-x-auto whitespace-nowrap py-sm gap-0">
        {STEPS.map((step, i) => (
          <div key={step} className="flex items-center">
            <div className={`flex items-center gap-sm relative ${i === 2 ? 'text-primary font-bold' : 'text-on-surface-variant opacity-60'}`}>
              <span className="material-symbols-outlined">
                {i < 2 ? 'check_circle' : i === 2 ? 'payments' : 'task_alt'}
              </span>
              <span className="text-label-lg">{step}</span>
              {i === 2 && <div className="absolute -bottom-2 left-0 right-0 h-0.5 bg-primary" />}
            </div>
            {i < STEPS.length - 1 && (
              <div className="w-12 h-px bg-outline-variant mx-md" />
            )}
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-gutter">
        {/* ── Forms ─────────────────────────────────────────────────── */}
        <div className="lg:col-span-8 space-y-lg">

          {/* Delivery Address */}
          <section className="bg-surface-container-lowest border border-outline-variant rounded-xl p-xl shadow-sm">
            <div className="flex items-center gap-sm mb-lg">
              <span className="material-symbols-outlined text-primary">location_on</span>
              <h2 className="text-headline-sm">Delivery address</h2>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-md">
              <div className="md:col-span-2">
                <label className="block text-label-sm text-on-surface-variant mb-xs">Full Name</label>
                <input
                  type="text"
                  placeholder="John Doe"
                  value={address.fullName}
                  onChange={e => setAddress(a => ({ ...a, fullName: e.target.value }))}
                  className="w-full px-md py-sm border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                />
              </div>
              <div className="md:col-span-2">
                <label className="block text-label-sm text-on-surface-variant mb-xs">Address Line 1</label>
                <input
                  type="text"
                  placeholder="123 Fresh Lane"
                  value={address.addressLine1}
                  onChange={e => setAddress(a => ({ ...a, addressLine1: e.target.value }))}
                  className="w-full px-md py-sm border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                />
              </div>
              <div>
                <label className="block text-label-sm text-on-surface-variant mb-xs">City</label>
                <input
                  type="text"
                  placeholder="London"
                  value={address.city}
                  onChange={e => setAddress(a => ({ ...a, city: e.target.value }))}
                  className="w-full px-md py-sm border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                />
              </div>
              <div>
                <label className="block text-label-sm text-on-surface-variant mb-xs">Postcode</label>
                <input
                  type="text"
                  placeholder="SW1A 1AA"
                  value={address.postcode}
                  onChange={e => setAddress(a => ({ ...a, postcode: e.target.value }))}
                  className="w-full px-md py-sm border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                />
              </div>
            </div>
          </section>

          {/* Payment */}
          <section className="bg-surface-container-lowest border border-outline-variant rounded-xl p-xl shadow-sm">
            <div className="flex items-center gap-sm mb-lg">
              <span className="material-symbols-outlined text-primary">credit_card</span>
              <h2 className="text-headline-sm">Payment Method</h2>
            </div>
            <div className="space-y-md">
              <div>
                <label className="block text-label-sm text-on-surface-variant mb-xs">Card Number</label>
                <div className="relative">
                  <input
                    type="text"
                    placeholder="0000 0000 0000 0000"
                    value={payment.cardNumber}
                    onChange={e => setPayment(p => ({ ...p, cardNumber: e.target.value }))}
                    className="w-full px-md py-sm pl-12 border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                  />
                  <span className="material-symbols-outlined absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant opacity-60">lock</span>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-md">
                <div>
                  <label className="block text-label-sm text-on-surface-variant mb-xs">Expiry Date</label>
                  <input
                    type="text"
                    placeholder="MM / YY"
                    value={payment.expiry}
                    onChange={e => setPayment(p => ({ ...p, expiry: e.target.value }))}
                    className="w-full px-md py-sm border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                  />
                </div>
                <div>
                  <label className="block text-label-sm text-on-surface-variant mb-xs">CVV</label>
                  <input
                    type="password"
                    placeholder="•••"
                    value={payment.cvv}
                    onChange={e => setPayment(p => ({ ...p, cvv: e.target.value }))}
                    className="w-full px-md py-sm border border-outline-variant rounded-lg text-body-md bg-transparent focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"
                  />
                </div>
              </div>
              <div className="flex items-center gap-sm pt-sm">
                <input type="checkbox" id="save-card" className="w-4 h-4 text-primary border-outline-variant rounded" />
                <label htmlFor="save-card" className="text-body-sm text-on-surface-variant">
                  Save card details for future purchases
                </label>
              </div>
            </div>
          </section>
        </div>

        {/* ── Order Summary Sidebar ──────────────────────────────────── */}
        <aside className="lg:col-span-4">
          <div className="bg-surface-container-low border border-outline-variant rounded-xl p-xl shadow-sm sticky top-24">
            <h3 className="text-headline-sm mb-lg border-b border-outline-variant pb-md">Order summary</h3>

            <div className="space-y-md mb-xl">
              {items.map(({ product, quantity }) => (
                <div key={product.id} className="flex justify-between items-start">
                  <div>
                    <p className="text-label-lg">{product.name}</p>
                    <p className="text-body-sm text-on-surface-variant">{quantity} × £{product.price.toFixed(2)}</p>
                  </div>
                  <span className="text-label-lg">£{(product.price * quantity).toFixed(2)}</span>
                </div>
              ))}
            </div>

            <div className="border-t border-outline-variant pt-md space-y-sm">
              <div className="flex justify-between text-body-md">
                <span>Subtotal</span>
                <span>£{subtotal.toFixed(2)}</span>
              </div>
              <div className="flex justify-between text-body-md">
                <span>Delivery Fee</span>
                <span className="text-primary font-bold">£{DELIVERY_FEE.toFixed(2)}</span>
              </div>
              <div className="flex justify-between items-center pt-md border-t border-outline-variant">
                <span className="text-headline-sm">Total</span>
                <span className="text-headline-md text-primary">£{total.toFixed(2)}</span>
              </div>
            </div>

            {error && (
              <p className="mt-md text-body-sm text-error bg-error-container rounded-lg px-md py-sm">{error}</p>
            )}

            <button
              onClick={handlePlaceOrder}
              disabled={loading || items.length === 0}
              className="w-full mt-xl bg-primary text-on-primary py-md rounded-lg text-label-lg hover:brightness-110 active:scale-[0.98] transition-all flex items-center justify-center gap-sm shadow-md disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  Processing...
                </>
              ) : (
                <>
                  <span className="material-symbols-outlined">shopping_bag</span>
                  Place Order
                </>
              )}
            </button>

            <div className="mt-lg flex items-center justify-center gap-xs text-on-surface-variant opacity-60">
              <span className="material-symbols-outlined text-sm">verified_user</span>
              <span className="text-label-sm">Secure 256-bit SSL encrypted checkout</span>
            </div>
          </div>
        </aside>
      </div>
    </div>
  )
}
