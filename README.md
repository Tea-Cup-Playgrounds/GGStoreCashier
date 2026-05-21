# GG Store Cashier

Point of Sale system with Express.js API backend and Flutter mobile app.

## Prerequisites

- Node.js >= 18.0.0
- npm >= 9.0.0
- Flutter 3.38.5 (via FVM)
- Android Studio with NDK 27.0.12077973
- MySQL database

## Setup

### 1. Install Node dependencies

```bash
npm install
```

### 2. Install Flutter via FVM

```bash
cd app
dart pub global activate fvm
fvm install 3.38.5
fvm flutter pub get
```

### 3. Configure environment

Create `.env` in the project root:

```env
# Database
DB_HOST=localhost
DB_USER=your_user
DB_PASSWORD=your_password
DB_NAME=gg_store

# API
PORT=3000
JWT_SECRET=your_secret_key

# Ngrok (for dev)
NGROK_API_URL=http://localhost:3000
NGROK_API_TIMEOUT=30000
```

### 4. Run the project

**Option A: Run separately**

- API: `npm run dev` (with hot reload + ngrok)
- Flutter: Use VS Code Run & Debug → "Flutter (Mobile App via FVM)"

**Option B: Run both together**

- Use VS Code Run & Debug → "Full Stack (Flutter + API)"

## Project Structure

```
├── API/                    # Express.js backend
│   ├── src/
│   │   ├── server.js      # Entry point
│   │   ├── routes/        # API routes
│   │   ├── middleware/    # Auth, validation
│   │   └── utils/         # Helpers
│   └── uploads/           # Product/category images
├── app/                   # Flutter mobile app
│   ├── lib/
│   ├── android/
│   └── ios/
└── .vscode/              # VS Code debug configs
```

## Available Scripts

- `npm start` — Start API (production)
- `npm run dev` — Start API with nodemon + ngrok
- `npm run sync-env` — Sync ngrok URL to Flutter .env
- `npm run hash-passwords` — Hash passwords in DB
- `npm run create-test-user` — Create test user

## Notes

- All dependency versions are locked (no `^` or `~`) for stability
- The `sync-env` script automatically updates `app/.env` with the ngrok URL during dev
- Android requires NDK 27 for the `audioplayers` package

---

## API Documentation

Base URL: `http://localhost:5000` (or your ngrok URL in dev)

All protected routes require a Bearer token in the `Authorization` header:

```
Authorization: Bearer <token>
```

Token is returned from `POST /api/auth/login`.

### Roles

| Role         | Description                                                 |
| ------------ | ----------------------------------------------------------- |
| `karyawan`   | Cashier — can create transactions, view products            |
| `admin`      | Branch manager — manages users/products within their branch |
| `superadmin` | Full access across all branches                             |

---

### Auth — `/api/auth`

| Method | Path               | Auth | Description                |
| ------ | ------------------ | ---- | -------------------------- |
| POST   | `/api/auth/login`  | ❌   | Login, returns JWT token   |
| POST   | `/api/auth/logout` | ❌   | Clears auth cookie         |
| GET    | `/api/auth/me`     | ✅   | Get current logged-in user |

**POST `/api/auth/login`**

```json
{
  "username": "string",
  "password": "string"
}
```

Response:

```json
{
  "token": "jwt_token",
  "user": { "id": 1, "name": "string", "username": "string", "role": "string", "branchId": 1 }
}
```

Rate limited: 5 failed attempts → 15 min lockout per IP+username combo.

---

### Users — `/api/users`

All routes require auth. `admin` can only manage users in their own branch.

| Method | Path                                 | Role              | Description            |
| ------ | ------------------------------------ | ----------------- | ---------------------- |
| GET    | `/api/users`                         | admin, superadmin | List users (paginated) |
| GET    | `/api/users/:id`                     | admin, superadmin | Get user by ID         |
| POST   | `/api/users`                         | admin, superadmin | Create user            |
| PUT    | `/api/users/:id`                     | admin, superadmin | Update user            |
| DELETE | `/api/users/:id`                     | admin, superadmin | Delete user            |
| POST   | `/api/users/check-password-strength` | admin, superadmin | Validate password      |

**GET `/api/users`** query params:

