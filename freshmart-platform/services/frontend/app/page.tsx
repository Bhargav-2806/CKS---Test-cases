'use client'

import { useEffect, useState } from 'react'
import { Product } from '@/lib/types'
import { getProducts } from '@/lib/api'
import ProductCard from '@/components/ProductCard'

export default function HomePage() {
  const [products, setProducts] = useState<Product[]>([])

  useEffect(() => {
    getProducts().then(setProducts)
  }, [])

  return (
    <>
      {/* ── Hero Banner ─────────────────────────────────────────────────── */}
      <section className="relative w-full overflow-hidden bg-primary-container text-on-primary-container min-h-[400px] flex items-center">
        <div className="absolute inset-0 opacity-40 bg-[radial-gradient(circle_at_50%_50%,_#acf4a4_0%,_transparent_50%)]" />
        <div className="relative px-margin-desktop max-w-container-max mx-auto grid md:grid-cols-2 gap-xl items-center py-xxl">
          <div className="space-y-lg">
            <h1 className="text-display-lg text-on-primary-container leading-tight">
              Fresh groceries,<br />delivered fast.
            </h1>
            <p className="text-body-lg text-primary-fixed-dim opacity-90 max-w-md">
              Quality local produce and household essentials at your doorstep within minutes.
              Experience the future of grocery shopping today.
            </p>
            <button className="bg-surface-container-lowest text-primary text-label-lg px-xl py-md rounded-lg shadow-sm hover:bg-primary-fixed transition-all active:scale-95 inline-flex items-center group">
              Shop Now
              <span className="material-symbols-outlined ml-sm text-[20px] group-hover:translate-x-1 transition-transform">
                arrow_forward
              </span>
            </button>
          </div>
          <div className="hidden md:block relative h-full">
            <img
              alt="Fresh Grocery Hero"
              className="rounded-xl shadow-2xl object-cover w-full h-[320px]"
              src="https://lh3.googleusercontent.com/aida-public/AB6AXuDH_UhwcCj0Gr-OrvM9hhMAeSu72lBbGygf5zg3loe_rSXA__5BxnibUHbFpK8ceydPGJdRU9kHmMtGqUOezIgguTIaTA9YCoC0qOHdXijHuDfYpc5X6wGbeNxJVz-nR75V95ZrY7-TV163LrhLoqct_F0x_WPnB_IY2BJx8ajJ2ZS_B_62gBnQxF63kWndUJgs7EDHSMkf_-2DpkCfaX9Di225lKcdTMlMjxI-ScsHHdpeXQrgzstIhVNCR7em6QFrDj254MxM7XF5"
            />
          </div>
        </div>
      </section>

      {/* ── Product Grid ────────────────────────────────────────────────── */}
      <section className="px-margin-desktop max-w-container-max mx-auto py-xxl">
        <div className="flex items-center justify-between mb-xl">
          <div>
            <h2 className="text-headline-lg text-on-surface">Weekly Freshness</h2>
            <p className="text-body-md text-on-surface-variant">Hand-picked selection of our top quality produce.</p>
          </div>
          <div className="flex gap-sm">
            <button className="p-sm rounded-full border border-outline-variant hover:bg-surface-container transition-colors">
              <span className="material-symbols-outlined text-outline">filter_list</span>
            </button>
            <button className="p-sm rounded-full border border-outline-variant hover:bg-surface-container transition-colors">
              <span className="material-symbols-outlined text-outline">sort</span>
            </button>
          </div>
        </div>

        {products.length === 0 ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-gutter">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="bg-surface-container rounded-lg h-80 animate-pulse" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-gutter">
            {products.map(product => (
              <ProductCard key={product.id} product={product} />
            ))}
          </div>
        )}
      </section>
    </>
  )
}
