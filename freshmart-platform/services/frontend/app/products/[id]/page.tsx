'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import { Product } from '@/lib/types'
import { getProduct } from '@/lib/api'
import { useCart } from '@/context/CartContext'
import { RELATED_PRODUCTS } from '@/lib/data'

export default function ProductDetailPage() {
  const params = useParams()
  const router = useRouter()
  const { addItem } = useCart()

  const [product, setProduct] = useState<Product | null>(null)
  const [quantity, setQuantity] = useState(1)
  const [added, setAdded] = useState(false)

  useEffect(() => {
    const id = Number(params.id)
    getProduct(id).then(p => {
      if (!p) router.push('/')
      else setProduct(p)
    })
  }, [params.id, router])

  const handleAddToCart = () => {
    if (!product) return
    addItem(product, quantity)
    setAdded(true)
    setTimeout(() => setAdded(false), 1500)
  }

  if (!product) {
    return (
      <div className="pt-xxl px-margin-desktop max-w-container-max mx-auto">
        <div className="grid md:grid-cols-2 gap-gutter">
          <div className="bg-surface-container rounded-xl aspect-[4/3] animate-pulse" />
          <div className="space-y-md">
            <div className="h-8 bg-surface-container rounded animate-pulse w-3/4" />
            <div className="h-12 bg-surface-container rounded animate-pulse w-1/3" />
            <div className="h-4 bg-surface-container rounded animate-pulse" />
            <div className="h-4 bg-surface-container rounded animate-pulse w-5/6" />
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="pt-xxl mt-4 px-margin-mobile md:px-margin-desktop max-w-container-max mx-auto mb-xxl">
      {/* Breadcrumb */}
      <nav className="flex py-md text-label-sm text-on-surface-variant gap-xs items-center mb-md">
        <Link href="/" className="hover:text-primary">Home</Link>
        <span className="material-symbols-outlined text-[14px]">chevron_right</span>
        <Link href="/" className="hover:text-primary">Products</Link>
        <span className="material-symbols-outlined text-[14px]">chevron_right</span>
        <span className="text-on-surface font-semibold">{product.name}</span>
      </nav>

      {/* Product section */}
      <section className="grid grid-cols-1 md:grid-cols-12 gap-gutter items-start">
        {/* Image */}
        <div className="md:col-span-7">
          <div className="rounded-xl overflow-hidden shadow-sm border border-outline-variant bg-white aspect-[4/3] group cursor-zoom-in">
            <img
              src={product.image}
              alt={product.name}
              className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
            />
          </div>
        </div>

        {/* Info */}
        <div className="md:col-span-5 flex flex-col gap-lg">
          <div>
            {product.badge && (
              <span className="inline-block bg-primary-fixed text-on-primary-fixed px-sm py-xs rounded text-label-sm mb-sm">
                {product.badge}
              </span>
            )}
            <h1 className="text-headline-lg text-on-surface leading-tight">{product.name}</h1>
            <p className="text-display-lg text-secondary-container mt-xs">£{product.price.toFixed(2)}</p>
          </div>

          <p className="text-body-md text-on-surface-variant leading-relaxed">{product.description}</p>

          {/* Quantity + stock */}
          <div className="flex flex-col gap-md border-y border-outline-variant py-lg">
            <div className="flex items-center gap-md">
              <span className="text-label-lg w-20">Quantity</span>
              <div className="flex items-center border border-outline rounded-lg bg-surface-container-lowest">
                <button
                  className="p-sm hover:bg-surface-container transition-colors"
                  onClick={() => setQuantity(q => Math.max(1, q - 1))}
                >
                  <span className="material-symbols-outlined">remove</span>
                </button>
                <input
                  type="number"
                  min={1}
                  value={quantity}
                  onChange={e => setQuantity(Math.max(1, parseInt(e.target.value) || 1))}
                  className="w-12 text-center border-none focus:ring-0 bg-transparent font-bold outline-none"
                />
                <button
                  className="p-sm hover:bg-surface-container transition-colors"
                  onClick={() => setQuantity(q => q + 1)}
                >
                  <span className="material-symbols-outlined">add</span>
                </button>
              </div>
            </div>
            <div className="flex items-center gap-sm text-on-primary-fixed-variant">
              <span className="material-symbols-outlined text-[20px]">check_circle</span>
              <span className="text-label-sm">In stock &amp; ready to ship</span>
            </div>
          </div>

          {/* CTAs */}
          <div className="flex flex-col gap-sm pt-sm">
            <button
              onClick={handleAddToCart}
              className={`text-headline-sm py-md rounded-xl active:scale-[0.98] transition-all flex items-center justify-center gap-sm ${
                added
                  ? 'bg-primary-fixed text-on-primary-fixed-variant'
                  : 'bg-primary-container text-on-primary hover:brightness-110'
              }`}
            >
              <span className="material-symbols-outlined">
                {added ? 'check_circle' : 'shopping_basket'}
              </span>
              {added ? 'Added to Cart!' : 'Add to Cart'}
            </button>
            <Link
              href="/"
              className="text-primary text-label-lg py-md border border-transparent hover:border-primary rounded-xl active:scale-[0.98] transition-all text-center"
            >
              Continue Shopping
            </Link>
          </div>

          {/* Trust badges */}
          <div className="grid grid-cols-3 gap-sm pt-md">
            {[
              { icon: 'eco', label: 'Organic' },
              { icon: 'local_shipping', label: 'Fast Delivery' },
              { icon: 'verified', label: 'Certified' },
            ].map(b => (
              <div key={b.label} className="flex flex-col items-center text-center p-sm bg-surface-container-low rounded-lg">
                <span className="material-symbols-outlined text-primary mb-xs">{b.icon}</span>
                <span className="text-[10px] font-bold uppercase tracking-wider text-outline">{b.label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Related Products */}
      <section className="mt-xxl">
        <div className="flex justify-between items-end mb-lg">
          <h2 className="text-headline-md">Related Products</h2>
          <Link href="/" className="text-primary text-label-lg flex items-center gap-xs hover:underline">
            View all <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
          </Link>
        </div>
        <div className="flex overflow-x-auto gap-gutter pb-lg no-scrollbar snap-x">
          {RELATED_PRODUCTS.map(rp => (
            <div
              key={rp.id}
              className="min-w-[260px] flex-shrink-0 snap-start group border border-outline-variant rounded-xl bg-surface-container-lowest overflow-hidden shadow-sm hover:shadow-lg transition-all"
            >
              <div className="h-48 overflow-hidden">
                <img
                  src={rp.image}
                  alt={rp.name}
                  className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                />
              </div>
              <div className="p-md">
                <h3 className="text-headline-sm text-on-surface">{rp.name}</h3>
                <p className="text-secondary-container font-bold text-lg mt-xs">£{rp.price.toFixed(2)}</p>
                <button className="w-full mt-md py-sm bg-primary-fixed text-on-primary-fixed text-label-lg rounded-lg hover:bg-primary-fixed-dim transition-colors active:scale-95">
                  Add to Cart
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}
