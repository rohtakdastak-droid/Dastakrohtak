import { Routes, Route, Link, useLocation } from 'react-router-dom';
import { Home as HomeIcon, ShoppingBag, Receipt, User } from 'lucide-react';
import Home from './pages/Home';
import Vendor from './pages/Vendor';
import Cart from './pages/Cart';
import Checkout from './pages/Checkout';
import Orders from './pages/Orders';
import OrderDetail from './pages/OrderDetail';
import Profile from './pages/Profile';
import Login from './pages/Login';
import AdminLayout from './admin/AdminLayout';
import Overview from './admin/pages/Overview';
import AdminVendors from './admin/pages/Vendors';
import AdminProducts from './admin/pages/Products';
import AdminOrders from './admin/pages/Orders';
import AdminPayments from './admin/pages/Payments';
import AdminPartners from './admin/pages/Partners';
import AdminSettings from './admin/pages/Settings';
import AdminAudit from './admin/pages/AuditLog';
import VendorLayout from './vendor/VendorLayout';
import VendorDashboard from './vendor/pages/VendorDashboard';
import VendorOrders from './vendor/pages/VendorOrders';
import VendorOrderDetail from './vendor/pages/VendorOrderDetail';
import VendorMenu from './vendor/pages/VendorMenu';
import VendorProfile from './vendor/pages/VendorProfile';
import PartnerLayout from './partner/PartnerLayout';
import Available from './partner/pages/Available';
import Active from './partner/pages/Active';
import Earnings from './partner/pages/Earnings';
import PartnerProfile from './partner/pages/PartnerProfile';
import { useCart } from './lib/cart';

export default function App() {
  const location = useLocation();
  const isAdmin = location.pathname.startsWith('/admin');
  const isPartner = location.pathname.startsWith('/partner');
  // Vendor panel paths: /vendor, /vendor/orders, /vendor/menu, /vendor/profile. The customer
  // vendor-detail page is /vendor/:uuid — distinguished by its route segment.
  const isPanelVendor =
    location.pathname === '/vendor' ||
    /^\/vendor\/(orders|menu|profile)(\/.*)?$/.test(location.pathname);
  const isLogin = location.pathname === '/login';
  const hideNav = isLogin || isAdmin || isPanelVendor || isPartner;
  const itemCount = useCart((s) => s.items.reduce((n, i) => n + i.quantity, 0));

  if (isLogin) {
    return (
      <div className="h-screen">
        <Routes>
          <Route path="/login" element={<Login />} />
        </Routes>
      </div>
    );
  }

  if (isAdmin) {
    return (
      <Routes>
        <Route path="/admin" element={<AdminLayout />}>
          <Route index element={<Overview />} />
          <Route path="vendors" element={<AdminVendors />} />
          <Route path="products" element={<AdminProducts />} />
          <Route path="orders" element={<AdminOrders />} />
          <Route path="payments" element={<AdminPayments />} />
          <Route path="partners" element={<AdminPartners />} />
          <Route path="settings" element={<AdminSettings />} />
          <Route path="audit" element={<AdminAudit />} />
        </Route>
      </Routes>
    );
  }

  if (isPanelVendor) {
    return (
      <Routes>
        <Route path="/vendor" element={<VendorLayout />}>
          <Route index element={<VendorDashboard />} />
          <Route path="orders" element={<VendorOrders />} />
          <Route path="orders/:id" element={<VendorOrderDetail />} />
          <Route path="menu" element={<VendorMenu />} />
          <Route path="profile" element={<VendorProfile />} />
        </Route>
      </Routes>
    );
  }

  if (isPartner) {
    return (
      <Routes>
        <Route path="/partner" element={<PartnerLayout />}>
          <Route index element={<Available />} />
          <Route path="active" element={<Active />} />
          <Route path="earnings" element={<Earnings />} />
          <Route path="profile" element={<PartnerProfile />} />
        </Route>
      </Routes>
    );
  }

  return (
    <div className="mx-auto flex min-h-full max-w-xl flex-col pb-20 sm:max-w-2xl">
      <main className="flex-1">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/vendor/:id" element={<Vendor />} />
          <Route path="/cart" element={<Cart />} />
          <Route path="/checkout" element={<Checkout />} />
          <Route path="/orders" element={<Orders />} />
          <Route path="/orders/:id" element={<OrderDetail />} />
          <Route path="/profile" element={<Profile />} />
          <Route path="/login" element={<Login />} />
        </Routes>
      </main>

      {!hideNav && (
        <nav className="fixed inset-x-0 bottom-0 z-40 mx-auto flex max-w-xl items-center justify-around border-t border-neutral-200/80 bg-white/95 px-2 py-1.5 backdrop-blur-xl dark:border-neutral-800/80 dark:bg-neutral-950/95 sm:max-w-2xl">
          <TabLink to="/" icon={<HomeIcon size={20} />} label="Home" />
          <TabLink to="/cart" icon={<ShoppingBag size={20} />} label="Cart" badge={itemCount} />
          <TabLink to="/orders" icon={<Receipt size={20} />} label="Orders" />
          <TabLink to="/profile" icon={<User size={20} />} label="Profile" />
        </nav>
      )}
    </div>
  );
}

function TabLink({ to, icon, label, badge }: { to: string; icon: React.ReactNode; label: string; badge?: number }) {
  const { pathname } = useLocation();
  const active = pathname === to || (to !== '/' && pathname.startsWith(to));
  return (
    <Link
      to={to}
      className={`relative flex flex-col items-center gap-0.5 rounded-2xl px-5 py-2 text-[11px] font-semibold transition-all duration-200 ${
        active
          ? 'text-brand-600'
          : 'text-neutral-400 hover:text-neutral-600 dark:text-neutral-500 dark:hover:text-neutral-300'
      }`}
    >
      <div className={`transition-transform duration-200 ${active ? 'scale-110' : ''}`}>{icon}</div>
      <span>{label}</span>
      {active && <div className="absolute -top-1.5 h-1 w-6 rounded-full bg-brand-500" />}
      {!!badge && badge > 0 && (
        <span className="absolute right-2 top-0 min-w-[18px] rounded-full bg-brand-500 px-1 text-center text-[10px] font-bold leading-[18px] text-white shadow-sm shadow-brand-500/30">
          {badge}
        </span>
      )}
    </Link>
  );
}
