// ── Endpoint definitions ──────────────────────────────────────────────────────
const groups = [
  {
    name: 'Authentication', icon: '🔐', prefix: '/api/auth',
    endpoints: [
      {
        method: 'POST', path: '/api/auth/login', auth: 'public',
        desc: 'Login with username & password. Returns JWT token.',
        headers: [{ name: 'Content-Type', value: 'application/json', required: true }],
        body: [
          { name: 'username', type: 'string', required: true, desc: 'Account username' },
          { name: 'password', type: 'string', required: true, desc: 'Account password' },
        ],
        response: { message: 'Login successful', user: { id: 1, name: 'John', username: 'john', role: 'superadmin', branchId: 1 }, token: '<jwt>' },
        errors: [{ code: 400, msg: 'Username and password are required' }, { code: 401, msg: 'Invalid credentials' }, { code: 429, msg: 'Too many failed attempts' }],
      },
      {
        method: 'POST', path: '/api/auth/logout', auth: 'required',
        desc: 'Logout and clear session cookie.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        response: { message: 'Logged out successfully' },
        errors: [],
      },
      {
        method: 'GET', path: '/api/auth/me', auth: 'required',
        desc: 'Get currently authenticated user info.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        response: { user: { id: 1, name: 'John', username: 'john', role: 'superadmin', branch_id: 1 } },
        errors: [{ code: 401, msg: 'No token provided / User not found' }],
      },
    ]
  },
  {
    name: 'Users', icon: '👥', prefix: '/api/users',
    endpoints: [
      {
        method: 'GET', path: '/api/users', auth: 'admin',
        desc: 'List all users with pagination, search & role filter.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        query: [
          { name: 'page', type: 'number', required: false, desc: 'Page number (default: 1)' },
          { name: 'limit', type: 'number', required: false, desc: 'Items per page (default: 10)' },
          { name: 'branch_id', type: 'number', required: false, desc: 'Filter by branch (superadmin only)' },
          { name: 'role', type: 'string', required: false, desc: 'Filter by role: karyawan | admin | superadmin' },
          { name: 'search', type: 'string', required: false, desc: 'Search by name or username' },
        ],
        response: { users: [], pagination: { page: 1, limit: 10, total: 50, totalPages: 5 } },
        errors: [{ code: 403, msg: 'Insufficient permissions' }],
      },
      {
        method: 'GET', path: '/api/users/:id', auth: 'admin',
        desc: 'Get a single user by ID.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'User ID' }],
        response: { user: { id: 1, name: 'John', username: 'john', role: 'karyawan', branch_id: 1, branch_name: 'Main' } },
        errors: [{ code: 404, msg: 'User not found' }],
      },
      {
        method: 'POST', path: '/api/users', auth: 'admin',
        desc: 'Create a new user. Admins can only create karyawan.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'application/json', required: true }],
        body: [
          { name: 'name', type: 'string', required: true, desc: '2–50 chars, letters/spaces/hyphens' },
          { name: 'username', type: 'string', required: true, desc: '3–30 chars, alphanumeric/_/-/.' },
          { name: 'password', type: 'string', required: true, desc: 'Min 8 chars, mixed case + number' },
          { name: 'role', type: 'string', required: false, desc: 'karyawan | admin | superadmin (default: karyawan)' },
          { name: 'branch_id', type: 'number', required: false, desc: 'Existing branch ID' },
          { name: 'branch_name', type: 'string', required: false, desc: 'Create new branch by name (superadmin only)' },
        ],
        response: { message: 'User created successfully', userId: 5 },
        errors: [{ code: 400, msg: 'Validation error / Username exists' }, { code: 403, msg: 'Cannot create admin/superadmin as admin' }],
      },
      {
        method: 'PUT', path: '/api/users/:id', auth: 'admin',
        desc: 'Update user details, role, or branch.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'application/json', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'User ID' }],
        body: [
          { name: 'name', type: 'string', required: false, desc: 'Updated display name' },
          { name: 'username', type: 'string', required: false, desc: 'Updated username' },
          { name: 'password', type: 'string', required: false, desc: 'New password (leave blank to keep)' },
          { name: 'role', type: 'string', required: false, desc: 'karyawan | admin | superadmin' },
          { name: 'branch_id', type: 'number', required: false, desc: 'New branch ID (superadmin only)' },
        ],
        response: { message: 'User updated successfully' },
        errors: [{ code: 404, msg: 'User not found' }, { code: 403, msg: 'Cross-branch or role restriction' }],
      },
      {
        method: 'DELETE', path: '/api/users/:id', auth: 'admin',
        desc: 'Delete a user. Cannot delete own account.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'User ID' }],
        response: { message: 'User deleted successfully' },
        errors: [{ code: 400, msg: 'Cannot delete own account' }, { code: 404, msg: 'User not found' }],
      },
      {
        method: 'POST', path: '/api/users/check-password-strength', auth: 'admin',
        desc: 'Validate password strength before submission.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'application/json', required: true }],
        body: [{ name: 'password', type: 'string', required: true, desc: 'Password to evaluate' }],
        response: { isValid: true, score: 4, requirements: { minLength: true, hasUpperCase: true, hasLowerCase: true, hasNumbers: true, hasSpecialChar: false } },
        errors: [{ code: 400, msg: 'Password is required' }],
      },
    ]
  },
  {
    name: 'Products', icon: '📦', prefix: '/api/products',
    endpoints: [
      {
        method: 'GET', path: '/api/products', auth: 'required',
        desc: 'List products. Filtered by branch for non-superadmin.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        query: [
          { name: 'branch_id', type: 'number', required: false, desc: 'Filter by branch' },
          { name: 'category_id', type: 'number', required: false, desc: 'Filter by category' },
          { name: 'search', type: 'string', required: false, desc: 'Search by name or barcode' },
        ],
        response: { products: [{ id: 1, name: 'Item', barcode: 'GG001', sell_price: 10000, stock: 50, category_name: 'Food', branch_name: 'Main' }] },
        errors: [],
      },
      {
        method: 'GET', path: '/api/products/:id', auth: 'required',
        desc: 'Get product detail by ID.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Product ID' }],
        response: { product: { id: 1, name: 'Item', barcode: 'GG001', sell_price: 10000, stock: 50 } },
        errors: [{ code: 404, msg: 'Product not found' }, { code: 403, msg: 'Cross-branch access denied' }],
      },
      {
        method: 'POST', path: '/api/products', auth: 'admin',
        desc: 'Create product with optional image upload.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'multipart/form-data', required: true }],
        body: [
          { name: 'name', type: 'string', required: true, desc: 'Product name' },
          { name: 'sell_price', type: 'number', required: true, desc: 'Selling price' },
          { name: 'barcode', type: 'string', required: false, desc: 'Auto-generated if omitted' },
          { name: 'category_id', type: 'number', required: false, desc: 'Category ID' },
          { name: 'stock', type: 'number', required: false, desc: 'Initial stock (default: 0)' },
          { name: 'branch_id', type: 'number', required: false, desc: 'Branch ID (forced to own branch for admin)' },
          { name: 'product_image', type: 'file', required: false, desc: 'JPEG/PNG image file' },
        ],
        response: { message: 'Product created successfully', productId: 10, product: {} },
        errors: [{ code: 400, msg: 'Name and sell price required / Duplicate barcode' }],
      },
      {
        method: 'PUT', path: '/api/products/:id', auth: 'admin',
        desc: 'Update product details and/or image.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'multipart/form-data', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Product ID' }],
        body: [
          { name: 'name', type: 'string', required: true, desc: 'Product name' },
          { name: 'sell_price', type: 'number', required: true, desc: 'Selling price' },
          { name: 'barcode', type: 'string', required: false, desc: 'Product barcode' },
          { name: 'category_id', type: 'number', required: false, desc: 'Category ID' },
          { name: 'stock', type: 'number', required: false, desc: 'Stock quantity' },
          { name: 'product_image', type: 'file', required: false, desc: 'Replaces existing image' },
        ],
        response: { message: 'Product updated successfully', product: {} },
        errors: [{ code: 404, msg: 'Product not found' }, { code: 403, msg: 'Cross-branch update denied' }],
      },
      {
        method: 'DELETE', path: '/api/products/:id', auth: 'superadmin',
        desc: 'Delete product and its image. Superadmin only.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Product ID' }],
        response: { message: 'Product deleted successfully' },
        errors: [{ code: 404, msg: 'Product not found' }],
      },
    ]
  },
  {
    name: 'Categories', icon: '🏷️', prefix: '/api/categories',
    endpoints: [
      {
        method: 'GET', path: '/api/categories', auth: 'required',
        desc: 'List all categories ordered by name.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        response: { categories: [{ id: 1, name: 'Food', description: 'Food items', category_image: 'cat.jpg' }] },
        errors: [],
      },
      {
        method: 'GET', path: '/api/categories/:id', auth: 'required',
        desc: 'Get category by ID.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Category ID' }],
        response: { category: { id: 1, name: 'Food', description: 'Food items' } },
        errors: [{ code: 404, msg: 'Category not found' }],
      },
      {
        method: 'POST', path: '/api/categories', auth: 'admin',
        desc: 'Create category with optional image.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'multipart/form-data', required: true }],
        body: [
          { name: 'name', type: 'string', required: true, desc: 'Category name' },
          { name: 'description', type: 'string', required: false, desc: 'Short description' },
          { name: 'category_image', type: 'file', required: false, desc: 'JPEG/PNG image' },
        ],
        response: { message: 'Category created successfully', categoryId: 3, category: {} },
        errors: [{ code: 400, msg: 'Category name is required' }],
      },
      {
        method: 'PUT', path: '/api/categories/:id', auth: 'admin',
        desc: 'Update category name, description, or image.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'multipart/form-data', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Category ID' }],
        body: [
          { name: 'name', type: 'string', required: true, desc: 'Category name' },
          { name: 'description', type: 'string', required: false, desc: 'Short description' },
          { name: 'category_image', type: 'file', required: false, desc: 'Replaces existing image' },
        ],
        response: { message: 'Category updated successfully', category: {} },
        errors: [{ code: 404, msg: 'Category not found' }],
      },
      {
        method: 'DELETE', path: '/api/categories/:id', auth: 'superadmin',
        desc: 'Delete category. Fails if products exist.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Category ID' }],
        response: { message: 'Category deleted successfully' },
        errors: [{ code: 400, msg: 'Cannot delete category with existing products' }, { code: 404, msg: 'Category not found' }],
      },
    ]
  },
  {
    name: 'Branches', icon: '🏪', prefix: '/api/branches',
    endpoints: [
      {
        method: 'GET', path: '/api/branches', auth: 'required',
        desc: 'List all branches.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        response: { branches: [{ id: 1, name: 'Main Branch', address: 'Jl. Merdeka 1', phone: '08123456789' }] },
        errors: [],
      },
      {
        method: 'GET', path: '/api/branches/:id', auth: 'required',
        desc: 'Get branch by ID.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Branch ID' }],
        response: { branch: { id: 1, name: 'Main Branch', address: 'Jl. Merdeka 1', phone: '08123456789' } },
        errors: [{ code: 404, msg: 'Branch not found' }],
      },
      {
        method: 'POST', path: '/api/branches', auth: 'superadmin',
        desc: 'Create a new branch.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'application/json', required: true }],
        body: [
          { name: 'name', type: 'string', required: true, desc: 'Branch name' },
          { name: 'address', type: 'string', required: false, desc: 'Physical address' },
          { name: 'phone', type: 'string', required: false, desc: 'Contact phone number' },
        ],
        response: { message: 'Branch created successfully', branchId: 3 },
        errors: [{ code: 400, msg: 'Branch name is required' }],
      },
      {
        method: 'PUT', path: '/api/branches/:id', auth: 'superadmin',
        desc: 'Update branch info.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'application/json', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Branch ID' }],
        body: [
          { name: 'name', type: 'string', required: true, desc: 'Branch name' },
          { name: 'address', type: 'string', required: false, desc: 'Physical address' },
          { name: 'phone', type: 'string', required: false, desc: 'Contact phone number' },
        ],
        response: { message: 'Branch updated successfully' },
        errors: [{ code: 404, msg: 'Branch not found' }],
      },
      {
        method: 'DELETE', path: '/api/branches/:id', auth: 'superadmin',
        desc: 'Delete branch. Fails if users or products exist.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Branch ID' }],
        response: { message: 'Branch deleted successfully' },
        errors: [{ code: 400, msg: 'Cannot delete branch with existing users or products' }, { code: 404, msg: 'Branch not found' }],
      },
    ]
  },
  {
    name: 'Transactions', icon: '💳', prefix: '/api/transactions',
    endpoints: [
      {
        method: 'GET', path: '/api/transactions', auth: 'required',
        desc: 'List transactions with filters (branch, date, status).',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        query: [
          { name: 'branch_id', type: 'number', required: false, desc: 'Filter by branch' },
          { name: 'user_id', type: 'number', required: false, desc: 'Filter by cashier' },
          { name: 'payment_status', type: 'string', required: false, desc: 'paid | unpaid' },
          { name: 'start_date', type: 'string', required: false, desc: 'YYYY-MM-DD' },
          { name: 'end_date', type: 'string', required: false, desc: 'YYYY-MM-DD' },
        ],
        response: { transactions: [{ id: 1, total_amount: 50000, final_amount: 45000, discount: 5000, payment_status: 'paid', user_name: 'John', branch_name: 'Main' }] },
        errors: [],
      },
      {
        method: 'GET', path: '/api/transactions/:id', auth: 'required',
        desc: 'Get transaction with items and payment details.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }],
        params: [{ name: 'id', type: 'number', required: true, desc: 'Transaction ID' }],
        response: { transaction: {}, items: [{ product_id: 1, qty: 2, price: 10000, subtotal: 20000, product_name: 'Item' }], payments: [{ method: 'cash', amount: 50000 }] },
        errors: [{ code: 404, msg: 'Transaction not found' }],
      },
      {
        method: 'POST', path: '/api/transactions', auth: 'required',
        desc: 'Create transaction, deduct stock, record payment.',
        headers: [{ name: 'Authorization', value: 'Bearer <token>', required: true }, { name: 'Content-Type', value: 'application/json', required: true }],
        body: [
          { name: 'items', type: 'array', required: true, desc: '[{ product_id, qty, price }] — at least one item' },
          { name: 'discount', type: 'number', required: false, desc: 'Discount amount (default: 0)' },
          { name: 'payment_method', type: 'string', required: false, desc: 'cash | transfer | qris' },
          { name: 'payment_amount', type: 'number', required: false, desc: 'Amount tendered' },
        ],
        response: { message: 'Transaction created successfully', transactionId: 42, transaction: {} },
        errors: [{ code: 400, msg: 'Transaction items are required' }],
      },
    ]
  },
  {
    name: 'System', icon: '⚙️', prefix: '/api',
    endpoints: [
      {
        method: 'GET', path: '/api/health', auth: 'public',
        desc: 'Server health check. Returns status and timestamp.',
        response: { status: 'OK', message: 'Server is running' },
        errors: [],
      },
      {
        method: 'GET', path: '/api/test', auth: 'public',
        desc: 'Connectivity test for Flutter app.',
        response: { status: 'OK', message: 'Connection successful', timestamp: '2026-01-01T00:00:00.000Z', ip: '::1' },
        errors: [],
      },
      {
        method: 'GET', path: '/api/docs', auth: 'superadmin',
        desc: 'This API documentation page.',
        response: '(HTML page)',
        errors: [{ code: 302, msg: 'Redirect to /api/docs/login if not authenticated' }],
      },
      {
        method: 'GET', path: '/api/docs/info', auth: 'superadmin',
        desc: 'Server info JSON (ngrok URL, uptime, env).',
        response: { status: 'OK', env: 'development', uptime: 3600, ngrokUrl: 'https://xxx.ngrok.io', timestamp: '2026-01-01T00:00:00.000Z' },
        errors: [{ code: 302, msg: 'Redirect to /api/docs/login if not authenticated' }],
      },
    ]
  },
];

// ── Helpers ───────────────────────────────────────────────────────────────────
function authBadge(auth) {
  if (auth === 'public')     return '<span class="auth-badge auth-public">Public</span>';
  if (auth === 'required')   return '<span class="auth-badge auth-required">Auth</span>';
  if (auth === 'admin')      return '<span class="auth-badge role-admin">Admin+</span>';
  if (auth === 'superadmin') return '<span class="auth-badge role-superadmin">Superadmin</span>';
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
