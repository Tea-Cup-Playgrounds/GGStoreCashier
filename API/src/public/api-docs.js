// ── Endpoint definitions ──────────────────────────────────────────────────────
// auth: 'public' | 'required' (any signed-in user) | 'owner' | a permission key (see API/src/auth/permissions.js).
// Permissions are checked at the request's location (location_id in params, query or body, or the
// X-Location-Id header); list endpoints are scoped to the locations where the user holds them.
const J = { name: 'Authorization', value: 'Bearer <token>', required: true };
const loc = (desc = 'Location id') => ({ name: 'location_id', type: 'number', required: true, desc });

const groups = [
  {
    name: 'Authentication', icon: '🔐', prefix: '/api/auth',
    endpoints: [
      {
        method: 'POST', path: '/api/auth/login', auth: 'public',
        desc: 'Login with username & password. Returns a JWT (Flutter app) and the user\'s per-location access, and sets an httpOnly SameSite=Lax token cookie (web back-office).',
        body: [
          { name: 'username', type: 'string', required: true, desc: 'Account username' },
          { name: 'password', type: 'string', required: true, desc: 'Account password' },
        ],
        response: {
          message: 'Login berhasil',
          user: { id: 8, name: 'Manager Satu', username: 'mgr1' },
          access: { isOwner: false, assignments: [{ locationId: 1, locationName: 'Cabang Satu', locationType: 'branch', roleId: 2, roleCode: 'branch_manager', roleName: 'Branch Manager', permissions: ['sales.create', '...'] }] },
          token: '<jwt>',
        },
        errors: [{ code: 401, msg: 'Wrong credentials / account disabled' }, { code: 429, msg: 'Too many failed attempts' }],
      },
      { method: 'POST', path: '/api/auth/logout', auth: 'required', desc: 'Clears the token cookie.', response: { message: 'Berhasil keluar' }, errors: [] },
      {
        method: 'GET', path: '/api/auth/me', auth: 'required', headers: [J],
        desc: 'Current user and access (assignments with permissions). locationId null = every location.',
        response: { user: { id: 8, name: 'Manager Satu', username: 'mgr1', last_active_at: '2026-10-31T10:00:00.000Z' }, access: { isOwner: false, assignments: [] } },
        errors: [{ code: 401, msg: 'Invalid token / account disabled' }],
      },
    ]
  },
  {
    name: 'Users', icon: '👥', prefix: '/api/users',
    endpoints: [
      {
        method: 'GET', path: '/api/users', auth: 'users.manage',
        desc: 'Users with their assignments. Non-owners only see non-owner users assigned to a location they manage.',
        query: [
          { name: 'search', type: 'string', required: false, desc: 'Name or username' },
          { name: 'location_id', type: 'number', required: false, desc: 'Assigned at this location (global assignments included)' },
          { name: 'role_id', type: 'number', required: false, desc: 'Has this role somewhere' },
          { name: 'include_inactive', type: 'boolean', required: false, desc: 'true to include deactivated users' },
          { name: 'page', type: 'number', required: false, desc: 'Default 1' },
          { name: 'limit', type: 'number', required: false, desc: 'Default 10, max 100' },
        ],
        response: { users: [{ id: 9, name: 'Kasir Satu', username: 'kasir1', is_active: true, assignments: [{ location_id: 1, location_code: 'BR01', location_name: 'Cabang Satu', location_type: 'branch', role_id: 3, role_code: 'cashier', role_name: 'Cashier' }] }], pagination: { page: 1, limit: 10, total: 1, totalPages: 1 } },
        errors: [{ code: 403, msg: 'No users.manage permission' }],
      },
      { method: 'GET', path: '/api/users/:id', auth: 'users.manage', desc: 'One user with assignments.', errors: [{ code: 403, msg: 'User is an owner or not at your locations' }, { code: 404, msg: 'Not found' }] },
      {
        method: 'POST', path: '/api/users', auth: 'users.manage',
        desc: 'Create a user. At least one assignment is required; you can only grant roles whose permissions you hold at that location.',
        body: [
          { name: 'name', type: 'string', required: true, desc: '2–50 letters' },
          { name: 'username', type: 'string', required: true, desc: '3–30 chars [a-zA-Z0-9_.-]' },
          { name: 'password', type: 'string', required: true, desc: 'Min 8 chars, 3 of: upper, lower, digit, symbol' },
          { name: 'assignments', type: 'array', required: true, desc: '[{ location_id: number|null, role_id }] — null = every location (owner only)' },
        ],
        response: { message: 'Pengguna berhasil dibuat', userId: 12, user: { id: 12, assignments: [] } },
        errors: [{ code: 400, msg: 'Validation / username taken / weak password (passwordRequirements)' }, { code: 403, msg: 'Location or role you may not grant' }],
      },
      {
        method: 'PUT', path: '/api/users/:id', auth: 'users.manage',
        desc: 'Update name, username, password, is_active and/or assignments. A non-owner only replaces assignments at their own locations.',
        body: [
          { name: 'name', type: 'string', required: false, desc: '' },
          { name: 'username', type: 'string', required: false, desc: '' },
          { name: 'password', type: 'string', required: false, desc: 'Empty = unchanged' },
          { name: 'is_active', type: 'boolean', required: false, desc: 'false disables login' },
          { name: 'assignments', type: 'array', required: false, desc: '[{ location_id, role_id }]' },
        ],
        errors: [{ code: 400, msg: 'Validation / own assignments or own deactivation' }, { code: 403, msg: 'User not manageable by you' }],
      },
      {
        method: 'DELETE', path: '/api/users/:id', auth: 'users.manage',
        desc: 'Deletes a user without history; a user with history is deactivated instead. A manager who only manages some of the user\'s locations just removes those assignments.',
        response: { message: '...', deleted: false, deactivated: true },
        errors: [{ code: 400, msg: 'Cannot delete yourself' }],
      },
      { method: 'POST', path: '/api/users/check-password-strength', auth: 'users.manage', desc: 'Scores a password.', body: [{ name: 'password', type: 'string', required: true, desc: '' }], response: { isValid: true, score: 5, requirements: {} }, errors: [] },
    ]
  },
  {
    name: 'Access (roles & assignments)', icon: '🛡️', prefix: '/api/access',
    endpoints: [
      { method: 'GET', path: '/api/access/permissions', auth: 'users.manage', desc: 'All permission keys with group and description (roles.manage also allowed).', errors: [] },
      { method: 'GET', path: '/api/access/roles', auth: 'users.manage', desc: 'Roles with permissions and user counts (roles.manage also allowed).', errors: [] },
      { method: 'POST', path: '/api/access/roles', auth: 'roles.manage', desc: 'Create a custom role.', body: [{ name: 'name', type: 'string', required: true, desc: '' }, { name: 'description', type: 'string', required: false, desc: '' }, { name: 'permissions', type: 'array', required: false, desc: 'Keys you hold yourself' }], errors: [] },
      { method: 'PUT', path: '/api/access/roles/:id', auth: 'roles.manage', desc: 'Update a role (system roles keep their name; owner is fixed).', errors: [] },
      { method: 'DELETE', path: '/api/access/roles/:id', auth: 'roles.manage', desc: 'Delete an unused custom role.', errors: [] },
      { method: 'GET', path: '/api/access/users/:id/assignments', auth: 'users.manage', desc: 'A user\'s assignments.', errors: [] },
      { method: 'PUT', path: '/api/access/users/:id/assignments', auth: 'users.manage', desc: 'Replace assignments (same rules as PUT /api/users/:id).', body: [{ name: 'assignments', type: 'array', required: true, desc: '[{ location_id, role_id }]' }], errors: [] },
    ]
  },
  {
    name: 'Locations', icon: '🏪', prefix: '/api/locations',
    endpoints: [
      { method: 'GET', path: '/api/locations', auth: 'required', desc: 'Locations you are assigned to (all for owners). ?type=branch|warehouse, ?include_inactive=true, ?scope=destinations (transfers.create: every location, short form).', response: { locations: [{ id: 1, code: 'BR01', name: 'Cabang Satu', type: 'branch', is_active: true }] }, errors: [] },
      { method: 'GET', path: '/api/locations/:id', auth: 'required', desc: 'One location you are assigned to.', errors: [{ code: 403, msg: 'Not assigned there' }, { code: 404, msg: 'Not found' }] },
      { method: 'POST', path: '/api/locations', auth: 'locations.manage', desc: 'Create a branch or warehouse (locations.manage at every location, i.e. owners).', body: [{ name: 'code', type: 'string', required: true, desc: '2–10 chars A–Z 0–9 -' }, { name: 'name', type: 'string', required: true, desc: '' }, { name: 'type', type: 'string', required: false, desc: 'branch | warehouse' }, { name: 'address', type: 'string', required: false, desc: '' }, { name: 'phone', type: 'string', required: false, desc: '' }, { name: 'settings', type: 'object', required: false, desc: 'Receipt header etc.' }], errors: [] },
      { method: 'PUT', path: '/api/locations/:id', auth: 'locations.manage', desc: 'Update name/address/phone/settings with locations.manage there; code and is_active (deactivate — locations are never deleted) need it at every location.', errors: [] },
    ]
  },
  {
    name: 'Catalog', icon: '📦', prefix: '/api/catalog',
    endpoints: [
      { method: 'GET', path: '/api/catalog/products', auth: 'catalog.view', desc: 'Products with variants; with location_id adds on_hand and the location price.', query: [{ name: 'location_id', type: 'number', required: false, desc: '' }, { name: 'search', type: 'string', required: false, desc: 'Name, SKU or barcode' }, { name: 'category_id', type: 'number', required: false, desc: '' }, { name: 'kind', type: 'string', required: false, desc: 'goods | service | digital' }], errors: [] },
      { method: 'GET', path: '/api/catalog/products/:id', auth: 'catalog.view', desc: 'One product with variants and stock per location.', errors: [] },
      { method: 'POST', path: '/api/catalog/products', auth: 'catalog.manage', desc: 'Create a product with its variants.', errors: [] },
      { method: 'PUT', path: '/api/catalog/products/:id', auth: 'catalog.manage', desc: 'Update a product.', errors: [] },
      { method: 'DELETE', path: '/api/catalog/products/:id', auth: 'catalog.manage', desc: 'Soft-delete a product.', errors: [] },
      { method: 'POST', path: '/api/catalog/products/:id/image', auth: 'catalog.manage', desc: 'Upload product image (multipart field "image").', errors: [] },
      { method: 'POST', path: '/api/catalog/products/:id/variants', auth: 'catalog.manage', desc: 'Add a variant.', errors: [] },
      { method: 'PUT', path: '/api/catalog/variants/:id', auth: 'catalog.manage', desc: 'Update a variant.', errors: [] },
      { method: 'DELETE', path: '/api/catalog/variants/:id', auth: 'catalog.manage', desc: 'Soft-delete a variant.', errors: [] },
      { method: 'GET', path: '/api/catalog/brands', auth: 'catalog.view', desc: 'Brands.', errors: [] },
      { method: 'POST', path: '/api/catalog/brands', auth: 'catalog.manage', desc: 'Create a brand.', errors: [] },
      { method: 'PUT', path: '/api/catalog/brands/:id', auth: 'catalog.manage', desc: 'Update a brand.', errors: [] },
      { method: 'GET', path: '/api/catalog/tax-rates', auth: 'catalog.view', desc: 'Tax rates (PPN 11%).', errors: [] },
      { method: 'POST', path: '/api/catalog/tax-rates', auth: 'settings.manage', desc: 'Create a tax rate.', errors: [] },
      { method: 'PUT', path: '/api/catalog/tax-rates/:id', auth: 'settings.manage', desc: 'Update a tax rate.', errors: [] },
      { method: 'GET', path: '/api/categories', auth: 'required', desc: 'Categories.', errors: [] },
      { method: 'GET', path: '/api/categories/:id', auth: 'required', desc: 'One category.', errors: [] },
      { method: 'POST', path: '/api/categories', auth: 'catalog.manage', desc: 'Create a category (multipart, optional category_image).', errors: [] },
      { method: 'PUT', path: '/api/categories/:id', auth: 'catalog.manage', desc: 'Update a category.', errors: [] },
      { method: 'DELETE', path: '/api/categories/:id', auth: 'catalog.manage', desc: 'Delete an unused category.', errors: [] },
    ]
  },
  {
    name: 'Stock', icon: '📊', prefix: '/api/stock',
    endpoints: [
      { method: 'GET', path: '/api/stock', auth: 'stock.view', desc: 'Stock levels at a location.', query: [loc()], errors: [] },
      { method: 'POST', path: '/api/stock/adjust', auth: 'stock.adjust', desc: 'Manual adjustment (quantity items); posts a stock-value journal.', body: [loc(), { name: 'variant_id', type: 'number', required: true, desc: '' }, { name: 'qty_change', type: 'number', required: true, desc: '+/-' }, { name: 'unit_cost', type: 'number', required: false, desc: 'For increases' }, { name: 'note', type: 'string', required: false, desc: '' }], errors: [] },
      { method: 'PUT', path: '/api/stock/price', auth: 'prices.manage_location', desc: 'Location-specific selling price.', errors: [] },
      { method: 'GET', path: '/api/stock/movements', auth: 'stock.view', desc: 'Stock ledger (movements) with filters.', errors: [] },
      { method: 'GET', path: '/api/stock/units', auth: 'stock.view', desc: 'IMEI/serial units (search by IMEI, status, location).', errors: [] },
      { method: 'POST', path: '/api/stock/units', auth: 'units.register', desc: 'Register units (IMEI checked with Luhn).', errors: [] },
      { method: 'PUT', path: '/api/stock/units/:id', auth: 'units.register', desc: 'Edit a unit (IMEI, warranty, note).', errors: [] },
      { method: 'POST', path: '/api/stock/units/:id/write-off', auth: 'stock.adjust', desc: 'Write off a lost/damaged unit.', errors: [] },
    ]
  },
  {
    name: 'Purchasing', icon: '🚚', prefix: '/api/purchasing',
    endpoints: [
      { method: 'GET', path: '/api/purchasing/suppliers', auth: 'suppliers.manage', desc: 'Suppliers with outstanding balance (purchases.manage also allowed).', errors: [] },
      { method: 'POST', path: '/api/purchasing/suppliers', auth: 'suppliers.manage', desc: 'Create a supplier.', errors: [] },
      { method: 'PUT', path: '/api/purchasing/suppliers/:id', auth: 'suppliers.manage', desc: 'Update a supplier.', errors: [] },
      { method: 'GET', path: '/api/purchasing/receipts', auth: 'purchases.manage', desc: 'Goods receipts (GR-…).', errors: [] },
      { method: 'GET', path: '/api/purchasing/receipts/:id', auth: 'purchases.manage', desc: 'One receipt with lines, units and payments.', errors: [] },
      { method: 'POST', path: '/api/purchasing/receipts', auth: 'purchases.manage', desc: 'Draft receipt.', errors: [] },
      { method: 'PUT', path: '/api/purchasing/receipts/:id', auth: 'purchases.manage', desc: 'Edit a draft.', errors: [] },
      { method: 'DELETE', path: '/api/purchasing/receipts/:id', auth: 'purchases.manage', desc: 'Delete a draft.', errors: [] },
      { method: 'POST', path: '/api/purchasing/receipts/:id/post', auth: 'purchases.manage', desc: 'Post (final): stock in + journal.', errors: [] },
      { method: 'POST', path: '/api/purchasing/payments', auth: 'purchases.manage', desc: 'Pay a supplier against a receipt (journal posted).', errors: [] },
    ]
  },
  {
    name: 'Transfers', icon: '🔁', prefix: '/api/transfers',
    endpoints: [
      { method: 'GET', path: '/api/transfers', auth: 'stock.view', desc: 'Transfers in/out of your locations.', errors: [] },
      { method: 'GET', path: '/api/transfers/:id', auth: 'stock.view', desc: 'One transfer.', errors: [] },
      { method: 'POST', path: '/api/transfers', auth: 'transfers.create', desc: 'Draft transfer (TF-…) from a source location.', errors: [] },
      { method: 'PUT', path: '/api/transfers/:id', auth: 'transfers.create', desc: 'Edit a draft.', errors: [] },
      { method: 'POST', path: '/api/transfers/:id/cancel', auth: 'transfers.create', desc: 'Cancel a draft.', errors: [] },
      { method: 'POST', path: '/api/transfers/:id/send', auth: 'transfers.send', desc: 'Send: stock leaves the source (in transit).', errors: [] },
      { method: 'POST', path: '/api/transfers/:id/receive', auth: 'transfers.receive', desc: 'Receive (partial allowed) at the destination.', errors: [] },
      { method: 'POST', path: '/api/transfers/:id/resolve', auth: 'stock.adjust', desc: 'Source returns or writes off what was not received.', errors: [] },
    ]
  },
  {
    name: 'Stock opname', icon: '📋', prefix: '/api/opnames',
    endpoints: [
      { method: 'GET', path: '/api/opnames', auth: 'stock.view', desc: 'Stock counts.', errors: [] },
      { method: 'GET', path: '/api/opnames/:id', auth: 'stock.view', desc: 'One count with lines, scanned units and extras.', errors: [] },
      { method: 'POST', path: '/api/opnames', auth: 'stock.opname', desc: 'Start a count (SO-…) with a snapshot.', errors: [] },
      { method: 'PUT', path: '/api/opnames/:id/counts', auth: 'stock.opname', desc: 'Counted quantities (quantity items).', errors: [] },
      { method: 'POST', path: '/api/opnames/:id/scan', auth: 'stock.opname', desc: 'Scan an IMEI/serial.', errors: [] },
      { method: 'POST', path: '/api/opnames/:id/unscan', auth: 'stock.opname', desc: 'Undo a scan.', errors: [] },
      { method: 'POST', path: '/api/opnames/:id/approve', auth: 'stock.opname', desc: 'Apply counted − snapshot; unscanned units written off.', errors: [] },
      { method: 'POST', path: '/api/opnames/:id/cancel', auth: 'stock.opname', desc: 'Cancel an open count.', errors: [] },
    ]
  },
  {
    name: 'Sales', icon: '💳', prefix: '/api/sales',
    endpoints: [
      { method: 'GET', path: '/api/sales/payment-methods', auth: 'sales.create', desc: 'Active payment methods at ?location_id (Tunai, QRIS, E-Wallet, Kartu, Transfer). ?all=true with settings.manage lists every method, inactive ones included.', errors: [] },
      { method: 'POST', path: '/api/sales/payment-methods', auth: 'settings.manage', desc: 'Create a payment method.', errors: [] },
      { method: 'PUT', path: '/api/sales/payment-methods/:id', auth: 'settings.manage', desc: 'Update a payment method.', errors: [] },
      { method: 'POST', path: '/api/sales/quote', auth: 'sales.create', desc: 'Price a cart (PPN-inclusive, vouchers) without saving.', errors: [] },
      {
        method: 'POST', path: '/api/sales', auth: 'sales.create',
        desc: 'Create a sale (INV-…). Idempotent by client UUID: re-sending the same id returns the stored sale (200). Change only from cash; a customer is required when IMEI units are sold.',
        body: [
          { name: 'id', type: 'string', required: false, desc: 'Client UUID (offline queue)' },
          loc(),
          { name: 'occurred_at', type: 'string', required: false, desc: 'ISO time (offline sales)' },
          { name: 'cash_session_id', type: 'string', required: false, desc: 'Open shift' },
          { name: 'lines', type: 'array', required: true, desc: '[{ variant_id, qty | unit_ids[], unit_price? (services/pulsa), description? }]' },
          { name: 'payments', type: 'array', required: true, desc: '[{ payment_method_id, amount, reference? }]' },
          { name: 'customer_id | customer', type: 'object', required: false, desc: 'Existing id or { name, phone } to register' },
          { name: 'voucher_code', type: 'string', required: false, desc: '' },
        ],
        errors: [{ code: 400, msg: 'Validation / underpaid / unit not available' }, { code: 403, msg: 'No sales.create at location' }],
      },
      { method: 'GET', path: '/api/sales', auth: 'sales.create', desc: 'Sales at your locations (reports.view_location or sales.void also allowed).', errors: [] },
      { method: 'GET', path: '/api/sales/:id', auth: 'sales.create', desc: 'One sale with lines, payments and returns.', errors: [] },
      { method: 'POST', path: '/api/sales/:id/void', auth: 'sales.void', desc: 'Void a sale (stock back, journal reversed).', errors: [] },
      { method: 'POST', path: '/api/sales/:id/returns', auth: 'sales.void', desc: 'Return lines (RT-…); returned units can be marked defective.', errors: [] },
      { method: 'GET', path: '/api/vouchers/validate/:code', auth: 'required', desc: 'Check a voucher code.', errors: [{ code: 404, msg: 'Invalid or expired' }] },
      { method: 'GET', path: '/api/vouchers', auth: 'vouchers.manage', desc: 'All vouchers.', errors: [] },
      { method: 'POST', path: '/api/vouchers', auth: 'vouchers.manage', desc: 'Create a voucher.', errors: [] },
      { method: 'PUT', path: '/api/vouchers/:id', auth: 'vouchers.manage', desc: 'Update a voucher.', errors: [] },
      { method: 'DELETE', path: '/api/vouchers/:id', auth: 'vouchers.manage', desc: 'Delete a voucher.', errors: [] },
    ]
  },
  {
    name: 'Customers & shifts', icon: '🧾', prefix: '/api/customers',
    endpoints: [
      { method: 'GET', path: '/api/customers', auth: 'sales.create', desc: 'Search customers (name, phone in 08/+62 form). customers.manage also allowed.', errors: [] },
      { method: 'GET', path: '/api/customers/:id', auth: 'sales.create', desc: 'One customer.', errors: [] },
      { method: 'POST', path: '/api/customers', auth: 'sales.create', desc: 'Create (same phone returns the existing customer). customers.manage also allowed.', errors: [] },
      { method: 'PUT', path: '/api/customers/:id', auth: 'customers.manage', desc: 'Update.', errors: [] },
      { method: 'GET', path: '/api/cash-sessions/current', auth: 'sales.create', desc: 'Your open shift at a location.', query: [loc()], errors: [] },
      { method: 'GET', path: '/api/cash-sessions', auth: 'sales.create', desc: 'Shifts (all at the location with cash_session.view_all).', errors: [] },
      { method: 'GET', path: '/api/cash-sessions/:id', auth: 'sales.create', desc: 'One shift with summary (expected cash, totals per method).', errors: [] },
      { method: 'POST', path: '/api/cash-sessions', auth: 'cash_session.open', desc: 'Open a shift.', body: [loc(), { name: 'opening_cash', type: 'number', required: false, desc: '' }], errors: [] },
      { method: 'POST', path: '/api/cash-sessions/:id/close', auth: 'cash_session.close', desc: 'Close with counted cash (own shift, or any shift with cash_session.view_all); over/short is posted.', errors: [] },
    ]
  },
  {
    name: 'Accounting', icon: '📒', prefix: '/api/accounting',
    endpoints: [
      { method: 'GET', path: '/api/accounting/accounts', auth: 'accounting.view', desc: 'Chart of accounts.', errors: [] },
      { method: 'POST', path: '/api/accounting/accounts', auth: 'accounting.post_manual', desc: 'Create an account.', errors: [] },
      { method: 'PUT', path: '/api/accounting/accounts/:id', auth: 'accounting.post_manual', desc: 'Update an account.', errors: [] },
      { method: 'GET', path: '/api/accounting/journals', auth: 'accounting.view', desc: 'Journal entries with filters.', errors: [] },
      { method: 'GET', path: '/api/accounting/journals/:id', auth: 'accounting.view', desc: 'One entry with lines.', errors: [] },
      { method: 'POST', path: '/api/accounting/journals', auth: 'accounting.post_manual', desc: 'Manual entry (JV-…); must balance; closed periods refused.', errors: [] },
      { method: 'POST', path: '/api/accounting/journals/:id/void', auth: 'accounting.post_manual', desc: 'Void a manual entry by reversal.', errors: [] },
      { method: 'GET', path: '/api/accounting/trial-balance', auth: 'accounting.view', desc: 'Trial balance for a date range.', errors: [] },
      { method: 'GET', path: '/api/accounting/profit-loss', auth: 'accounting.view', desc: 'Profit & loss.', errors: [] },
      { method: 'GET', path: '/api/accounting/periods', auth: 'accounting.view', desc: 'Accounting periods.', errors: [] },
      { method: 'POST', path: '/api/accounting/periods/:year/:month/close', auth: 'accounting.close_period', desc: 'Close a month.', errors: [] },
      { method: 'POST', path: '/api/accounting/periods/:year/:month/reopen', auth: 'accounting.close_period', desc: 'Reopen a month.', errors: [] },
      { method: 'GET', path: '/api/accounting/mappings', auth: 'accounting.view', desc: 'Which account each posting rule uses.', errors: [] },
      { method: 'PUT', path: '/api/accounting/mappings', auth: 'settings.manage', desc: 'Change account mappings.', errors: [] },
    ]
  },
  {
    name: 'Dashboard & analytics', icon: '📈', prefix: '/api/dashboard',
    endpoints: [
      {
        method: 'GET', path: '/api/dashboard', auth: 'required',
        desc: 'KPIs and recent sales for the locations where you sell or read reports (every location with reports.view_all). ?location_id narrows to one.',
        response: { stats: { todayRevenue: 600000, todayTransactions: 1, monthlyTransactions: 5, monthlyRevenue: 1162000, lowStockCount: 0, outOfStockCount: 0 }, recentTransactions: [{ id: '01a1…', number: 'INV-BR01-261031-0001', final_amount: 600000, payment_status: 'paid', user_name: 'Kasir Satu', branch_name: 'Cabang Satu', payment_method: 'Tunai', item_count: 2 }] },
        errors: [{ code: 403, msg: 'location_id outside your scope' }],
      },
      { method: 'GET', path: '/api/analytics/summary', auth: 'reports.view_all', desc: 'Today / month / all-time revenue and transactions.', errors: [] },
      { method: 'GET', path: '/api/analytics/revenue-trend', auth: 'reports.view_all', desc: 'Daily revenue, ?days=30 (max 90).', errors: [] },
      { method: 'GET', path: '/api/analytics/branch-revenue', auth: 'reports.view_all', desc: 'Revenue per branch for ?date=YYYY-MM-DD.', errors: [] },
      { method: 'GET', path: '/api/analytics/category-sales', auth: 'reports.view_all', desc: 'Sales per category, ?days=.', errors: [] },
      { method: 'GET', path: '/api/analytics/top-products', auth: 'reports.view_all', desc: 'Best sellers, ?days=&limit=.', errors: [] },
    ]
  },
  {
    name: 'System', icon: '⚙️', prefix: '/api',
    endpoints: [
      { method: 'GET', path: '/api/health', auth: 'public', desc: 'Server health check.', response: { status: 'OK', message: 'Server is running' }, errors: [] },
      { method: 'GET', path: '/api/test', auth: 'public', desc: 'Connectivity test for the Flutter app.', response: { status: 'OK', message: 'Connection successful', timestamp: '2026-01-01T00:00:00.000Z', ip: '::1' }, errors: [] },
      { method: 'GET', path: '/api/docs', auth: 'owner', desc: 'This API documentation page.', response: '(HTML page)', errors: [{ code: 302, msg: 'Redirect to /api/docs/login if not signed in as an owner' }] },
      { method: 'GET', path: '/api/docs/info', auth: 'owner', desc: 'Server info JSON (ngrok URL, uptime, env).', errors: [{ code: 302, msg: 'Redirect to /api/docs/login' }] },
      { method: 'SOCKET', path: 'socket.io', auth: 'required', desc: 'Connect with auth { token } (or Authorization header). emit join-branch <locationId> (0 = every location, only with all-location access). Events: sale-created, stock-changed { location_id, variant_ids }.', errors: [] },
    ]
  },
];

