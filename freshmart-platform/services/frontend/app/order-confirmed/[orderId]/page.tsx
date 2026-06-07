'use client'

import Link from 'next/link'
import { useParams } from 'next/navigation'

// In production this would be fetched from order-service via getOrder(orderId)
// For now we show a confirmation screen using the orderId from the URL

export default function OrderConfirmedPage() {
  const { orderId } = useParams()

  const orderItems = [
    { name: 'Organic Vine Tomatoes', qty: 1, price: 4.50,
      img: 'https://lh3.googleusercontent.com/aida-public/AB6AXuAZatha4t3u4RXwxseso6tt1KcO8s6hEB0yN3RYIWFJfkr-elv8h5VDwgsw_ZbLmg5v5qyxIhbUihsH3xa-yUeTxdb9kcuGO3dOuWi9BbAtyjqjZe0Zb6OQd_LJF3cWFGI-zNpc1PmohJ69HGPSW-N-2WTb5PL0ebNXvyre4xeIsg10Zqor6H2dn32I5vwSP_2GOm7vrAySYgJvYb0dDNgOyfr2X10xyxC-NPvDb69HKnO5T_NnGSdMBMexuxbu-x9GGRu8FLQj6RFx' },
    { name: 'Premium Baby Spinach', qty: 2, price: 3.00,
      img: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCqh_drbMa2OKjhe4bJ5hZAiUjtodQawvmirEbtBO7ddeiYYeYYxO1nTGeL59tsWqpnQ6kTGqW3ow4939LEzkRc-hIxwx7EhWIuGoPvjtTdei-HoPhDbZplemZebiWVtgN8tXqbWMNFJIV9X0i05Kb94muCN8dx67THdd1Rx9Ggh_tVOKtl672g6fAt78MNaF6PUIDE5G9eWvCbw8BqljqAC2k9z1GLFn_aq10QG25CjdR8cHPokAuLM8ZHfE-0gOzR8rTzqim_SRuJ' },
    { name: 'Extra Virgin Olive Oil', qty: 1, price: 8.99,
      img: 'https://lh3.googleusercontent.com/aida-public/AB6AXuB69UunXrxrh-y_AyDqWZC6-e6oJTSdIqColveKS_asApynLnUjYQ-EEH-0QjrdxAUcX92seTpyoeGS3KiMa5nBhqN0b3kbkiWHttBgcQ9X_t_u25a85XvZMl2TwoXINoPnym2hMZaGXXLYIEeY-L5wiMhX-XUoN1MFOqPwT8mnY3qOt9p6uNagj324OImIT7FXsazey4d6PU_AwB_EcJImPuC1wwt7NrK8PZMBRMhYPCm9_l-B5mYF8HufOryo42uozi_-fALCd1qd' },
  ]
  const subtotal = orderItems.reduce((s, i) => s + i.price, 0)

  return (
    <div className="pt-32 pb-xxl px-margin-mobile md:px-margin-desktop max-w-[800px] mx-auto">

      {/* Success header */}
      <section className="text-center mb-xl">
        <div className="inline-flex items-center justify-center w-24 h-24 bg-primary-container text-on-primary-container rounded-full mb-lg"
          style={{ animation: 'bounceIn 0.8s cubic-bezier(0.175, 0.885, 0.32, 1.275)' }}>
          <span className="material-symbols-outlined text-[48px]" style={{ fontVariationSettings: "'FILL' 1" }}>
            check_circle
          </span>
        </div>
        <h1 className="text-display-lg text-on-surface mb-sm">Order Placed!</h1>
        <p className="text-body-lg text-on-surface-variant max-w-[500px] mx-auto">
          Your order is confirmed and will be delivered within 2–3 days.
        </p>
        <div className="mt-md px-lg py-sm bg-surface-container-high inline-block rounded-lg border border-outline-variant">
          <span className="text-label-lg text-on-surface">
            Order ID: <span className="text-primary font-bold">#{orderId}</span>
          </span>
        </div>
      </section>

      {/* Order summary table */}
      <div className="bg-surface-container-lowest rounded-xl shadow-sm border border-outline-variant overflow-hidden">
        <div className="p-lg bg-surface-container-low border-b border-outline-variant">
          <h2 className="text-headline-sm text-on-surface">Order Summary</h2>
        </div>
        <div className="p-lg">
          <table className="w-full border-collapse">
            <thead>
              <tr className="border-b border-outline-variant">
                <th className="text-left py-md text-label-lg text-on-surface-variant">Item name</th>
                <th className="text-center py-md text-label-lg text-on-surface-variant">Qty</th>
                <th className="text-right py-md text-label-lg text-on-surface-variant">Price</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant">
              {orderItems.map(item => (
                <tr key={item.name}>
                  <td className="py-md">
                    <div className="flex items-center gap-md">
                      <div className="w-12 h-12 rounded-lg bg-surface-container overflow-hidden flex-shrink-0">
                        <img src={item.img} alt={item.name} className="w-full h-full object-cover" />
                      </div>
                      <span className="text-body-md text-on-surface">{item.name}</span>
                    </div>
                  </td>
                  <td className="py-md text-center text-body-md text-on-surface">{item.qty}</td>
                  <td className="py-md text-right text-body-md text-on-surface">£{item.price.toFixed(2)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr>
                <td className="pt-lg pb-md text-right text-body-md text-on-surface-variant" colSpan={2}>Subtotal</td>
                <td className="pt-lg pb-md text-right text-body-md text-on-surface">£{subtotal.toFixed(2)}</td>
              </tr>
              <tr>
                <td className="pb-md text-right text-body-md text-on-surface-variant" colSpan={2}>Delivery</td>
                <td className="pb-md text-right text-body-md text-primary font-bold">FREE</td>
              </tr>
              <tr className="border-t border-outline">
                <td className="py-lg text-right text-headline-sm text-on-surface" colSpan={2}>Total</td>
                <td className="py-lg text-right text-headline-sm text-primary">£{subtotal.toFixed(2)}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>

      {/* CTAs */}
      <div className="mt-xl flex flex-col md:flex-row gap-lg justify-center">
        <button className="px-xxl py-md bg-primary text-on-primary rounded-lg text-label-lg flex items-center justify-center gap-sm hover:brightness-110 active:scale-95 transition-all shadow-md">
          <span className="material-symbols-outlined">local_shipping</span>
          Track Order
        </button>
        <Link
          href="/"
          className="px-xxl py-md border-2 border-primary text-primary rounded-lg text-label-lg flex items-center justify-center gap-sm hover:bg-primary/5 active:scale-95 transition-all"
        >
          Continue Shopping
        </Link>
      </div>

      {/* Delivery + payment bento */}
      <div className="mt-xxl grid grid-cols-1 md:grid-cols-2 gap-gutter">
        <div className="p-lg bg-surface-container-low rounded-xl border border-outline-variant">
          <div className="flex items-center gap-md mb-md">
            <span className="material-symbols-outlined text-primary">location_on</span>
            <h3 className="text-headline-sm text-on-surface">Delivery Address</h3>
          </div>
          <p className="text-body-md text-on-surface-variant">
            John Doe<br />
            221B Baker Street<br />
            London, NW1 6XE<br />
            United Kingdom
          </p>
        </div>
        <div className="p-lg bg-surface-container-low rounded-xl border border-outline-variant">
          <div className="flex items-center gap-md mb-md">
            <span className="material-symbols-outlined text-primary">payments</span>
            <h3 className="text-headline-sm text-on-surface">Payment Method</h3>
          </div>
          <div className="flex items-center gap-md">
            <span className="material-symbols-outlined text-on-surface-variant">credit_card</span>
            <p className="text-body-md text-on-surface-variant">Mastercard ending in •••• 4242</p>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes bounceIn {
          0% { transform: scale(0.5); opacity: 0; }
          100% { transform: scale(1); opacity: 1; }
        }
      `}</style>
    </div>
  )
}
