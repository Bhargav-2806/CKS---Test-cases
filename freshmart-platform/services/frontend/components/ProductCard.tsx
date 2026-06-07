'use client'

import Link from 'next/link'
import { Product } from '@/lib/types'
import { useCart } from '@/context/CartContext'

interface ProductCardProps {
  product: Product
}

export default function ProductCard({ product }: ProductCardProps) {
  const { addItem } = useCart()

  return (
    <div className="product-card-hover bg-surface-container-lowest border border-outline-variant rounded-lg p-md transition-all duration-300 flex flex-col h-full group">
      {/* Image */}
      <Link href={`/products/${product.id}`} className="block">
        <div className="relative overflow-hidden rounded-lg mb-md aspect-square bg-surface-container cursor-pointer">
          <img
            src={product.image}
            alt={product.name}
            className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110"
          />
          <span className="absolute top-2 left-2 bg-primary-fixed text-on-primary-fixed-variant text-[10px] font-bold px-2 py-1 rounded-full uppercase tracking-wider">
            {product.category}
          </span>
        </div>
      </Link>

      {/* Info */}
      <div className="flex-grow">
        <Link href={`/products/${product.id}`}>
          <h3 className="text-headline-sm text-on-surface mb-xs hover:text-primary transition-colors">
            {product.name}
          </h3>
        </Link>
        <p className="text-primary font-bold text-lg">£{product.price.toFixed(2)}</p>
      </div>

      {/* CTA */}
      <button
        onClick={() => addItem(product)}
        className="mt-md w-full bg-primary text-on-primary text-label-lg py-3 rounded-lg flex items-center justify-center gap-2 hover:bg-primary-container transition-colors active:scale-95"
      >
        <span className="material-symbols-outlined text-[18px]">add_shopping_cart</span>
        Add to Cart
      </button>
    </div>
  )
}
