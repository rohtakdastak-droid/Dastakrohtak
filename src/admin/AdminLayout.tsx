import { NavLink, Outlet, useNavigate, Link } from 'react-router-dom';
import {
  LayoutDashboard, Store, ShoppingBag, Wallet, Bike, Settings, History, LogOut, Package
} from 'lucide-react';
import { useRole } from '../lib/role';
import { signOut } from '../lib/auth';
import NotificationBell from '../components/NotificationBell';

export default function AdminLayout() {
  const { role, loading, session } = useRole();
  const navigate = useNavigate();

  if (loading) return <div className="p-10 text-sm text-neutral-500">Loading…</div>;
  if (!session) {
    navigate('/login', { replace: true });
    return null;
  }
  if (role !== 'admin') {
    return (
      <div className="mx-auto max-w-md p-10 text-center">
        <div className="text-xl font-bold">Admin access required</div>
        <p className="mt-2 text-sm text-neutral-500">
          Your account doesn't have admin role. Ask an admin to promote your account, or run:
        </p>
        <pre className="mt-3 overflow-x-auto rounded-xl bg-neutral-100 p-3 text-left text-xs dark:bg-neutral-900">
{`update profiles set role = 'admin'
where id = '${session.user.id}';`}
        </pre>
        <Link to="/" className="btn-outline mt-5 inline-flex">Back to app</Link>
      </div>
    );
  }

  return (
    <div className="flex min-h-full">
      {/* Sidebar */}
      <aside className="hidden w-64 shrink-0 border-r border-neutral-200 bg-white px-3 py-5 dark:border-neutral-800 dark:bg-neutral-950 md:block">
        <Link to="/admin" className="flex items-center gap-2 px-3 pb-6">
          <div className="h-8 w-8 rounded-lg bg-gradient-to-br from-brand-500 to-brand-700" />
          <div>
            <div className="text-sm font-bold">Dastak</div>
            <div className="text-[11px] uppercase tracking-wider text-neutral-400">Admin</div>
          </div>
        </Link>
        <nav className="space-y-1 text-sm">
          <Item to="/admin" end icon={<LayoutDashboard size={16} />}>Overview</Item>
          <Item to="/admin/vendors" icon={<Store size={16} />}>Restaurants</Item>
          <Item to="/admin/products" icon={<Package size={16} />}>Products</Item>
          <Item to="/admin/orders" icon={<ShoppingBag size={16} />}>Orders</Item>
          <Item to="/admin/payments" icon={<Wallet size={16} />}>Payments</Item>
          <Item to="/admin/partners" icon={<Bike size={16} />}>Delivery Partners</Item>
          <Item to="/admin/settings" icon={<Settings size={16} />}>Settings</Item>
          <Item to="/admin/audit" icon={<History size={16} />}>Audit Log</Item>
        </nav>
        <button onClick={() => signOut()} className="btn-ghost mt-6 w-full justify-start">
          <LogOut size={16} /> Sign out
        </button>
      </aside>

      {/* Mobile top bar */}
      <div className="md:hidden fixed inset-x-0 top-0 z-30 flex items-center justify-between border-b border-neutral-200 bg-white px-4 py-2.5 dark:border-neutral-800 dark:bg-neutral-950">
        <Link to="/admin" className="font-bold">Dastak Admin</Link>
        <div className="flex items-center gap-1">
          <NotificationBell orderLinkBase="/admin/orders" />
          <MobileNav />
        </div>
      </div>

      {/* Main */}
      <main className="min-w-0 flex-1 px-4 pb-16 pt-16 md:pt-6 md:px-8">
        <div className="hidden md:flex md:items-center md:justify-end md:mb-2">
          <NotificationBell orderLinkBase="/admin/orders" />
        </div>
        <Outlet />
      </main>
    </div>
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

function MobileNav() {
  return (
    <select
      className="input py-1.5"
      onChange={(e) => (window.location.href = e.target.value)}
      defaultValue={window.location.pathname}
    >
      <option value="/admin">Overview</option>
      <option value="/admin/vendors">Restaurants</option>
      <option value="/admin/products">Products</option>
      <option value="/admin/orders">Orders</option>
      <option value="/admin/payments">Payments</option>
      <option value="/admin/partners">Delivery Partners</option>
      <option value="/admin/settings">Settings</option>
      <option value="/admin/audit">Audit Log</option>
    </select>
  );
}
