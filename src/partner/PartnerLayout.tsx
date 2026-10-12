import { NavLink, Outlet, Link, useNavigate } from 'react-router-dom';
import { Bike, Package, Wallet, User, LogOut } from 'lucide-react';
import { useRole } from '../lib/role';
import { signOut } from '../lib/auth';
import { usePartner } from '../lib/partner';
import NotificationBell from '../components/NotificationBell';

export default function PartnerLayout() {
  const navigate = useNavigate();
  const { session, role, loading: roleLoading } = useRole();
  const { data, loading } = usePartner();

  if (roleLoading || loading) return <div className="p-10 text-sm text-neutral-500">Loading…</div>;
  if (!session) {
    navigate('/login', { replace: true });
    return null;
  }

  if (role !== 'delivery') {
    return (
      <div className="mx-auto max-w-md p-10 text-center">
        <div className="text-xl font-bold">Delivery partner access required</div>
        <p className="mt-2 text-sm text-neutral-500">
          Your account isn't a delivery partner. Ask an admin to assign the delivery role from the admin dashboard.
        </p>
        <div className="mt-2 text-xs text-neutral-400">Current role: {role}</div>
        <Link to="/" className="btn-outline mt-5 inline-flex">Back to app</Link>
      </div>
    );
  }

  return (
    <div className="mx-auto flex min-h-full max-w-xl flex-col pb-20 sm:max-w-2xl">
      <header className="flex items-center justify-between border-b border-neutral-200 px-4 py-3 dark:border-neutral-800">
        <Link to="/partner" className="flex items-center gap-2">
          <div className="h-7 w-7 rounded-lg bg-gradient-to-br from-brand-500 to-brand-700" />
          <div>
            <div className="text-sm font-bold">Dastak</div>
            <div className="text-[10px] uppercase tracking-wider text-neutral-400">Rider</div>
          </div>
        </Link>
        <div className="flex items-center gap-1">
          <NotificationBell orderLinkBase="/partner" />
          <button className="btn-ghost" onClick={() => signOut()} aria-label="Sign out">
            <LogOut size={16} />
          </button>
        </div>
      </header>

      {data?.status === 'pending' && (
        <div className="m-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-800 dark:bg-amber-500/10 dark:text-amber-200">
          Your account is awaiting admin approval. You can set up your profile below, but new orders won't be assigned to you yet.
        </div>
      )}
      {data?.status === 'suspended' && (
        <div className="m-4 rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">
          Your account is suspended. Contact admin.
        </div>
      )}

      <main className="flex-1 px-4 py-4">
        <Outlet />
      </main>

      <nav className="fixed inset-x-0 bottom-0 z-40 mx-auto flex max-w-xl justify-around border-t border-neutral-200 bg-white/90 py-2 backdrop-blur dark:border-neutral-800 dark:bg-neutral-950/90 sm:max-w-2xl">
        <Tab to="/partner" end icon={<Bike size={20} />} label="Available" />
        <Tab to="/partner/active" icon={<Package size={20} />} label="Active" />
        <Tab to="/partner/earnings" icon={<Wallet size={20} />} label="Earnings" />
        <Tab to="/partner/profile" icon={<User size={20} />} label="Profile" />
      </nav>
    </div>
  );
}

function Tab({ to, icon, label, end }: { to: string; icon: React.ReactNode; label: string; end?: boolean }) {
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        `flex flex-col items-center gap-0.5 rounded-xl px-4 py-1.5 text-xs font-medium ${
          isActive ? 'text-brand-600' : 'text-neutral-500 dark:text-neutral-400'
        }`
      }
    >
      {icon}
      <span>{label}</span>
    </NavLink>
  );
}