// ── Helpers ───────────────────────────────────────────────────────────────────
function authBadge(auth) {
  if (auth === 'public')   return '<span class="auth-badge auth-public">Public</span>';
  if (auth === 'required') return '<span class="auth-badge auth-required">Auth</span>';
  if (auth === 'owner')    return '<span class="auth-badge role-superadmin">Owner</span>';
  if (auth)                  return `<span class="auth-badge role-admin" title="Permission">${auth}</span>`;
  return '';
}

function typeChip(type) {
  const colors = { string: '#60a5fa', number: '#4ade80', boolean: '#fb923c', array: '#c084fc', file: '#f5c842', object: '#94a3b8' };
  const c = colors[type] || '#94a3b8';
  return `<span style="font-size:10px;padding:1px 6px;border-radius:4px;background:${c}22;color:${c};border:1px solid ${c}44;font-family:Consolas,monospace">${type}</span>`;
}

function tableRows(items) {
  return items.map(p => `
    <tr>
      <td style="font-family:Consolas,monospace;color:#e2e8f0;padding:6px 10px;white-space:nowrap">${p.name}${p.required ? ' <span style="color:#f87171;font-size:10px">*</span>' : ''}</td>
      <td style="padding:6px 10px">${typeChip(p.type || 'string')}</td>
      <td style="padding:6px 10px;color:#8892a4;font-size:12px">${p.desc || ''}</td>
    </tr>`).join('');
}

