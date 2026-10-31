import { useState, type ComponentType, type ReactNode } from 'react';
import { NavLink, Outlet } from 'react-router';
import {
  ArrowLeftRight,
  BarChart3,
  BookOpen,
  Boxes,
  Building2,
  ClipboardCheck,
  Clock,
  CreditCard,
  FileSpreadsheet,
  History,
  Landmark,
  LayoutDashboard,
  ListTree,
  LogOut,
  Menu,
  Percent,
  Receipt,
  ScanBarcode,
  Scale,
  ShieldCheck,
  ShoppingBag,
  Smartphone,
  Tags,
  Ticket,
  Truck,
  Users,
  UserRound,
  Wallet,
  Lock,
  X,
} from 'lucide-react';
import { useAuth } from '../auth/AuthContext';
import type { Access } from '../auth/access';
import { cx } from './ui';

interface NavItem {
  to: string;
  label: string;
  icon: ComponentType<{ className?: string }>;
  visible: (a: Access) => boolean;
}

// Menu entries appear only for users who hold a permission that the page needs (the API checks again).
const NAV: Array<{ title: string; items: NavItem[] }> = [
  {
    title: 'Ringkasan',
    items: [
      { to: '/', label: 'Dashboard', icon: LayoutDashboard, visible: () => true },
      { to: '/analytics', label: 'Analitik', icon: BarChart3, visible: (a) => a.can('reports.view_all') },
    ],
  },
  {
    title: 'Penjualan',
    items: [
      { to: '/sales', label: 'Penjualan', icon: ShoppingBag, visible: (a) => a.canAny('sales.create', 'reports.view_location', 'sales.void') },
      { to: '/shifts', label: 'Shift Kasir', icon: Clock, visible: (a) => a.can('sales.create') },
      { to: '/customers', label: 'Pelanggan', icon: UserRound, visible: (a) => a.canAny('sales.create', 'customers.manage') },
      { to: '/vouchers', label: 'Voucher', icon: Ticket, visible: (a) => a.can('vouchers.manage') },
    ],
  },
  {
    title: 'Katalog & Stok',
    items: [
      { to: '/catalog', label: 'Produk', icon: Smartphone, visible: (a) => a.can('catalog.view') },
      { to: '/categories', label: 'Kategori & Merek', icon: Tags, visible: (a) => a.can('catalog.view') },
      { to: '/stock', label: 'Stok', icon: Boxes, visible: (a) => a.can('stock.view') },
      { to: '/units', label: 'Unit IMEI/Serial', icon: ScanBarcode, visible: (a) => a.can('stock.view') },
      { to: '/movements', label: 'Riwayat Stok', icon: History, visible: (a) => a.can('stock.view') },
    ],
  },
  {
    title: 'Gudang & Pembelian',
    items: [
      { to: '/receipts', label: 'Penerimaan Barang', icon: Truck, visible: (a) => a.can('purchases.manage') },
      { to: '/suppliers', label: 'Supplier', icon: Building2, visible: (a) => a.canAny('suppliers.manage', 'purchases.manage') },
      { to: '/transfers', label: 'Transfer Stok', icon: ArrowLeftRight, visible: (a) => a.can('stock.view') },
      { to: '/opnames', label: 'Stok Opname', icon: ClipboardCheck, visible: (a) => a.can('stock.view') },
    ],
  },
  {
    title: 'Akuntansi',
    items: [
      { to: '/accounting/journals', label: 'Jurnal', icon: BookOpen, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/trial-balance', label: 'Neraca Saldo', icon: Scale, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/profit-loss', label: 'Laba Rugi', icon: FileSpreadsheet, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/accounts', label: 'Bagan Akun', icon: ListTree, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/periods', label: 'Periode', icon: Landmark, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/mappings', label: 'Pemetaan Akun', icon: Receipt, visible: (a) => a.can('accounting.view') },
    ],
  },
  {
    title: 'Pengaturan',
    items: [
      { to: '/users', label: 'Pengguna', icon: Users, visible: (a) => a.can('users.manage') },
      { to: '/roles', label: 'Role & Izin', icon: ShieldCheck, visible: (a) => a.canAny('roles.manage', 'users.manage') },
      { to: '/locations', label: 'Lokasi', icon: Building2, visible: () => true },
      { to: '/settings/payment-methods', label: 'Metode Pembayaran', icon: CreditCard, visible: (a) => a.can('settings.manage') },
      { to: '/settings/tax-rates', label: 'Tarif Pajak', icon: Percent, visible: (a) => a.can('settings.manage') },
    ],
  },
];

/** Renders a page only for users who may open it (same rule as its menu entry); the API checks again. */
export function Guard({ to, children }: { to: string; children: ReactNode }) {
  const { access } = useAuth();
  const item = NAV.flatMap((g) => g.items).find((i) => i.to === to);
  if (item && !item.visible(access)) {
    return (
      <div className="py-20 text-center text-stone-600">
        <Lock className="mx-auto mb-3 size-8 text-stone-400" />
        <h1 className="text-lg font-semibold text-stone-800">Tidak ada akses</h1>
        <p className="mt-1 text-sm">Role Anda tidak memiliki izin untuk halaman ini.</p>
      </div>
    );
  }
  return <>{children}</>;
}

function Sidebar({ access, onNavigate }: { access: Access; onNavigate?: () => void }) {
  return (
    <nav className="flex-1 overflow-y-auto px-3 py-4">
      {NAV.map((group) => {
        const items = group.items.filter((i) => i.visible(access));
        if (items.length === 0) return null;
        return (
          <div key={group.title} className="mb-5">
            <div className="px-2 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-stone-500">{group.title}</div>
            {items.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                onClick={onNavigate}
                className={({ isActive }) =>
                  cx(
                    'flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm transition-colors',
                    isActive ? 'bg-brand-500/15 font-medium text-brand-500' : 'text-stone-300 hover:bg-white/5 hover:text-white',
                  )
                }
              >
                <item.icon className="size-4 shrink-0" />
                {item.label}
              </NavLink>
            ))}
          </div>
        );
      })}
    </nav>
  );
}

