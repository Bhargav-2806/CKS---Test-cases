import { redirect } from 'next/navigation'

// /products and / both show the product grid
export default function ProductsPage() {
  redirect('/')
}