- `branch_id` — filter by branch (superadmin only)
- `role` — filter by role (`karyawan`, `admin`, `superadmin`)
- `search` — search by name or username
- `page` — page number (default: 1)
- `limit` — items per page (default: 10)

**POST `/api/users`** body:

```json
{
  "name": "string",
  "username": "string",
  "password": "string (min 8 chars, needs uppercase+lowercase+number)",
  "role": "karyawan | admin | superadmin",
  "branch_id": 1
}
```

---

### Products — `/api/products`

All routes require auth. Branch-filtered automatically by role.

| Method | Path                | Role              | Description                          |
| ------ | ------------------- | ----------------- | ------------------------------------ |
| GET    | `/api/products`     | all               | List products                        |
| GET    | `/api/products/:id` | all               | Get product by ID                    |
| POST   | `/api/products`     | admin, superadmin | Create product (multipart/form-data) |
| PUT    | `/api/products/:id` | admin, superadmin | Update product (multipart/form-data) |
| DELETE | `/api/products/:id` | superadmin        | Delete product                       |

**GET `/api/products`** query params:

- `branch_id` — filter by branch
- `category_id` — filter by category
- `search` — search by name or barcode

**POST/PUT `/api/products`** — `multipart/form-data`:
| Field | Type | Required |
|-------|------|----------|
| `name` | string | ✅ |
| `sell_price` | number | ✅ |
| `barcode` | string | ❌ (auto-generated if empty) |
| `category_id` | number | ❌ |
| `stock` | number | ❌ (default 0) |
| `branch_id` | number | ✅ |
| `product_image` | file (jpg/png) | ❌ |

Images served at: `GET /uploads/products/<filename>`

Real-time: emits `product-created`, `product-updated`, `product-deleted` via Socket.IO.

---

### Categories — `/api/categories`

| Method | Path                  | Role              | Description                             |
| ------ | --------------------- | ----------------- | --------------------------------------- |
| GET    | `/api/categories`     | all (auth)        | List all categories                     |
| GET    | `/api/categories/:id` | all (auth)        | Get category by ID                      |
| POST   | `/api/categories`     | admin, superadmin | Create category (multipart/form-data)   |
| PUT    | `/api/categories/:id` | admin, superadmin | Update category (multipart/form-data)   |
| DELETE | `/api/categories/:id` | superadmin        | Delete category (fails if has products) |

**POST/PUT `/api/categories`** — `multipart/form-data`:
| Field | Type | Required |
|-------|------|----------|
| `name` | string | ✅ |
| `description` | string | ❌ |
| `category_image` | file (jpg/png) | ❌ |

Images served at: `GET /uploads/categories/<filename>`

---

### Branches — `/api/branches`

| Method | Path                | Role                    | Description                                 |
| ------ | ------------------- | ----------------------- | ------------------------------------------- |
| GET    | `/api/branches`     | all (auth)              | List all branches                           |
| GET    | `/api/branches/:id` | all (auth)              | Get branch by ID                            |
| POST   | `/api/branches`     | superadmin              | Create branch                               |
| PUT    | `/api/branches/:id` | admin (own), superadmin | Update branch                               |
| DELETE | `/api/branches/:id` | superadmin              | Delete branch (fails if has users/products) |

**POST `/api/branches`** body:

```json
{
  "name": "string",
  "address": "string",
  "phone": "string"
}
```

---

### Transactions — `/api/transactions`

| Method | Path                    | Role       | Description                         |
| ------ | ----------------------- | ---------- | ----------------------------------- |
| GET    | `/api/transactions`     | all (auth) | List transactions (branch-filtered) |
| GET    | `/api/transactions/:id` | all (auth) | Get transaction + items + payments  |
| POST   | `/api/transactions`     | all (auth) | Create transaction                  |

**GET `/api/transactions`** query params:

- `branch_id`, `user_id`, `payment_status`
- `start_date`, `end_date` — format `YYYY-MM-DD`

**POST `/api/transactions`** body:

```json
{
  "branch_id": 1,
  "items": [{ "product_id": 1, "qty": 2, "price": 15000 }],
  "discount": 0,
  "payment_method": "cash | transfer | qris",
  "payment_amount": 30000
}
```

- Validates stock before committing
- Deducts stock atomically (DB transaction)
- Records stock movement
- Real-time: emits `transaction-created`, `payment-completed`, `product-updated` via Socket.IO

