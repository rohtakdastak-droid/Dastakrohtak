import { Link } from 'react-router-dom';
import { Plus, Minus, Trash2, ShoppingBag, ArrowRight } from 'lucide-react';
import { useCart } from '../lib/cart';
import { formatRupees } from '../lib/deliveryFee';

export default function Cart() {
  const cart = useCart();

  if (cart.items.length === 0) {
    return (
      <div className="page-enter flex min-h-[60vh] flex-col items-center justify-center p-6 text-center">
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-neutral-100 dark:bg-neutral-800">
          <ShoppingBag size={32} className="text-neutral-400" />
        </div>
        <h1 className="mt-4 text-lg font-bold">Your cart is empty</h1>
        <p className="mt-1 text-sm text-neutral-500">Add items from a restaurant to get started</p>
        <Link to="/" className="btn-primary mt-6">Browse restaurants</Link>
      </div>
    );
  }

  return (
    <div className="page-enter p-4 pb-20">
      <h1 className="text-xl font-bold">Your cart</h1>
      <div className="mt-1 flex items-center gap-2 text-xs text-neutral-500">
        <div className="h-1.5 w-1.5 rounded-full bg-brand-500" />
        from {cart.vendorName}
      </div>

      <div className="mt-5 space-y-3">
        {cart.items.map((item, i) => (
          <div
            key={item.product_id}
            className="card flex items-center justify-between gap-3 p-4 animate-slide-up"
            style={{ animationDelay: `${i * 60}ms`, animationFillMode: 'backwards' }}
          >
            <div className="flex-1">
              <div className="font-bold tracking-tight">{item.name}</div>
              <div className="mt-0.5 text-sm text-neutral-500">{formatRupees(item.unit_price_paise)} each</div>
            </div>
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-1 rounded-2xl border-2 border-brand-500 bg-brand-50 px-1 py-0.5 text-sm font-bold text-brand-700 dark:bg-brand-600/10">
                <button className="flex h-7 w-7 items-center justify-center rounded-xl transition hover:bg-brand-100" onClick={() => cart.updateQty(item.product_id, item.quantity - 1)}>
                  <Minus size={14} />
                </button>
                <span className="w-5 text-center">{item.quantity}</span>
                <button className="flex h-7 w-7 items-center justify-center rounded-xl transition hover:bg-brand-100" onClick={() => cart.updateQty(item.product_id, item.quantity + 1)}>
                  <Plus size={14} />
                </button>
              </div>
              <button onClick={() => cart.remove(item.product_id)} className="rounded-xl p-2 text-neutral-400 transition hover:bg-red-50 hover:text-red-500 dark:hover:bg-red-500/10">
                <Trash2 size={16} />
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Bill */}
      <div className="card mt-5 p-4">
        <div className="text-xs font-bold uppercase tracking-wider text-neutral-400">Bill summary</div>
        <div className="mt-3 flex justify-between text-sm">
          <span className="text-neutral-500">Items subtotal</span>
          <span className="font-bold">{formatRupees(cart.subtotalPaise())}</span>
        </div>
        <div className="mt-2 rounded-xl bg-neutral-50 p-2.5 text-xs text-neutral-500 dark:bg-neutral-800/50">
          Delivery fee will be calculated at checkout based on your address.
        </div>
      </div>

      {/* CTA */}
      <Link to="/checkout" className="btn-primary mt-5 w-full">
        Proceed to checkout <ArrowRight size={16} />
      </Link>
    </div>
  );
}
