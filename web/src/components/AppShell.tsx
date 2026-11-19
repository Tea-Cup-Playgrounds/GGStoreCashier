import { useState, type ComponentType, type ReactNode } from 'react';
import { NavLink, Outlet } from 'react-router';
import {
  ArrowLeftRight,
  BarChart3,
  BookOpen,
  BookText,
  CalendarRange,
  Coins,
  PiggyBank,
  Library,
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
      { to: '/reports/monthly', label: 'Rekap Bulanan', icon: CalendarRange, visible: (a) => a.canAny('reports.view_location', 'reports.view_all', 'accounting.view') },
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
      { to: '/accounting/expenses', label: 'Biaya', icon: Wallet, visible: (a) => a.canAny('expenses.manage', 'accounting.view') },
      { to: '/accounting/pulsa-deposit', label: 'Deposit Pulsa', icon: Coins, visible: (a) => a.canAny('expenses.manage', 'accounting.view') },
      { to: '/accounting/journals', label: 'Jurnal', icon: BookOpen, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/opening-balances', label: 'Saldo Awal', icon: PiggyBank, visible: (a) => a.can('accounting.view') },
      // Also for branch managers: their own location's statements (reports.view_location).
      { to: '/accounting/balance-sheet', label: 'Neraca', icon: Library, visible: (a) => a.canAny('accounting.view', 'reports.view_location') },
      { to: '/accounting/profit-loss', label: 'Laba Rugi', icon: FileSpreadsheet, visible: (a) => a.canAny('accounting.view', 'reports.view_location') },
      { to: '/accounting/trial-balance', label: 'Neraca Saldo', icon: Scale, visible: (a) => a.can('accounting.view') },
      { to: '/accounting/ledger', label: 'Buku Besar', icon: BookText, visible: (a) => a.can('accounting.view') },
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
      <div className="mx-auto max-w-md py-20 text-center">
        <div className="mx-auto mb-4 flex size-14 items-center justify-center rounded-lg bg-ink-900">
          <Lock className="size-7 text-brand-500" />
        </div>
        <h1 className="text-xl font-extrabold text-ink-900">Tidak ada akses</h1>
        <p className="mt-1 text-sm text-stone-500">Role Anda tidak memiliki izin untuk halaman ini. Minta admin menambahkan izinnya.</p>
      </div>
    );
  }
  return <>{children}</>;
}

function Sidebar({ access, onNavigate }: { access: Access; onNavigate?: () => void }) {
  return (
    <nav aria-label="Menu utama" className="flex-1 overflow-y-auto px-3 py-4 hideScrollbar">
      {NAV.map((group) => {
        const items = group.items.filter((i) => i.visible(access));
        if (items.length === 0) return null;
        return (
          <div key={group.title} className="mb-5">
            {/* #a3a3a3 on the black panel: 8:1. */}
            <div className="px-2.5 pb-1.5 text-[11px] font-bold tracking-widest text-[#a3a3a3] uppercase">{group.title}</div>
            {items.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                onClick={onNavigate}
                className={({ isActive }) =>
                  cx(
                    'flex items-center gap-2.5 rounded-md px-2.5 py-2 text-sm font-semibold transition-colors',
                    isActive ? 'bg-brand-500 text-ink-900' : 'text-white hover:bg-white/10',
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

/** Flat logo mark: black "GG" on a yellow square. */
export function BrandMark({ size = 'md' }: { size?: 'md' | 'lg' }) {
  return (
    <div
      aria-hidden
      className={cx(
        'flex shrink-0 items-center justify-center rounded-md bg-brand-500 font-black tracking-tight text-ink-900',
        size === 'lg' ? 'size-12 text-lg' : 'size-9 text-sm',
      )}
    >
      GG
    </div>
  );
}

const initials = (name?: string | null) => {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  return (parts.length === 1 ? parts[0][0] : parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

export function AppShell() {
  const { user, access, logout } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);

  const panel = (onNavigate?: () => void) => (
    <div className="flex h-full w-64 flex-col bg-ink-900">
      <div className="flex items-center gap-3 border-b-2 border-white/10 px-5 py-4">
        <BrandMark />
        <div>
          <div className="text-base font-extrabold text-white">GG Store</div>
          <div className="text-xs font-semibold text-[#a3a3a3]">Back-office</div>
        </div>
      </div>
      <Sidebar access={access} onNavigate={onNavigate} />
      <div className="border-t-2 border-white/10 p-3">
        <div className="flex items-center gap-3 px-1">
          <div className="flex size-9 shrink-0 items-center justify-center rounded-md border-2 border-brand-500 text-xs font-extrabold text-brand-500">
            {initials(user?.name)}
          </div>
          <div className="min-w-0">
            <div className="truncate text-sm font-bold text-white">{user?.name}</div>
            <div className="truncate text-xs font-semibold text-[#a3a3a3]">{access.roleLabel}</div>
          </div>
        </div>
        <button
          type="button"
          onClick={() => logout()}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-md border-2 border-white/25 py-2 text-sm font-bold text-white hover:border-white hover:bg-white hover:text-ink-900"
        >
          <LogOut className="size-4" /> Keluar
        </button>
      </div>
    </div>
  );

  return (
    <div className="flex h-full">
      <aside className="hidden shrink-0 lg:block">{panel()}</aside>
      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label="Menu">
          <div className="absolute inset-0 bg-ink-900/60" onClick={() => setMobileOpen(false)} />
          <div className="relative h-full w-64">{panel(() => setMobileOpen(false))}</div>
        </div>
      )}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center gap-3 border-b-2 border-ink-900 bg-ink-900 px-4 py-3 text-white lg:hidden">
          <button
            type="button"
            onClick={() => setMobileOpen(true)}
            aria-label="Buka menu"
            className="flex size-10 items-center justify-center rounded-md hover:bg-white/10"
          >
            {mobileOpen ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
          <BrandMark />
          <span className="text-sm font-extrabold">GG Store Back-office</span>
        </header>
        <main className="min-w-0 flex-1 overflow-y-auto px-4 py-6 lg:px-8">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
