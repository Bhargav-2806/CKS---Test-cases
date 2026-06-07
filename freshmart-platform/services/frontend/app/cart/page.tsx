'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useCart } from '@/context/CartContext'

const DELIVERY_FEE = 3.99

export default function CartPage() {
  const { items, subtotal, count, removeItem, updateQuantity } = useCart()
  const router = useRouter()

  const total = subtotal + (subtotal > 0 ? DELIVERY_FEE : 0)

  if (count === 0) {
    return (
      <div className="pt-24 pb-xxl px-margin-mobile md:px-margin-desktop max-w-container-max mx-auto text-center">
        <span className="material-symbols-outlined text-[80px] text-outline-variant block mb-lg">shopping_cart</span>
        <h1 className="text-headline-lg text-on-surface mb-md">Your cart is empty</h1>
        <p className="text-body-md text-on-surface-variant mb-xl">Add some fresh products to get started.</p>
        <Link
          href="/"
          className="inline-flex items-center gap-sm bg-primary text-on-primary text-label-lg px-xl py-md rounded-lg hover:brightness-110 transition-all"
        >
          <span className="material-symbols-outlined text-[18px]">arrow_back</span>
          Continue Shopping
        </Link>
      </div>
    )
  }

  return (
    <div className="pt-24 pb-xxl px-margin-mobile md:px-margin-desktop max-w-container-max mx-auto">
      <h1 className="text-headline-lg mb-xl">Your Cart</h1>

      <div className="flex flex-col lg:flex-row gap-gutter">
        {/* ── Cart Items (70%) ───────────────────────────────────────── */}
        <div className="lg:w-[70%]">
          <div className="bg-surface-container-lowest border border-outline-variant rounded-xl overflow-hidden shadow-sm">
            <div className="p-md md:p-lg space-y-lg">
              {items.map(({ product, quantity }) => (
                <div
                  key={product.id}
                  className="flex items-center gap-md py-md border-b border-outline-variant last:border-0"
                >
                  {/* Thumbnail */}
                  <div className="w-20 h-20 rounded-lg overflow-hidden bg-surface-container flex-shrink-0">
                    <img src={product.image} alt={product.name} className="w-full h-full object-cover" />
                  </div>

                  {/* Details */}
                  <div className="flex-grow grid grid-cols-2 md:grid-cols-4 items-center gap-sm">
                    <div className="col-span-2 md:col-span-1">
                      <h3 className="text-label-lg text-on-surface">{product.name}</h3>
                      <p className="text-body-sm text-on-surface-variant">£{product.price.toFixed(2)} per unit</p>
                    </div>

                    {/* Quantity stepper */}
                    <div className="flex items-center gap-sm justify-center md:justify-start">
                      <button
                        onClick={() => updateQuantity(product.id, quantity - 1)}
                        className="w-8 h-8 rounded-full border border-outline-variant flex items-center justify-center hover:bg-surface-container transition-colors"
                      >
                        <span className="material-symbols-outlined text-[18px]">remove</span>
                      </button>
                      <span className="text-label-lg w-4 text-center">{quantity}</span>
                      <button
                        onClick={() => updateQuantity(product.id, quantity + 1)}
                        className="w-8 h-8 rounded-full border border-outline-variant flex items-center justify-center hover:bg-surface-container transition-colors"
                      >
                        <span className="material-symbols-outlined text-[18px]">add</span>
                      </button>
                    </div>

                    {/* Line total */}
                    <div className="text-right md:text-left">
                      <p className="text-label-lg text-on-surface">£{(product.price * quantity).toFixed(2)}</p>
                    </div>

                    {/* Remove */}
                    <div className="flex justify-end">
                      <button
                        onClick={() => removeItem(product.id)}
                        className="text-on-surface-variant hover:text-error transition-colors p-sm"
                      >
                        <span className="material-symbols-outlined">delete</span>
                      </button>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Subtotal row */}
            <div className="bg-surface-container-low p-md md:p-lg border-t border-outline-variant flex justify-between items-center">
              <span className="text-label-lg text-on-surface-variant">Subtotal</span>
              <span className="text-headline-sm text-on-surface">£{subtotal.toFixed(2)}</span>
            </div>
          </div>

          {/* Continue shopping */}
          <Link
            href="/"
            className="mt-lg flex items-center gap-sm text-primary hover:underline transition-all w-fit"
          >
            <span className="material-symbols-outlined text-[18px]">arrow_back</span>
            <span className="text-label-lg">Continue Shopping</span>
          </Link>
        </div>

        {/* ── Order Summary (30%) ────────────────────────────────────── */}
        <aside className="lg:w-[30%]">
          <div className="bg-surface-container-lowest border border-outline-variant rounded-xl shadow-sm p-md md:p-lg sticky top-24">
            <h2 className="text-headline-sm mb-lg text-on-surface">Order Summary</h2>

            <div className="space-y-md mb-xl">
              <div className="flex justify-between items-center text-on-surface-variant">
                <span className="text-body-md">Subtotal</span>
                <span className="text-body-md">£{subtotal.toFixed(2)}</span>
              </div>
              <div className="flex justify-between items-center text-on-surface-variant">
                <span className="text-body-md">Delivery fee</span>
                <span className="text-body-md">£{DELIVERY_FEE.toFixed(2)}</span>
              </div>
              <div className="pt-md border-t border-outline-variant flex justify-between items-center">
                <span className="text-label-lg text-on-surface">Total</span>
                <span className="text-headline-md text-on-surface font-bold">£{total.toFixed(2)}</span>
              </div>
            </div>

            <button
              onClick={() => router.push('/checkout')}
              className="w-full py-md bg-primary hover:brightness-110 text-on-primary rounded-lg text-label-lg transition-colors flex items-center justify-center gap-sm active:scale-95 duration-150"
            >
              Proceed to Checkout
              <span className="material-symbols-outlined">chevron_right</span>
            </button>

            <div className="mt-xl p-md bg-primary-fixed/30 rounded-lg flex items-start gap-sm">
              <span className="material-symbols-outlined text-primary" style={{ fontVariationSettings: "'FILL' 1" }}>eco</span>
              <p className="text-body-sm text-on-primary-fixed-variant">
                This order qualifies for <span className="font-bold">Plastic-Free</span> packaging.
              </p>
            </div>
          </div>
        </aside>
      </div>
    </div>
  )
}
