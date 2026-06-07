import Link from 'next/link'

export default function OrdersPage() {
  return (
    <div className="pt-24 pb-xxl px-margin-desktop max-w-container-max mx-auto text-center">
      <span className="material-symbols-outlined text-[80px] text-outline-variant block mb-lg">receipt_long</span>
      <h1 className="text-headline-lg text-on-surface mb-md">Your Orders</h1>
      <p className="text-body-md text-on-surface-variant mb-xl">Order history will appear here once connected to the order service.</p>
      <Link href="/" className="inline-flex items-center gap-sm bg-primary text-on-primary text-label-lg px-xl py-md rounded-lg hover:brightness-110 transition-all">
        <span className="material-symbols-outlined text-[18px]">arrow_back</span>
        Back to Shopping
      </Link>
    </div>
  )
}