---

### Dashboard — `/api/dashboard`

| Method | Path             | Role       | Description                 |
| ------ | ---------------- | ---------- | --------------------------- |
| GET    | `/api/dashboard` | all (auth) | Stats + recent transactions |

Response includes:

- `todayRevenue`, `todayTransactions`
- `monthlyRevenue`, `monthlyTransactions`
- `lowStockCount` (stock ≤ 5), `outOfStockCount`
- `recentTransactions` (last 10)

Branch-filtered automatically: `admin`/`karyawan` see only their branch.

---

### Vouchers — `/api/vouchers`

| Method | Path                           | Role              | Description             |
| ------ | ------------------------------ | ----------------- | ----------------------- |
| GET    | `/api/vouchers`                | admin, superadmin | List all vouchers       |
| GET    | `/api/vouchers/validate/:code` | all (auth)        | Validate a voucher code |
| POST   | `/api/vouchers`                | admin, superadmin | Create voucher          |
| PUT    | `/api/vouchers/:id`            | admin, superadmin | Update voucher          |
| DELETE | `/api/vouchers/:id`            | admin, superadmin | Delete voucher          |

**POST/PUT `/api/vouchers`** body:

```json
{
  "code": "SAVE10",
  "description": "string",
  "discount_type": "percent | fixed",
  "discount_value": 10,
  "valid_from": "2025-01-01",
  "valid_to": "2025-12-31",
  "is_active": 1,
  "target_type": "product | category | null",
  "target_id": 1
}
```

---

### Analytics — `/api/analytics`

All routes require `superadmin` role.

| Method | Path                            | Query Params                | Description                          |
| ------ | ------------------------------- | --------------------------- | ------------------------------------ |
| GET    | `/api/analytics/summary`        | —                           | KPIs: today, month, all-time revenue |
| GET    | `/api/analytics/revenue-trend`  | `days` (max 90, default 30) | Daily revenue chart data             |
| GET    | `/api/analytics/branch-revenue` | `date` (YYYY-MM-DD)         | Revenue per branch for a day         |
| GET    | `/api/analytics/category-sales` | `days` (max 90, default 30) | Top categories by qty sold           |
| GET    | `/api/analytics/top-products`   | `days`, `limit` (max 20)    | Top products by qty sold             |

---

### API Docs (Web UI)

A built-in docs page is available at:

```
http://localhost:5000/api/docs
```

Protected by a separate login — requires `superadmin` credentials.

---

### Socket.IO Events

Connect to the server with `socket_io_client`. Join a branch room to receive real-time updates:

```dart
socket.emit('join-branch', branchId); // join branch room
socket.emit('leave-branch', branchId); // leave branch room
```

| Event                 | Payload                                       | Trigger                         |
| --------------------- | --------------------------------------------- | ------------------------------- |
| `transaction-created` | transaction object                            | New transaction                 |
| `payment-completed`   | `{ transactionId, method, amount, branchId }` | Payment done                    |
| `product-created`     | product object                                | Product added                   |
| `product-updated`     | product object                                | Product edited or stock changed |
| `product-deleted`     | `{ id }`                                      | Product removed                 |
| `server-info`         | server status                                 | Every 10 seconds                |

Use `branch_id = 0` to receive events from all branches (superadmin).

---

### Environment Variables

| Variable          | Required | Description                                    |
| ----------------- | -------- | ---------------------------------------------- |
| `PORT`            | ❌       | Server port (default: 3000)                    |
| `NODE_ENV`        | ❌       | `development` or `production`                  |
| `DB_HOST`         | ✅       | MySQL host                                     |
| `DB_USER`         | ✅       | MySQL username                                 |
| `DB_PASS`         | ✅       | MySQL password                                 |
| `DB_NAME`         | ✅       | MySQL database name                            |
| `JWT_SECRET`      | ✅       | Secret key for JWT signing                     |
| `CORS_ORIGIN`     | ❌       | Allowed CORS origins (comma-separated)         |
| `NGROK_AUTHTOKEN` | ❌       | Ngrok auth token (enables tunnel)              |
| `API_TIMEOUT`     | ❌       | Timeout written to `app/.env` (default: 30000) |
