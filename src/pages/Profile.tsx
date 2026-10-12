import { Link } from 'react-router-dom';
import { Sun, Moon, Monitor, LogOut, Shield, ChefHat, Truck, LayoutDashboard, User, ChevronRight } from 'lucide-react';
import { useTheme } from '../lib/theme';
import { signOut } from '../lib/auth';
import { useRole } from '../lib/role';

export default function Profile() {
  const { theme, setTheme } = useTheme();
  const { session, role } = useRole();

  return (
    <div className="page-enter p-4 pb-28">
      {/* Avatar + greeting */}
      <div className="flex items-center gap-4">
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-brand-400 to-brand-600 text-2xl font-bold text-white shadow-lg shadow-brand-500/20">
          {session ? (session.user.email?.[0] ?? 'U').toUpperCase() : <User size={28} />}
        </div>
        <div>
          <h1 className="text-xl font-bold">
            {session ? `Hey there!` : 'Welcome'}
          </h1>
          {session && <div className="text-sm text-neutral-500">{session.user.email}</div>}
          {session && role && <div className="mt-0.5 badge-info capitalize">{role}</div>}
        </div>
      </div>

      {!session && (
        <Link to="/login" className="btn-primary mt-6 w-full">Sign in to your account</Link>
      )}

      {/* Quick links — only show the panel link matching user's role */}
      {session && (
        <div className="mt-6 space-y-2">
          {role === 'admin' && (
            <ProfileLink to="/admin" icon={<LayoutDashboard size={18} />} label="Admin dashboard" desc="Manage everything" />
          )}
          {role === 'vendor' && (
            <ProfileLink to="/vendor" icon={<ChefHat size={18} />} label="Restaurant panel" desc="Orders & menu" />
          )}
          {role === 'delivery' && (
            <ProfileLink to="/partner" icon={<Truck size={18} />} label="Delivery partner" desc="Deliveries & earnings" />
          )}
        </div>
      )}

      {/* Appearance */}
      <div className="card mt-6 p-5">
        <div className="text-xs font-bold uppercase tracking-widest text-neutral-400">Appearance</div>
        <div className="mt-3 grid grid-cols-3 gap-2">
          <ThemeOpt active={theme === 'light'} onClick={() => setTheme('light')} icon={<Sun size={18} />} label="Light" />
          <ThemeOpt active={theme === 'dark'} onClick={() => setTheme('dark')} icon={<Moon size={18} />} label="Dark" />
          <ThemeOpt active={theme === 'system'} onClick={() => setTheme('system')} icon={<Monitor size={18} />} label="System" />
        </div>
      </div>

      {/* Privacy */}
      <div className="card mt-4 p-5">
        <div className="flex items-center gap-2 font-semibold">
          <Shield size={16} className="text-brand-500" /> Privacy
        </div>
        <p className="mt-2 text-xs leading-relaxed text-neutral-500">
          Dastak uses your location only when you ask. We never track you in the background. Your
          address is stored with the order so delivery can be completed and deleted afterwards.
        </p>
      </div>

      {/* Sign out */}
      {session && (
        <button onClick={() => signOut()} className="btn-outline mt-4 w-full text-red-500 hover:border-red-200 hover:bg-red-50 dark:text-red-400 dark:hover:border-red-800 dark:hover:bg-red-500/10">
          <LogOut size={16} /> Sign out
        </button>
      )}
    </div>
  );
}

function ProfileLink({ to, icon, label, desc }: { to: string; icon: React.ReactNode; label: string; desc: string }) {
  return (
    <Link to={to} className="card flex items-center gap-4 p-4 transition-all duration-200 hover:shadow-md hover:-translate-y-0.5">
      <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-brand-50 text-brand-600 dark:bg-brand-600/10">
        {icon}
      </div>
      <div className="flex-1">
        <div className="text-sm font-bold">{label}</div>
        <div className="text-xs text-neutral-500">{desc}</div>
      </div>
      <ChevronRight size={16} className="text-neutral-300 dark:text-neutral-600" />
    </Link>
  );
}

function ThemeOpt({ active, onClick, icon, label }: { active: boolean; onClick: () => void; icon: React.ReactNode; label: string }) {
  return (
    <button
      onClick={onClick}
      className={`flex flex-col items-center gap-1.5 rounded-2xl border-2 px-3 py-3.5 text-xs font-semibold transition-all ${
        active
          ? 'border-brand-500 bg-brand-50 text-brand-700 shadow-sm dark:bg-brand-600/10'
          : 'border-neutral-200 text-neutral-500 hover:border-neutral-300 dark:border-neutral-800 dark:hover:border-neutral-700'
      }`}
    >
      {icon}
      {label}
    </button>
  );
}