function section(title, rows) {
  if (!rows || rows.length === 0) return '';
  return `
    <div class="detail-section">
      <div class="detail-section-title">${title}</div>
      <table class="detail-table">
        <thead><tr><th>Name</th><th>Type</th><th>Description</th></tr></thead>
        <tbody>${tableRows(rows)}</tbody>
      </table>
    </div>`;
}

function responseBlock(resp) {
  if (!resp) return '';
  const json = typeof resp === 'string' ? resp : JSON.stringify(resp, null, 2);
  return `
    <div class="detail-section">
      <div class="detail-section-title">Sample Response</div>
      <pre class="code-block">${json}</pre>
    </div>`;
}

function errorsBlock(errors) {
  if (!errors || errors.length === 0) return '';
  const rows = errors.map(e => `
    <tr>
      <td style="padding:6px 10px;font-family:Consolas,monospace;color:#f87171">${e.code}</td>
      <td style="padding:6px 10px;color:#8892a4;font-size:12px">${e.msg}</td>
    </tr>`).join('');
  return `
    <div class="detail-section">
      <div class="detail-section-title">Error Responses</div>
      <table class="detail-table">
        <thead><tr><th>Status</th><th>Message</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

function headersBlock(headers) {
  if (!headers || headers.length === 0) return '';
  const rows = headers.map(h => `
    <tr>
      <td style="font-family:Consolas,monospace;color:#e2e8f0;padding:6px 10px;white-space:nowrap">${h.name}${h.required ? ' <span style="color:#f87171;font-size:10px">*</span>' : ''}</td>
      <td style="padding:6px 10px;font-family:Consolas,monospace;color:#f5c842;font-size:12px">${h.value}</td>
    </tr>`).join('');
  return `
    <div class="detail-section">
      <div class="detail-section-title">Request Headers</div>
      <table class="detail-table">
        <thead><tr><th>Header</th><th>Value</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

// ── Render ────────────────────────────────────────────────────────────────────
document.getElementById('year').textContent = new Date().getFullYear();

// Inject drawer styles
const style = document.createElement('style');
style.textContent = `
  .endpoint { cursor: pointer; user-select: none; }
  .endpoint .chevron { margin-left: auto; color: var(--muted); font-size: 12px; transition: transform .2s; flex-shrink: 0; }
  .endpoint.open .chevron { transform: rotate(180deg); }
  .endpoint-detail {
    display: none; padding: 16px 20px; border-top: 1px solid var(--border);
    background: rgba(0,0,0,.2); animation: slideDown .15s ease;
  }
  .endpoint-detail.open { display: block; }
  @keyframes slideDown { from { opacity:0; transform:translateY(-4px) } to { opacity:1; transform:translateY(0) } }
  .detail-section { margin-bottom: 16px; }
  .detail-section:last-child { margin-bottom: 0; }
  .detail-section-title { font-size: 11px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); margin-bottom: 8px; }
  .detail-table { width: 100%; border-collapse: collapse; font-size: 13px; }
  .detail-table th { text-align: left; padding: 5px 10px; font-size: 10px; font-weight: 600; letter-spacing: .05em; text-transform: uppercase; color: var(--muted); border-bottom: 1px solid var(--border); }
  .detail-table tr:hover td { background: rgba(255,255,255,.02); }
  .code-block { background: var(--bg); border: 1px solid var(--border); border-radius: 8px; padding: 12px 14px; font-family: Consolas, monospace; font-size: 12px; color: #a5f3fc; overflow-x: auto; white-space: pre; line-height: 1.6; }
`;
document.head.appendChild(style);

const container = document.getElementById('docs-content');
let totalEndpoints = 0;
let idCounter = 0;

groups.forEach(group => {
  totalEndpoints += group.endpoints.length;

  const endpointsHtml = group.endpoints.map(e => {
    const id = `ep-${idCounter++}`;
    const detail = [
      headersBlock(e.headers),
      section('Path Parameters', e.params),
      section('Query Parameters', e.query),
      section('Request Body', e.body),
      responseBlock(e.response),
      errorsBlock(e.errors),
    ].join('');

    return `
      <div class="endpoint" data-id="${id}" role="button" aria-expanded="false">
        <span class="method ${e.method}">${e.method}</span>
        <div>
          <div class="path">${e.path}</div>
          <div class="desc">${e.desc}</div>
        </div>
        ${authBadge(e.auth)}
        <span class="chevron">▼</span>
      </div>
      <div class="endpoint-detail" id="${id}">
        ${detail || '<span style="color:var(--muted);font-size:12px">No additional details.</span>'}
      </div>`;
  }).join('');

  container.innerHTML += `
    <div class="endpoint-group">
      <div class="endpoint-group-header">
        <span class="icon">${group.icon}</span> ${group.name}
        <span style="color:var(--muted);font-weight:400;font-size:12px;margin-left:auto">${group.endpoints.length} endpoints</span>
      </div>
      ${endpointsHtml}
    </div>`;
});

document.getElementById('total-endpoints').textContent = totalEndpoints;
document.getElementById('total-groups').textContent = groups.length;

// Toggle drawer on click
container.addEventListener('click', (e) => {
  const row = e.target.closest('.endpoint[data-id]');
  if (!row) return;
  const id = row.dataset.id;
  const detail = document.getElementById(id);
  const isOpen = detail.classList.contains('open');
  detail.classList.toggle('open', !isOpen);
  row.classList.toggle('open', !isOpen);
  row.setAttribute('aria-expanded', String(!isOpen));
});

// ── Socket.IO uptime checker ──────────────────────────────────────────────────
function applyServerInfo(data) {
  document.getElementById('status-dot').className = 'status-dot online';
  document.getElementById('status-text').textContent = 'Online';

  const uptimeSec = Math.floor(data.uptime);
  const h = Math.floor(uptimeSec / 3600);
  const m = Math.floor((uptimeSec % 3600) / 60);
  const s = uptimeSec % 60;
  document.getElementById('uptime').textContent =
    h > 0 ? `${h}h ${m}m` : m > 0 ? `${m}m ${s}s` : `${s}s`;

  document.getElementById('env-badge').textContent = data.env || 'dev';

  if (data.ngrokUrl) {
    const el = document.getElementById('ngrok-url');
    el.textContent = data.ngrokUrl;
    el.href = data.ngrokUrl;
  } else {
    document.getElementById('ngrok-url').textContent = 'ngrok not active';
  }
}

function setOffline() {
  document.getElementById('status-dot').className = 'status-dot offline';
  document.getElementById('status-text').textContent = 'Offline';
}

fetch('/api/docs/info', { credentials: 'include' })
  .then(r => r.ok ? r.json() : Promise.reject())
  .then(applyServerInfo)
  .catch(setOffline);

(function connectSocket() {
  const socket = window.io ? io({ path: '/socket.io', transports: ['websocket', 'polling'] }) : null;
  if (!socket) {
    setInterval(() => {
      fetch('/api/docs/info', { credentials: 'include' })
        .then(r => r.ok ? r.json() : Promise.reject())
        .then(applyServerInfo)
        .catch(setOffline);
    }, 15000);
    return;
  }
  socket.on('connect', () => {
    document.getElementById('status-dot').className = 'status-dot online';
    document.getElementById('status-text').textContent = 'Online';
  });
  socket.on('server-info', applyServerInfo);
  socket.on('disconnect', setOffline);
  socket.on('connect_error', setOffline);
})();
