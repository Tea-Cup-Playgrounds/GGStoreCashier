import { createBrowserRouter, Link } from 'react-router';
import { RequireAuth } from './auth/AuthContext';
import type { ReactNode } from 'react';
import { AppShell, Guard } from './components/AppShell';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';
import { UsersPage } from './pages/admin/UsersPage';
import { RolesPage } from './pages/admin/RolesPage';
import { LocationsPage } from './pages/admin/LocationsPage';
import { ProductsPage } from './pages/catalog/ProductsPage';
import { ProductDetailPage } from './pages/catalog/ProductDetailPage';
import { CategoriesPage, TaxRatesPage } from './pages/catalog/CategoriesPage';
import { StockPage } from './pages/stock/StockPage';
import { UnitsPage } from './pages/stock/UnitsPage';
import { MovementsPage } from './pages/stock/MovementsPage';
import { SuppliersPage } from './pages/purchasing/SuppliersPage';
import { ReceiptsPage } from './pages/purchasing/ReceiptsPage';
import { ReceiptPage } from './pages/purchasing/ReceiptPage';
import { TransfersPage } from './pages/transfers/TransfersPage';
import { TransferPage } from './pages/transfers/TransferPage';
import { OpnamesPage } from './pages/opnames/OpnamesPage';
import { OpnamePage } from './pages/opnames/OpnamePage';
import { SalesPage } from './pages/sales/SalesPage';
import { SaleDetailPage } from './pages/sales/SaleDetailPage';
import { ShiftsPage } from './pages/sales/ShiftsPage';
import { CustomersPage } from './pages/sales/CustomersPage';
import { VouchersPage } from './pages/sales/VouchersPage';
import { AnalyticsPage } from './pages/sales/AnalyticsPage';
import { PaymentMethodsPage } from './pages/sales/PaymentMethodsPage';
import { JournalsPage } from './pages/accounting/JournalsPage';
import { ProfitLossPage, TrialBalancePage } from './pages/accounting/ReportsPages';
import { AccountsPage, MappingsPage, PeriodsPage } from './pages/accounting/AccountsPages';

const page = (menuPath: string, element: ReactNode) => <Guard to={menuPath}>{element}</Guard>;

function NotFound() {
  return (
    <div className="py-20 text-center">
      <h1 className="text-lg font-semibold">Halaman tidak ditemukan</h1>
      <Link to="/" className="mt-2 inline-block text-sm text-brand-700 underline">
        Kembali ke dashboard
      </Link>
    </div>
  );
}

export const router = createBrowserRouter([
  { path: '/login', element: <LoginPage /> },
  {
    element: <RequireAuth />,
    children: [
      {
        element: <AppShell />,
        children: [
          { index: true, element: <DashboardPage /> },
          { path: 'users', element: page('/users', <UsersPage />) },
          { path: 'roles', element: page('/roles', <RolesPage />) },
          { path: 'locations', element: page('/locations', <LocationsPage />) },
          { path: 'settings/tax-rates', element: page('/settings/tax-rates', <TaxRatesPage />) },
          { path: 'catalog', element: page('/catalog', <ProductsPage />) },
          { path: 'catalog/:id', element: page('/catalog', <ProductDetailPage />) },
          { path: 'categories', element: page('/categories', <CategoriesPage />) },
          { path: 'stock', element: page('/stock', <StockPage />) },
          { path: 'units', element: page('/units', <UnitsPage />) },
          { path: 'movements', element: page('/movements', <MovementsPage />) },
          { path: 'suppliers', element: page('/suppliers', <SuppliersPage />) },
          { path: 'receipts', element: page('/receipts', <ReceiptsPage />) },
          { path: 'receipts/:id', element: page('/receipts', <ReceiptPage />) },
          { path: 'transfers', element: page('/transfers', <TransfersPage />) },
          { path: 'transfers/:id', element: page('/transfers', <TransferPage />) },
          { path: 'opnames', element: page('/opnames', <OpnamesPage />) },
          { path: 'opnames/:id', element: page('/opnames', <OpnamePage />) },
          { path: 'sales', element: page('/sales', <SalesPage />) },
          { path: 'sales/:id', element: page('/sales', <SaleDetailPage />) },
          { path: 'shifts', element: page('/shifts', <ShiftsPage />) },
          { path: 'customers', element: page('/customers', <CustomersPage />) },
          { path: 'vouchers', element: page('/vouchers', <VouchersPage />) },
          { path: 'analytics', element: page('/analytics', <AnalyticsPage />) },
          { path: 'settings/payment-methods', element: page('/settings/payment-methods', <PaymentMethodsPage />) },
          { path: 'accounting/journals', element: page('/accounting/journals', <JournalsPage />) },
          { path: 'accounting/trial-balance', element: page('/accounting/trial-balance', <TrialBalancePage />) },
          { path: 'accounting/profit-loss', element: page('/accounting/profit-loss', <ProfitLossPage />) },
          { path: 'accounting/accounts', element: page('/accounting/accounts', <AccountsPage />) },
          { path: 'accounting/periods', element: page('/accounting/periods', <PeriodsPage />) },
          { path: 'accounting/mappings', element: page('/accounting/mappings', <MappingsPage />) },
          { path: '*', element: <NotFound /> },
        ],
      },
    ],
  },
]);
