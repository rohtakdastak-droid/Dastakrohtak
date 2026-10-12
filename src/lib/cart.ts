import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export type CartItem = {
  product_id: string;
  name: string;
  unit_price_paise: number;
  quantity: number;
  diet: 'veg' | 'non_veg' | 'egg' | 'unknown';
  options?: { label: string; price_delta_paise: number }[];
};

type CartState = {
  vendorId: string | null;
  vendorName: string | null;
  items: CartItem[];
  pendingSwitch: null | { vendorId: string; vendorName: string; item: CartItem };
  addItem: (vendorId: string, vendorName: string, item: CartItem) => void;
  confirmSwitch: () => void;
  cancelSwitch: () => void;
  updateQty: (productId: string, qty: number) => void;
  remove: (productId: string) => void;
  clear: () => void;
  subtotalPaise: () => number;
};

export const useCart = create<CartState>()(
  persist(
    (set, get) => ({
      vendorId: null,
      vendorName: null,
      items: [],
      pendingSwitch: null,
      addItem(vendorId, vendorName, item) {
        const s = get();
        if (s.vendorId && s.vendorId !== vendorId && s.items.length > 0) {
          set({ pendingSwitch: { vendorId, vendorName, item } });
          return;
        }
        const existing = s.items.find((i) => i.product_id === item.product_id);
        if (existing) {
          set({
            items: s.items.map((i) =>
              i.product_id === item.product_id ? { ...i, quantity: i.quantity + item.quantity } : i
            ),
          });
        } else {
          set({ vendorId, vendorName, items: [...s.items, item] });
        }
      },
      confirmSwitch() {
        const p = get().pendingSwitch;
        if (!p) return;
        set({ vendorId: p.vendorId, vendorName: p.vendorName, items: [p.item], pendingSwitch: null });
      },
      cancelSwitch() {
        set({ pendingSwitch: null });
      },
      updateQty(productId, qty) {
        if (qty <= 0) return get().remove(productId);
        set({ items: get().items.map((i) => (i.product_id === productId ? { ...i, quantity: qty } : i)) });
      },
      remove(productId) {
        const items = get().items.filter((i) => i.product_id !== productId);
        if (items.length === 0) set({ vendorId: null, vendorName: null, items: [] });
        else set({ items });
      },
      clear() {
        set({ vendorId: null, vendorName: null, items: [] });
      },
      subtotalPaise() {
        return get().items.reduce((sum, i) => {
          const addons = (i.options ?? []).reduce((s, o) => s + o.price_delta_paise, 0);
          return sum + (i.unit_price_paise + addons) * i.quantity;
        }, 0);
      },
    }),
    { name: 'dastak.cart' }
  )
);
