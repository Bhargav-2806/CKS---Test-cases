import Link from 'next/link'

export default function Footer() {
  return (
    <footer className="bg-surface-container w-full py-xxl mt-xxl border-t border-outline-variant">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-gutter px-margin-desktop max-w-container-max mx-auto">

        {/* Brand */}
        <div className="flex flex-col gap-md">
          <div className="text-headline-sm font-bold text-primary">FreshMart</div>
          <p className="text-body-sm text-on-surface-variant max-w-[200px]">
            Bringing the freshest produce directly from local farms to your kitchen.
          </p>
        </div>

        {/* Shop */}
        <div className="flex flex-col gap-sm">
          <h4 className="text-label-lg text-on-surface mb-xs">Shop</h4>
          {['Vegetables', 'Fruits', 'Bakery', 'Dairy'].map(cat => (
            <Link key={cat} href="/" className="text-label-sm text-on-surface-variant hover:text-secondary transition-colors">
              {cat}
            </Link>
          ))}
        </div>

        {/* Company */}
        <div className="flex flex-col gap-sm">
          <h4 className="text-label-lg text-on-surface mb-xs">Company</h4>
          {['About Us', 'Careers', 'Sustainability', 'Contact Us'].map(item => (
            <Link key={item} href="#" className="text-label-sm text-on-surface-variant hover:text-secondary transition-colors">
              {item}
            </Link>
          ))}
        </div>

        {/* Newsletter */}
        <div className="flex flex-col gap-md">
          <h4 className="text-label-lg text-on-surface mb-xs">Newsletter</h4>
          <p className="text-body-sm text-on-surface-variant">Get fresh deals delivered daily.</p>
          <div className="flex gap-xs">
            <input
              type="email"
              placeholder="Your email"
              className="bg-surface-container-lowest border border-outline-variant rounded px-sm py-xs text-body-sm focus:outline-none focus:border-primary w-full"
            />
            <button className="bg-primary text-on-primary px-md py-xs rounded text-label-sm hover:brightness-110 transition-all whitespace-nowrap">
              Join
            </button>
          </div>
        </div>
      </div>

      {/* Bottom bar */}
      <div className="px-margin-desktop max-w-container-max mx-auto mt-xl pt-lg border-t border-outline-variant flex flex-col md:flex-row justify-between items-center gap-md">
        <p className="text-label-sm text-on-surface-variant">© 2024 FreshMart. All rights reserved.</p>
        <div className="flex gap-lg">
          <Link href="#" className="text-label-sm text-on-surface-variant hover:text-secondary transition-colors">Privacy Policy</Link>
          <Link href="#" className="text-label-sm text-on-surface-variant hover:text-secondary transition-colors">Terms of Service</Link>
          <Link href="#" className="text-label-sm text-on-surface-variant hover:text-secondary transition-colors">FAQs</Link>
        </div>
      </div>
    </footer>
  )
}