export function AppShell() {
  const { user, access, logout } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);

  const panel = (onNavigate?: () => void) => (
    <div className="flex h-full w-64 flex-col bg-ink-900">
      <div className="flex items-center gap-2 border-b border-white/10 px-5 py-4">
        <Wallet className="size-5 text-brand-500" />
        <div>
          <div className="text-sm font-semibold text-white">GG Store</div>
          <div className="text-xs text-stone-400">Back-office</div>
        </div>
      </div>
      <Sidebar access={access} onNavigate={onNavigate} />
      <div className="border-t border-white/10 px-4 py-3">
        <div className="truncate text-sm font-medium text-white">{user?.name}</div>
        <div className="truncate text-xs text-stone-400">{access.roleLabel}</div>
        <button
          type="button"
          onClick={() => logout()}
          className="mt-2 inline-flex items-center gap-1.5 text-xs text-stone-400 hover:text-white"
        >
          <LogOut className="size-3.5" /> Keluar
        </button>
      </div>
    </div>
  );

  return (
    <div className="flex h-full">
      <aside className="hidden shrink-0 lg:block">{panel()}</aside>
      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setMobileOpen(false)} />
          <div className="relative h-full w-64">{panel(() => setMobileOpen(false))}</div>
        </div>
      )}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center gap-3 border-b border-stone-200 bg-white px-4 py-3 lg:hidden">
          <button type="button" onClick={() => setMobileOpen(true)} aria-label="Menu" className="rounded-md p-1 hover:bg-stone-100">
            {mobileOpen ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
          <span className="text-sm font-semibold">GG Store Back-office</span>
        </header>
        <main className="min-w-0 flex-1 overflow-y-auto px-4 py-6 lg:px-8">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
