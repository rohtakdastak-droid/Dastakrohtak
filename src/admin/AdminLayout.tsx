import { NavLink, Outlet, useNavigate, Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard, Store, ShoppingBag, Wallet, Bike, Settings, History, LogOut, Package, Menu, X
} from 'lucide-react';
import { useRole } from '../lib/role';
import { signOut } from '../lib/auth';
import { useState, useEffect } from 'react';

const NAV = [
  { to: '/admin', end: true, icon: <LayoutDashboard size={18} />, label: 'Overview' },
  { to: '/admin/vendors', icon: <Store size={18} />, label: 'Restaurants' },
  { to: '/admin/products', icon: <Package size={18} />, label: 'Products' },
  { to: '/admin/orders', icon: <ShoppingBag size={18} />, label: 'Orders' },
  { to: '/admin/payments', icon: <Wallet size={18} />, label: 'Payments' },
  { to: '/admin/partners', icon: <Bike size={18} />, label: 'Partners' },
  { to: '/admin/settings', icon: <Settings size={18} />, label: 'Settings' },
  { to: '/admin/audit', icon: <History size={18} />, label: 'Audit Log' },
];

export default function AdminLayout() {
  const { role, loading, session } = useRole();
  const navigate = useNavigate();
  const location = useLocation();
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => { setMenuOpen(false); }, [location.pathname]);

  if (loading) return <div className="flex min-h-screen items-center justify-center text-sm text-neutral-500">Loading…</div>;

  if (!session) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center p-6 text-center">
        <div className="text-xl font-bold">Please sign in</div>
        <p className="mt-2 text-sm text-neutral-500">You need to be logged in to access the admin panel.</p>
        <button onClick={() => navigate('/login', { replace: true })} className="btn-primary mt-4">Sign in</button>
      </div>
    );
  }

  if (role !== 'admin') {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center p-6 text-center">
        <div className="text-xl font-bold">Admin access required</div>
        <p className="mt-2 text-sm text-neutral-500">Your account doesn't have admin role.</p>
        <p className="mt-1 text-xs text-neutral-400">Current role: {role ?? 'unknown'}</p>
        <Link to="/" className="btn-outline mt-5">Back to app</Link>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      {/* Desktop sidebar */}
      <aside className="hidden w-60 shrink-0 border-r border-neutral-200 bg-white px-3 py-5 dark:border-neutral-800 dark:bg-neutral-950 md:block">
        <Link to="/admin" className="flex items-center gap-2 px-3 pb-5">
          <div className="h-8 w-8 rounded-lg bg-gradient-to-br from-brand-500 to-brand-700" />
          <div>
            <div className="text-sm font-bold">Dastak</div>
            <div className="text-[10px] uppercase tracking-wider text-neutral-400">Admin</div>
          </div>
        </Link>
        <nav className="space-y-0.5 text-sm">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) =>
                `flex items-center gap-2 rounded-xl px-3 py-2 ${
                  isActive ? 'bg-brand-50 font-semibold text-brand-700 dark:bg-brand-600/15 dark:text-brand-300' : 'text-neutral-600 hover:bg-neutral-100 dark:text-neutral-300 dark:hover:bg-neutral-900'
                }`
              }
            >
              {n.icon} {n.label}
            </NavLink>
          ))}
        </nav>
        <button onClick={() => signOut()} className="mt-6 flex w-full items-center gap-2 rounded-xl px-3 py-2 text-sm text-neutral-500 hover:bg-neutral-100 dark:hover:bg-neutral-900">
          <LogOut size={16} /> Sign out
        </button>
      </aside>

      {/* Mobile top bar + scrollable chip nav */}
      <div className="sticky top-0 z-30 border-b border-neutral-200 bg-white/95 backdrop-blur dark:border-neutral-800 dark:bg-neutral-950/95 md:hidden">
        <div className="flex items-center justify-between px-4 py-3">
          <Link to="/admin" className="flex items-center gap-2">
            <div className="h-7 w-7 rounded-lg bg-gradient-to-br from-brand-500 to-brand-700" />
            <div className="text-sm font-bold">Dastak Admin</div>
          </Link>
          <div className="flex items-center gap-2">
            <Link to="/" className="text-xs font-semibold text-brand-600">Open app</Link>
            <button onClick={() => setMenuOpen(!menuOpen)} className="flex h-9 w-9 items-center justify-center rounded-xl bg-neutral-100 dark:bg-neutral-800">
              {menuOpen ? <X size={16} /> : <Menu size={16} />}
            </button>
          </div>
        </div>
        {/* Always-visible scrollable chip nav */}
        <nav className="flex gap-2 overflow-x-auto px-4 pb-3 scrollbar-none">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) =>
                `inline-flex shrink-0 items-center gap-1.5 rounded-full px-3.5 py-2 text-xs font-semibold transition-all active:scale-95 ${
                  isActive
                    ? 'bg-brand-600 text-white shadow-md shadow-brand-500/30'
                    : 'bg-neutral-100 text-neutral-700 hover:bg-neutral-200 dark:bg-neutral-800 dark:text-neutral-200'
                }`
              }
            >
              {n.icon} {n.label}
            </NavLink>
          ))}
        </nav>
      </div>

      {/* Mobile overflow menu (sign out) */}
      {menuOpen && (
        <div className="border-b border-neutral-200 bg-white px-4 py-3 dark:border-neutral-800 dark:bg-neutral-950 md:hidden">
          <button onClick={() => { signOut(); setMenuOpen(false); }} className="flex w-full items-center justify-center gap-2 rounded-xl bg-red-50 px-3 py-2.5 text-xs font-medium text-red-600 dark:bg-red-500/10 dark:text-red-400">
            <LogOut size={14} /> Sign out
          </button>
        </div>
      )}

      {/* Main content */}
      <main className="min-w-0 flex-1 p-4 md:p-6">
        <Outlet />
      </main>
    </div>
  );
}
