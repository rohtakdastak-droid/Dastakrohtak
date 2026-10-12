import { NavLink, Outlet, Link, useNavigate, useLocation } from 'react-router-dom';
import { useState, useEffect } from 'react';
import { LayoutDashboard, ShoppingBag, UtensilsCrossed, Settings, LogOut, Store, Menu, X } from 'lucide-react';
import { useRole } from '../lib/role';
import { signOut } from '../lib/auth';
import { useMyVendors } from '../lib/myVendors';
import NotificationBell from '../components/NotificationBell';
import type { Vendor } from '../lib/supabase';

type Ctx = { vendor: Vendor; setVendor: (v: Vendor) => void };
import { createContext, useContext } from 'react';
const VendorCtx = createContext<Ctx | null>(null);
export const useCurrentVendor = () => {
  const v = useContext(VendorCtx);
  if (!v) throw new Error('useCurrentVendor outside provider');
  return v;
};

const VNAV = [
  { to: '/vendor', end: true, icon: <LayoutDashboard size={18} />, label: 'Dashboard' },
  { to: '/vendor/orders', icon: <ShoppingBag size={18} />, label: 'Orders' },
  { to: '/vendor/menu', icon: <UtensilsCrossed size={18} />, label: 'Menu' },
  { to: '/vendor/profile', icon: <Settings size={18} />, label: 'Profile' },
];

export default function VendorLayout() {
  const navigate = useNavigate();
  const location = useLocation();
  const { session, role, loading: roleLoading } = useRole();
  const { vendors, loading } = useMyVendors();
  const [vendor, setVendor] = useState<Vendor | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => { setMenuOpen(false); }, [location.pathname]);

  useEffect(() => {
    if (vendors.length > 0 && !vendor) setVendor(vendors[0]);
  }, [vendors, vendor]);

  if (roleLoading || loading) return <div className="flex min-h-screen items-center justify-center text-sm text-neutral-500">Loading…</div>;
  if (!session) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center p-6 text-center">
        <div className="text-xl font-bold">Please sign in</div>
        <p className="mt-2 text-sm text-neutral-500">You need to be logged in to access the restaurant panel.</p>
        <button onClick={() => navigate('/login', { replace: true })} className="btn-primary mt-4">Sign in</button>
      </div>
    );
  }
  if (vendors.length === 0) {
    return (
      <div className="mx-auto max-w-md p-10 text-center">
        <div className="text-xl font-bold">No vendor assigned</div>
        <p className="mt-2 text-sm text-neutral-500">
          Your account isn't linked to any restaurant yet. An admin must assign you via the admin dashboard.
        </p>
        <div className="mt-2 text-xs text-neutral-400">Current role: {role}</div>
        <Link to="/" className="btn-outline mt-5 inline-flex">Back to app</Link>
      </div>
    );
  }
  if (!vendor) return null;

  return (
    <VendorCtx.Provider value={{ vendor, setVendor }}>
      <div className="flex min-h-full">
        <aside className="hidden w-64 shrink-0 border-r border-neutral-200 bg-white px-3 py-5 dark:border-neutral-800 dark:bg-neutral-950 md:block">
          <Link to="/vendor" className="flex items-center gap-2 px-3 pb-4">
            <div className="h-8 w-8 rounded-lg bg-gradient-to-br from-brand-500 to-brand-700" />
            <div>
              <div className="text-sm font-bold">Dastak</div>
              <div className="text-[11px] uppercase tracking-wider text-neutral-400">Partner</div>
            </div>
          </Link>

          {vendors.length > 1 && (
            <select
              className="input mb-4"
              value={vendor.id}
              onChange={(e) => {
                const v = vendors.find((x) => x.id === e.target.value);
                if (v) setVendor(v);
              }}
            >
              {vendors.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
            </select>
          )}

          <div className="mb-3 flex items-center gap-2 rounded-xl border border-neutral-200 px-3 py-2 text-sm dark:border-neutral-800">
            <Store size={14} className="text-neutral-400" />
            <div className="min-w-0">
              <div className="truncate font-medium">{vendor.name}</div>
              <div className="truncate text-[11px] text-neutral-500 capitalize">{vendor.category}</div>
            </div>
          </div>

          <nav className="space-y-1 text-sm">
            <Item to="/vendor" end icon={<LayoutDashboard size={16} />}>Dashboard</Item>
            <Item to="/vendor/orders" icon={<ShoppingBag size={16} />}>Orders</Item>
            <Item to="/vendor/menu" icon={<UtensilsCrossed size={16} />}>Menu</Item>
            <Item to="/vendor/profile" icon={<Settings size={16} />}>Profile</Item>
          </nav>

          <button onClick={() => signOut()} className="btn-ghost mt-6 w-full justify-start">
            <LogOut size={16} /> Sign out
          </button>
        </aside>

        {/* Mobile top bar */}
        <div className="md:hidden sticky top-0 z-30 flex items-center justify-between border-b border-neutral-200 bg-white px-4 py-2.5 dark:border-neutral-800 dark:bg-neutral-950">
          <Link to="/vendor" className="min-w-0 truncate text-sm font-bold">{vendor.name}</Link>
          <div className="flex items-center gap-2">
            <NotificationBell orderLinkBase="/vendor/orders" />
            <Link to="/" className="text-xs text-brand-600 font-medium">App</Link>
            <button onClick={() => setMenuOpen(!menuOpen)} className="flex h-8 w-8 items-center justify-center rounded-lg bg-neutral-100 dark:bg-neutral-800">
              {menuOpen ? <X size={16} /> : <Menu size={16} />}
            </button>
          </div>
        </div>

        {/* Mobile dropdown menu */}
        {menuOpen && (
          <div className="border-b border-neutral-200 bg-white px-4 py-3 dark:border-neutral-800 dark:bg-neutral-950 md:hidden">
            <nav className="grid grid-cols-2 gap-2">
              {VNAV.map((n) => (
                <NavLink
                  key={n.to}
                  to={n.to}
                  end={n.end}
                  onClick={() => setMenuOpen(false)}
                  className={({ isActive }) =>
                    `flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-medium ${
                      isActive ? 'bg-brand-50 text-brand-700 dark:bg-brand-600/15 dark:text-brand-300' : 'bg-neutral-50 text-neutral-600 dark:bg-neutral-900 dark:text-neutral-300'
                    }`
                  }
                >
                  {n.icon} {n.label}
                </NavLink>
              ))}
            </nav>
            <button onClick={() => { signOut(); setMenuOpen(false); }} className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl bg-red-50 px-3 py-2.5 text-xs font-medium text-red-600 dark:bg-red-500/10 dark:text-red-400">
              <LogOut size={14} /> Sign out
            </button>
          </div>
        )}

        <main className="min-w-0 flex-1 p-4 md:px-8 md:py-6">
          <div className="hidden md:flex md:items-center md:justify-end md:mb-2">
            <NotificationBell orderLinkBase="/vendor/orders" />
          </div>
          <Outlet />
        </main>
      </div>
    </VendorCtx.Provider>
  );
}

function Item({ to, icon, end, children }: { to: string; icon: React.ReactNode; end?: boolean; children: React.ReactNode }) {
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        `flex items-center gap-2 rounded-xl px-3 py-2 ${
          isActive ? 'bg-brand-50 font-semibold text-brand-700 dark:bg-brand-600/15 dark:text-brand-300' : 'text-neutral-700 hover:bg-neutral-100 dark:text-neutral-200 dark:hover:bg-neutral-900'
        }`
      }
    >
      {icon}
      {children}
    </NavLink>
  );
}
