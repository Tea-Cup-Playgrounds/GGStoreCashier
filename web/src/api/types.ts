// Response shapes of the API endpoints the back-office uses. Money and quantities that MySQL returns
// as DECIMAL arrive as strings ("85000.00"); format them with lib/format.

export type Money = string | number;

export interface Pagination {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

// ── users & access ──

export interface UserAssignment {
  location_id: number | null;
  location_code: string | null;
  location_name: string | null;
  location_type: 'branch' | 'warehouse' | null;
  role_id: number;
  role_code: string | null;
  role_name: string;
}

export interface ManagedUser {
  id: number;
  name: string;
  username: string;
  is_active: boolean;
  last_active_at: string | null;
  created_at: string;
  updated_at: string;
  assignments: UserAssignment[];
}

export interface Role {
  id: number;
  code: string | null;
  name: string;
  description: string | null;
  isSystem: boolean;
  userCount: number;
  permissions: string[];
}

export interface PermissionInfo {
  key: string;
  group: string;
  description: string;
}

// ── catalog ──

export type ProductKind = 'goods' | 'service' | 'digital';
export type SerialType = 'imei' | 'imei_dual' | 'serial';

export interface Variant {
  id: number;
  product_id: number;
  sku: string;
  barcode: string | null;
  name: string | null;
  attributes: Record<string, string> | null;
  base_price: Money;
  min_price: Money | null;
  is_active: boolean;
  // With location_id:
  on_hand?: number;
  sell_price?: Money;
  location_price?: Money | null;
  avg_cost?: Money;
}

export interface LocationStock {
  location_id: number;
  location_code: string;
  location_name: string;
  location_type: 'branch' | 'warehouse';
  variant_id: number;
  on_hand: number;
  location_price: Money | null;
  sell_price: Money;
  avg_cost?: Money;
  reorder_level: number | null;
}

export interface Product {
  id: number;
  name: string;
  description: string | null;
  category_id: number | null;
  category_name: string | null;
  brand_id: number | null;
  brand_name: string | null;
  kind: ProductKind;
  is_serialized: boolean;
  serial_type: SerialType | null;
  warranty_months: number;
  tax_rate_id: number | null;
  image: string | null;
  is_active: boolean;
  variants: Variant[];
  stock?: LocationStock[];
}

export interface Category {
  id: number;
  name: string;
  description: string | null;
  category_image: string | null;
}

export interface Brand {
  id: number;
  name: string;
}

export interface TaxRate {
  id: number;
  name: string;
  rate: Money;
  is_active: boolean;
}

// ── stock ──

export interface StockRow {
  variant_id: number;
  sku: string;
  barcode: string | null;
  name: string;
  product_id: number;
  is_serialized: boolean;
  serial_type: SerialType | null;
  category_name: string | null;
  brand_name: string | null;
  on_hand: number;
  reorder_level: number | null;
  base_price: Money;
  location_price: Money | null;
  sell_price: Money;
  avg_cost?: Money;
}

export type UnitStatus = 'in_stock' | 'in_transit' | 'reserved' | 'sold' | 'returned' | 'in_service' | 'defective' | 'written_off';
export type Grade = 'new' | 'A' | 'B' | 'C';

export interface Unit {
  id: string;
  variant_id: number;
  name: string;
  sku: string;
  location_id: number | null;
  location_code: string | null;
  location_name: string | null;
  imei1: string | null;
  imei2: string | null;
  serial_number: string | null;
  status: UnitStatus;
  condition_grade: Grade;
  unit_cost?: Money;
  sell_price: Money;
  source_type: string;
  warranty_until: string | null;
  notes: string | null;
  created_at: string;
}

export interface Movement {
  id: string;
  variant_id: number;
  name: string;
  sku: string;
  unit_id: string | null;
  imei1: string | null;
  serial_number: string | null;
  qty_change: number;
  unit_cost?: Money;
  reason: string;
  ref_type: string | null;
  ref_id: string | null;
  note: string | null;
  user_name: string | null;
  created_at: string;
}

// ── purchasing ──

export interface Supplier {
  id: number;
  code: string | null;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  notes: string | null;
  is_active: boolean;
  outstanding: Money;
}

export type PaymentStatus = 'unpaid' | 'partial' | 'paid';

export interface ReceiptSummary {
  id: string;
  number: string;
  supplier_id: number;
  supplier_name: string;
  location_id: number;
  location_code: string;
  location_name: string;
  invoice_no: string | null;
  invoice_date: string | null;
  due_date: string | null;
  status: 'draft' | 'posted';
  subtotal: Money;
  tax_total: Money;
  grand_total: Money;
  paid_total: Money;
  payment_status: PaymentStatus;
  item_qty: number;
  created_at: string;
}

export interface ReceiptUnit {
  id: string;
  imei1: string | null;
  imei2: string | null;
  serial_number: string | null;
  condition_grade: Grade;
  unit_id: string | null;
}

export interface ReceiptItem {
  id: string;
  variant_id: number;
  name: string;
  sku: string;
  is_serialized: boolean;
  serial_type: SerialType | null;
  qty: number;
  unit_cost: Money;
  tax_rate: Money;
  tax_amount: Money;
  line_total: Money;
  units: ReceiptUnit[];
}

export interface SupplierPayment {
  id: string;
  amount: Money;
  method: 'cash' | 'transfer' | 'giro' | 'other';
  reference: string | null;
  paid_at: string;
  note: string | null;
  created_by_name: string | null;
}

export interface Receipt extends ReceiptSummary {
  supplier_code: string | null;
  location_type: 'branch' | 'warehouse';
  note: string | null;
  created_by_name: string | null;
  posted_by_name: string | null;
  posted_at: string | null;
  items: ReceiptItem[];
  payments: SupplierPayment[];
}

// ── transfers ──

export type TransferStatus = 'draft' | 'sent' | 'received' | 'partially_received' | 'cancelled';

export interface TransferSummary {
  id: string;
  number: string;
  status: TransferStatus;
  from_location_id: number;
  from_code: string;
  from_name: string;
  to_location_id: number;
  to_code: string;
  to_name: string;
  note: string | null;
  qty_total: number;
  sent_at: string | null;
  received_at: string | null;
  resolved_at: string | null;
  created_at: string;
}

export interface TransferUnit {
  unit_id: string;
  outcome: 'received' | 'returned' | 'written_off' | null;
  imei1: string | null;
  imei2: string | null;
  serial_number: string | null;
  status: UnitStatus;
  condition_grade: Grade;
}

export interface TransferItem {
  id: string;
  variant_id: number;
  name: string;
  sku: string;
  is_serialized: boolean;
  qty_sent: number;
  qty_received: number | null;
  qty_resolved: number;
  units: TransferUnit[];
  outstanding: number;
}

export interface Transfer extends TransferSummary {
  created_by_name: string | null;
  sent_by_name: string | null;
  received_by_name: string | null;
  receive_note?: string | null;
  items: TransferItem[];
}

// ── stock counts ──

export interface OpnameSummary {
  id: string;
  number: string;
  location_id: number;
  location_code: string;
  location_name: string;
  status: 'counting' | 'approved' | 'cancelled';
  category_name: string | null;
  note: string | null;
  created_at: string;
  approved_at: string | null;
  item_count: number;
}

export interface OpnameItem {
  id: string;
  variant_id: number;
  name: string;
  sku: string;
  barcode: string | null;
  is_serialized: boolean;
  system_qty: number;
  counted_qty: number | null;
  variance: number | null;
  found_units: number;
  note: string | null;
  units: Array<{ unit_id: string; found: boolean; imei1: string | null; imei2: string | null; serial_number: string | null; status: UnitStatus }>;
}

export interface Opname extends OpnameSummary {
  created_by_name: string | null;
  approved_by_name: string | null;
  items: OpnameItem[];
  extras: Array<{ id: string; identifier: string; unit_id: string | null; unit_status: string | null; unit_location_code: string | null; unit_name: string | null; created_at: string }>;
}

// ── sales ──

export type SaleStatus = 'completed' | 'voided' | 'partially_returned' | 'returned';

export interface SaleSummary {
  id: string;
  number: string;
  location_id: number;
  location_code: string;
  cashier_id: number | null;
  cashier_name: string | null;
  customer_id: string | null;
  customer_name: string | null;
  grand_total: Money;
  refunded_total: Money;
  status: SaleStatus;
  occurred_at: string;
  line_count: number;
  payment_methods: string | null;
}

export interface SaleLine {
  id: string;
  line_type: 'goods' | 'service' | 'digital' | 'fee';
  variant_id: number | null;
  unit_id: string | null;
  description: string;
  qty: number;
  unit_price: Money;
  discount: Money;
  tax_rate: Money;
  tax_amount: Money;
  line_total: Money;
  returned_qty: number;
  warranty_until: string | null;
  sku: string | null;
  imei1: string | null;
  imei2: string | null;
  serial_number: string | null;
}

export interface Sale extends SaleSummary {
  location_name: string;
  customer_phone: string | null;
  voucher_code: string | null;
  subtotal: Money;
  discount_total: Money;
  tax_total: Money;
  paid_total: Money;
  change_total: Money;
  note: string | null;
  void_reason?: string | null;
  lines: SaleLine[];
  payments: Array<{ id: string; payment_method_id: number; method_name: string; method_type: string; amount: Money; reference: string | null }>;
  returns: Array<{ id: string; number: string; refund_total: Money; reason: string; created_at: string; refund_method: string; created_by_name: string | null }>;
}

export interface PaymentMethod {
  id: number;
  name: string;
  type: 'cash' | 'qris' | 'ewallet' | 'card' | 'transfer';
  requires_reference: boolean;
  location_id: number | null;
  sort_order: number;
  is_active: boolean;
  account_code: string;
}

export interface CashSession {
  id: string;
  status: 'open' | 'closed';
  location_id?: number;
  location_name?: string;
  opened_at: string;
  closed_at: string | null;
  opening_cash: Money;
  expected_cash: Money | null;
  counted_cash: Money | null;
  difference: Money | null;
  opened_by_name: string | null;
  closed_by_name?: string | null;
  note?: string | null;
  summary?: {
    sales_count: number;
    sales_total: number;
    change_total: number;
    cash_refunds: number;
    expected_cash: number;
    by_method: Array<{ id: number; name: string; type: string; amount: number; sales: number }>;
  };
}

export interface Customer {
  id: string;
  code: string | null;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  id_number?: string | null;
  notes?: string | null;
  created_at: string;
}

export interface Voucher {
  id: number;
  code: string;
  description: string | null;
  target_type: 'product' | 'category' | null;
  target_id: number | null;
  discount_type: 'percent' | 'fixed';
  discount_value: Money;
  valid_from: string | null;
  valid_to: string | null;
  is_active: number | boolean;
}

// ── accounting ──

export type AccountType = 'asset' | 'liability' | 'equity' | 'income' | 'expense';

export interface Account {
  id: number;
  code: string;
  name: string;
  type: AccountType;
  parent_id: number | null;
  parent_code: string | null;
  is_postable: boolean;
  is_system: boolean;
  is_active: boolean;
}

export interface JournalSummary {
  id: string;
  number: string;
  entry_date: string;
  location_id: number | null;
  location_code: string | null;
  source_type: string;
  source_id: string | null;
  memo: string | null;
  status: 'posted' | 'void';
  reverses_entry_id: string | null;
  created_by_name: string | null;
  created_at: string;
  amount: number;
}

export interface Journal extends JournalSummary {
  lines: Array<{ id: string; account_id: number; account_code: string; account_name: string; location_id: number | null; debit: Money; credit: Money; memo: string | null }>;
}

export interface Balance {
  id: number;
  code: string;
  name: string;
  type: AccountType;
  debit: number;
  credit: number;
  balance: number;
}
