'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useCart } from '@/context/CartContext'

export default function Header() {
  const pathname = usePathname()
  const { count } = useCart()

  const navLinks = [
    { href: '/',         label: 'Home' },
    { href: '/products', label: 'Products' },
    { href: '/orders',   label: 'Orders' },
  ]

  const isActive = (href: string) =>
    href === '/' ? pathname === '/' : pathname.startsWith(href)

  return (
    <header className="fixed top-0 w-full z-50 bg-surface-container-lowest shadow-sm border-b border-outline-variant h-16">
      <div className="flex justify-between items-center h-full px-margin-desktop max-w-container-max mx-auto">

        {/* Logo */}
        <Link href="/" className="text-headline-md font-black text-primary">
          FreshMart
        </Link>

        {/* Nav */}
        <nav className="hidden md:flex items-center gap-xl">
          {navLinks.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className={`text-label-lg transition-colors active:scale-95 duration-150 ${
                isActive(href)
                  ? 'text-primary border-b-2 border-primary pb-1'
                  : 'text-on-surface-variant hover:text-primary'
              }`}
            >
              {label}
            </Link>
          ))}
        </nav>

        {/* Actions */}
        <div className="flex items-center gap-lg">
          {/* Search (md+) */}
          <div className="hidden lg:flex items-center bg-surface-container rounded-full px-md py-xs border border-outline-variant gap-sm">
            <span className="material-symbols-outlined text-outline text-[20px]">search</span>
            <input
              type="text"
              placeholder="Search groceries..."
              className="bg-transparent border-none focus:ring-0 text-body-sm w-40 outline-none"
            />
          </div>

          {/* Cart */}
          <Link
            href="/cart"
            className="relative flex items-center justify-center p-sm hover:bg-surface-container rounded-full transition-colors active:scale-95 duration-150"
          >
            <span className="material-symbols-outlined text-primary">shopping_cart</span>
            {count > 0 && (
              <span className="absolute -top-1 -right-1 bg-secondary text-on-secondary text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center">
                {count > 99 ? '99+' : count}
              </span>
            )}
          </Link>

          {/* Account */}
          <button className="flex items-center justify-center p-sm hover:bg-surface-container rounded-full transition-colors active:scale-95 duration-150">
            <span className="material-symbols-outlined text-primary">person</span>
          </button>
        </div>
      </div>
    </header>
  )
}
