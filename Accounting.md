# GG Store — Accounting (Akuntansi)

How bookkeeping works in GG Store Cashier: what the accounting module does, how every business document turns into journal entries, which reports exist, how the **web back office** (`web/`) and the **Flutter cashier app** (`app/`) use it, and what is still missing or unfinished.

Screen and menu names are written exactly as they appear in the apps (Indonesian), e.g. **Neraca**, **Laba Rugi**, **Buku Besar**.

> Status as of 14 November 2026. Everything described as "implemented" is in the code and was exercised end to end: the integration test (`API/test/integration/accounting.test.js`), the one-year demo data generator (`npm run seed:demo-year`), and a browser check of the back-office pages.

---

## Contents

1. [Overview](#1-overview)
2. [Where the code lives](#2-where-the-code-lives)
3. [Core concepts](#3-core-concepts)
   - [3.1 Chart of accounts (Bagan Akun)](#31-chart-of-accounts-bagan-akun)
   - [3.2 Account mappings (Pemetaan Akun)](#32-account-mappings-pemetaan-akun)
   - [3.3 Journal entries](#33-journal-entries)
   - [3.4 Locations, head office and the inter-location account](#34-locations-head-office-and-the-inter-location-account)
   - [3.5 Document dates and closed periods](#35-document-dates-and-closed-periods)
   - [3.6 Money, PPN and rounding](#36-money-ppn-and-rounding)
4. [Posting rules: what each document books](#4-posting-rules-what-each-document-books)
5. [Reports](#5-reports)
6. [Roles and permissions](#6-roles-and-permissions)
7. [API reference](#7-api-reference)
8. [Web back office: views and usage](#8-web-back-office-views-and-usage)
9. [Flutter app: views and usage](#9-flutter-app-views-and-usage)
10. [How the accounting is used day to day](#10-how-the-accounting-is-used-day-to-day)
11. [Demo data and tests](#11-demo-data-and-tests)
12. [Unfinished and missing](#12-unfinished-and-missing)

---

## 1. Overview

GG Store keeps **double-entry books automatically**. Cashiers, warehouse staff and branch managers never write journals: every business document (a sale, a goods receipt, a supplier payment, a stock count, a transfer, a shift close, an expense) posts its own journal entry in the same database transaction that saves the document. The accountant only adds what has no document of its own (cash deposits to the bank, QRIS settlements, PPN payments, owner drawings) as **manual journals**, enters the **opening balances** once, and **closes each month**.

Principles the module follows:

| Principle | What it means in practice |
|---|---|
| Double entry, always balanced | Every entry's debits equal its credits (checked in cents). An unbalanced entry is refused. |
| Never edited | A posted journal is never changed. Mistakes are corrected with a **reversing entry** (jurnal pembalik); the original is marked *Dibatalkan* (void) and both stay in the ledger. |
| Posted by the document | The posting rules live in one place (`API/src/services/posting.js`), so the same sale always books the same way whether it came from the cashier app, an offline upload or a script. |
| Books per location | Every journal line carries a location (BR01, BR02, BR03, WH) or none (**Pusat**, head office). Reports can be filtered per location and each location's books balance on their own. |
| Dated by the business event | Goods received on 31 Oct and entered on 2 Nov belong to October: the document date drives the journal date, the stock movement date and the document number. |
| Closed months stay closed | Once a month is closed, nothing new can be dated in it. Late automatic postings land on today instead of reopening old books. |
| Prices include PPN | Shelf prices include PPN 11% (setting `tax.prices_include_tax`). Each sale line records the tax inside it; revenue is booked without PPN. |

---

## 2. Where the code lives

| Area | File | Role |
|---|---|---|
| Journal engine | `API/src/services/journal.js` | `postEntry` (balance check, account checks, closed-period rule, JV numbering), `reverseSource` (voids), `resolveAccount` (mappings), `isPeriodClosed`, `dateOnly`. |
| Posting rules | `API/src/services/posting.js` | One function per document type: `postSale`, `voidSaleJournal`, `postSaleReturn`, `postGoodsReceipt`, `postSupplierPayment`, `postStockValue`, `postTransferReceived`, `postCashSessionClose`. |
| Document dates | `API/src/services/documentDate.js` | Validates a document's date: not in the future, not before a related date, not in a closed period. |
| Document numbers | `API/src/services/documents.js` | `{PREFIX}-{LOC or HQ}-{YYMMDD}-{seq}`, numbered by the document's own date. |
| Accounting API | `API/src/routes/accounting.js` | Accounts, journals, manual journals, opening balances, voids, trial balance, profit & loss, balance sheet, ledger, periods, mappings. |
| Expenses API | `API/src/routes/expenses.js` | Biaya: categories, list, create, void. |
| Pulsa deposit API | `API/src/routes/pulsa_deposit.js` | Deposit balance, top-ups, monthly usage. |
| Documents that post | `routes/sales.js`, `cash_sessions.js`, `purchasing.js`, `stock.js`, `opnames.js`, `transfers.js` | Call the posting rules inside their transactions. |
| Schema | `API/migrations/20261031040000_sales_and_accounting.js`, `20261115000000_accounting_completion.js` | Tables `accounts`, `account_mappings`, `journal_entries`, `journal_lines`, `accounting_periods`, `expenses`, chart of accounts and mappings seed. Full schema in `Database.md`. |
| Backfill | `API/scripts/backfill-journals.js` (`npm run accounting:backfill`) | Posts journals for documents recorded before the accounting core existed. Safe to run again. |
| Web pages | `web/src/pages/accounting/*.tsx` | Jurnal, Saldo Awal, Neraca, Laba Rugi, Neraca Saldo, Buku Besar, Bagan Akun, Periode, Pemetaan Akun, Biaya, Deposit Pulsa. |
| Flutter | `app/lib/features/finance` (+ `core/models/accounting.dart`, `core/services/accounting_service.dart`); `features/cashier`, `warehouse`, `inventory`, `home`, `sync` | The Finance tab (expenses, pulsa deposit, journals, manual journals, profit & loss, balance sheet, periods) and the screens that create documents (see [§9](#9-flutter-app-views-and-usage)). |
| Tests | `API/test/integration/accounting.test.js` | End-to-end accounting scenarios against a real MySQL database. |
| Demo data | `API/scripts/demo-year.js` (`npm run seed:demo-year -- --reset`) | One year of store operations through the real API with a simulated clock. |

---

## 3. Core concepts

### 3.1 Chart of accounts (Bagan Akun)

Codes have the form `9-9999`. Parent accounts (`x-0000`) only group; journals post to child accounts (`is_postable`). Codes and types are fixed once created; names can change and accounts can be deactivated (not if a mapping uses them).

Accounts created by the migrations:

| Code | Name | Type | Used by |
|---|---|---|---|
| 1-1100 | Kas | Asset | Cash payments, change, cash refunds, shift differences, expenses / top-ups paid in cash. Mapping `cash`; payment method *Tunai*. |
| 1-1200 | Bank | Asset | Bank transfers from customers, supplier payments, expenses / top-ups paid by bank. Mapping `bank`; payment method *Transfer Bank*. |
| 1-1300 | Piutang QRIS / E-Wallet | Asset | QRIS and e-wallet payments until the provider settles to the bank. Payment methods *QRIS*, *E-Wallet*. |
| 1-1310 | Piutang EDC (Kartu) | Asset | Debit / credit card payments until the bank settles. Payment method *Kartu Debit/Kredit*. |
| 1-1400 | Persediaan Barang | Asset | Stock value at cost. Mapping `inventory`. |
| 1-1500 | PPN Masukan | Asset | Input VAT on supplier invoices. Mapping `ppn_input`. |
| 1-1600 | Deposit Pulsa | Asset | Money paid in advance to the pulsa provider. Mapping `pulsa_deposit`. |
| 1-1700 | Rekening Antar Lokasi | Asset | What one location owes another after a stock transfer; nets to zero company-wide. Mapping `inter_location`. |
| 2-1100 | Hutang Usaha | Liability | Supplier invoices not yet paid. Mapping `accounts_payable`. |
| 2-1200 | PPN Keluaran | Liability | Output VAT inside sales. Mapping `ppn_output`. |
| 3-1000 | Modal Pemilik | Equity | Owner's capital (opening balance, capital injections). |
| 3-2000 | Laba Ditahan | Equity | Exists but is not posted to: retained earnings are computed (see [§5.3](#53-neraca-balance-sheet)). |
| 3-3000 | Ekuitas Saldo Awal | Equity | Balancing figure of the opening balances and the value of opening stock. Mapping `opening_balance`. |
| 4-1000 | Penjualan Barang | Income | Goods sold, without PPN. Mapping `sales_goods`. |
| 4-2000 | Pendapatan Jasa | Income | Repairs / services. Mapping `sales_service`. |
| 4-3000 | Pendapatan Pulsa & Digital | Income | Pulsa, data packages, electricity tokens. Mapping `sales_digital`. |
| 4-9000 | Pendapatan Lain-lain | Income | Free for manual journals. |
| 5-1000 | Harga Pokok Penjualan | Expense (HPP) | Cost of goods sold and pulsa cost. Mapping `cogs`. |
| 5-2000 | Selisih Persediaan | Expense (HPP) | Stock differences: manual adjustments, stock-count differences, write-offs, defective returns, goods lost in transfer. Mapping `inventory_adjustment`. |
| 6-1000 | Beban Sewa | Expense | Rent. |
| 6-1100 | Pajak Bumi & Bangunan | Expense | PBB. |
| 6-2000 | Gaji Karyawan | Expense | Salaries, THR. |
| 6-3000 | Listrik, Air & Internet | Expense | Utilities. |
| 6-9000 | Beban Lain-lain | Expense | Other operating costs. |
| 6-9100 | Selisih Kas | Expense | Cash over / short when a shift is closed. Mapping `cash_over_short`. |

New accounts are added in **Bagan Akun** (web). Every new postable expense account automatically becomes an **expense category** in **Biaya**. The demo data adds `3-1100 Prive Pemilik`, `6-4000 Biaya Administrasi Bank & MDR`, `6-5000 Beban Pemasaran` and `6-6000 Perlengkapan Toko` this way; they are not part of the migrations.

The profit & loss report treats every account whose code starts with `5-` as cost of goods (HPP) for the *Laba kotor* line.

### 3.2 Account mappings (Pemetaan Akun)

Automatic postings never hard-code account codes. They name a **mapping key** and the key resolves to an account. A mapping for a specific location wins over the company-wide one, so, for example, BR02 can book its cash to its own bank account.

| Key | Default account | Meaning |
|---|---|---|
| `cash` | 1-1100 | Cash |
| `bank` | 1-1200 | Bank |
| `ewallet_clearing` | 1-1300 | QRIS / e-wallet receivable (currently not read by any posting; payment methods carry their own account) |
| `card_clearing` | 1-1310 | Card receivable (same note) |
| `inventory` | 1-1400 | Stock |
| `ppn_input` | 1-1500 | Input VAT |
| `pulsa_deposit` | 1-1600 | Pulsa deposit |
| `inter_location` | 1-1700 | Inter-location account |
| `accounts_payable` | 2-1100 | Supplier debt |
| `ppn_output` | 2-1200 | Output VAT |
| `opening_balance` | 3-3000 | Opening-balance equity |
| `sales_goods` | 4-1000 | Goods revenue |
| `sales_service` | 4-2000 | Service revenue |
| `sales_digital` | 4-3000 | Pulsa / digital revenue |
| `cogs` | 5-1000 | Cost of goods sold |
| `inventory_adjustment` | 5-2000 | Stock differences |
| `cash_over_short` | 6-9100 | Shift cash differences |

**Payment methods** (web: **Metode Pembayaran**) each point at their own asset account: *Tunai* → 1-1100, *QRIS* and *E-Wallet* → 1-1300, *Kartu Debit/Kredit* → 1-1310, *Transfer Bank* → 1-1200. A new method (e.g. a second bank) only needs a new asset account.

### 3.3 Journal entries

| Field | Meaning |
|---|---|
| `number` | `JV-{LOC}-{YYMMDD}-{seq}`, or `JV-HQ-…` for head-office entries. Numbered by the entry date. |
| `entry_date` | The business date (see [§3.5](#35-document-dates-and-closed-periods)). |
| `location_id` | Location of the entry; each line also has its own location (they differ only for transfers). Empty = **Pusat**. |
| `source_type`, `source_id` | The document that posted it. |
| `status` | `posted` or `void`. A void entry stays in the books next to its reversal. |
| `reverses_entry_id` | Set on a reversing entry (shown as *Pembalik*). |
| lines | Account, location, debit or credit, memo. |

Source types and how each one is voided:

| `source_type` | Label in the web app | Posted by | Voided / corrected by |
|---|---|---|---|
| `sale` | Penjualan | Every sale (online or offline upload) | Sale void → `sale_void` reversal; partial: a return |
| `sale_void` | Pembatalan penjualan | Voiding a sale | — |
| `sale_return` | Retur penjualan | A return / refund | — |
| `goods_receipt` | Penerimaan barang | Posting a goods receipt | Not possible (purchase returns are not built, see [§12](#12-unfinished-and-missing)) |
| `supplier_payment` | Pembayaran supplier | A supplier payment | Manual journal |
| `stock_adjustment` | Penyesuaian stok | Stock adjustment, opening stock, unit registration, unit write-off | A new adjustment |
| `opname` | Stok opname | Approving a stock count | A new adjustment |
| `transfer` | Transfer | Receiving a transfer; writing off what never arrived | — |
| `cash_session` | Shift kasir | Closing a shift with a cash difference | Manual journal |
| `expense` | Biaya | Recording an expense | Expense void → `expense_void` |
| `expense_void` | Pembatalan biaya | Voiding an expense | — |
| `opening_balance` | Saldo awal | Saldo Awal page | Void on the journal screen |
| `pulsa_deposit` | Top up deposit pulsa | Deposit top-up | Void on the journal screen |
| `manual` | Jurnal manual | The accountant | Void on the journal screen |

Only `manual`, `opening_balance` and `pulsa_deposit` entries can be voided from the **Jurnal** screen. Everything else is voided through its own document so the document and its journal never disagree.

### 3.4 Locations, head office and the inter-location account

- Locations are the warehouse **WH** and the branches **BR01–BR03**. Entries without a location belong to **Pusat** (head office): opening balances of the company bank, salaries of head-office staff, owner drawings, PPN payments.
- Only users who hold `accounting.view` (or `expenses.manage`, for expenses) **for every location** see head-office entries and may post them.
- Each location's books balance on their own. When a transfer arrives, its value leaves the source's *Persediaan* and enters the destination's, and both sides are balanced through **1-1700 Rekening Antar Lokasi** (the destination owes the source). Company-wide the account nets to zero and does not show in the balance sheet.
- There is one bank account (1-1200) unless per-location mappings are added. Because supplier payments are booked at the warehouse and cash deposits at the branches, the per-location balance sheet shows a large negative *Bank* at WH and positive *Bank* at the branches. The company-wide figure is correct.

### 3.5 Document dates and closed periods

**Document dates.** Documents that can be entered late accept a date (`YYYY-MM-DD`, default today). Their stock movements, journal and number all use it:

| Document | Date field | Extra rule |
|---|---|---|
| Goods receipt | *Tanggal barang diterima* (`received_date`) | Checked again when the draft is posted |
| Sale return | *Tanggal retur* | Not before the sale |
| Stock adjustment / opening stock | *Tanggal* | — |
| Unit registration / unit write-off | *Tanggal* | — |
| Stock count approval | *Tanggal penyesuaian* | Not before the count started |
| Transfer send / receive / resolve | *Tanggal kirim / terima* | Receive and resolve not before sending |
| Supplier payment | *Tanggal bayar* | — |
| Expense, pulsa top-up, opening balance, manual journal | *Tanggal* | — |
| Sale | `occurred_at` (set by the device) | Not in the future (offline sales with a clock ahead are corrected and flagged) |

Every dated document refuses dates in the future and dates in a closed month.

**Closing a month** (web: **Periode**) locks it. What happens to something dated in a closed month:

| Kind of posting | Behaviour |
|---|---|
| Manual journal, opening balance, expense, pulsa top-up | Refused: *Periode 2026-10 sudah ditutup*. |
| Dated documents (receipts, returns, adjustments, counts, transfers, supplier payments) | Refused by the date check. |
| Sales (an offline sale uploaded late, or a sale whose time is in a closed month) | Accepted: the sale keeps its own time and number, but its **journal is dated today**, so closed books never change. |
| Voids and reversals | Always dated today. |
| Shift close | Dated at the moment of closing. |

A closed month can be reopened (**Buka kembali**), which is logged in the audit trail.

### 3.6 Money, PPN and rounding

- Amounts are stored with two decimals (sen) and every calculation is done in integer cents.
- Prices include PPN 11% by default: for a line of Rp 89.000 the tax inside is `89.000 × 11 / 111 = Rp 8.819,82` and the revenue is Rp 80.180,18. Because of this, report totals often show sen (e.g. *Rp 268.029.998,1*); that is correct, not a display bug.
- Purchases are entered without PPN (unit cost) plus a tax rate per line; the PPN goes to *PPN Masukan*.
- Stock cost is a moving average per location (`stock_levels.avg_cost`); IMEI units carry their own cost.

---

## 4. Posting rules: what each document books

All examples use real prices from the demo catalog. *Dr* = debit, *Cr* = credit. The location of every line is the document's location unless stated.

### 4.1 Sale (`sale`)

Posted when the sale is saved. Payments go to each payment method's account; change handed back from the drawer reduces the cash line. Revenue is split by line type (goods / service / digital), without PPN. Goods book their cost from stock; pulsa and digital items book their **harga modal** from the pulsa deposit.

*Example: a charger (Rp 89.000, cost Rp 49.000) and a pulsa 10rb (Rp 12.000, harga modal Rp 10.300), paid Rp 101.000 in cash:*

| Account | Debit | Credit |
|---|---:|---:|
| 1-1100 Kas | 101.000 | |
| 4-1000 Penjualan Barang | | 80.180,18 |
| 4-3000 Pendapatan Pulsa & Digital | | 10.810,81 |
| 2-1200 PPN Keluaran | | 10.009,01 |
| 5-1000 Harga Pokok Penjualan | 59.300 | |
| 1-1400 Persediaan Barang | | 49.000 |
| 1-1600 Deposit Pulsa | | 10.300 |

Paid by QRIS instead, the first line would be *1-1300 Piutang QRIS / E-Wallet*. Split payments give one debit line per method.

### 4.2 Sale void (`sale_void`)

**Batalkan** on a sale without returns: every line of the sale journal is mirrored (Dr ↔ Cr), dated today; goods and units go back into stock at their sale cost.

### 4.3 Sale return (`sale_return`)

Part of a sale comes back, refunded through one payment method (cash from the open shift, or another method). The refund is proportional to what the customer paid for the line (after discounts).

| Situation | Booking |
|---|---|
| Revenue and PPN of the returned part | Dr revenue account, Dr 2-1200; Cr refund method's account |
| Goods back on the shelf (*restock*) | Dr 1-1400; Cr 5-1000 (at the sale's unit cost) |
| Goods returned broken (*not restocked*) | Dr 5-2000 Selisih Persediaan; Cr 5-1000; an IMEI unit becomes *defective* |
| Pulsa that never arrived | Dr 1-1600 Deposit Pulsa; Cr 5-1000 (the provider refunds the deposit) |

### 4.4 Goods receipt (`goods_receipt`)

Posting a receipt (draft → *posted*) brings the goods into stock and books the supplier invoice, dated on the receipt date.

*Example: 20 chargers at Rp 49.000, PPN 11%:*

| Account | Debit | Credit |
|---|---:|---:|
| 1-1400 Persediaan Barang | 980.000 | |
| 1-1500 PPN Masukan | 107.800 | |
| 2-1100 Hutang Usaha | | 1.087.800 |

A receipt is final once posted. The payment status (*Belum dibayar / Dibayar sebagian / Lunas*) follows the payments.

### 4.5 Supplier payment (`supplier_payment`)

Dr 2-1100 Hutang Usaha; Cr 1-1100 Kas (method *cash*) or 1-1200 Bank (*transfer*, *giro*, *other*). Booked at the receipt's location, dated *Tanggal bayar*. A payment can't exceed what is still owed; several partial payments are allowed.

### 4.6 Stock value changes (`stock_adjustment`, `opname`)

Any change of stock value that is not a purchase or a sale:

| Event | Booking |
|---|---|
| Manual adjustment up / down (*Sesuaikan*) | Dr / Cr 1-1400 against 5-2000 Selisih Persediaan |
| **Opening stock** (*Stok awal* ticked, or IMEI units registered as opening stock) | Dr 1-1400; Cr **3-3000 Ekuitas Saldo Awal**: stock the business already had is equity brought in, not a gain |
| Registering IMEI units without "Stok awal" | Dr 1-1400; Cr 5-2000 |
| Writing off a unit (*rusak / hilang*) | Dr 5-2000; Cr 1-1400 |
| Approving a stock count | The value of all differences: Dr / Cr 1-1400 against 5-2000; unscanned IMEI units are written off |

### 4.7 Transfer received (`transfer`)

Nothing is booked when goods are sent (they stay in the source's books while in transit). When they arrive, four lines move their value:

*Example: 10 cables (cost Rp 13.500) from WH to BR02:*

| Account | Location | Debit | Credit |
|---|---|---:|---:|
| 1-1400 Persediaan Barang | BR02 | 135.000 | |
| 1-1700 Rekening Antar Lokasi | BR02 | | 135.000 |
| 1-1700 Rekening Antar Lokasi | WH | 135.000 | |
| 1-1400 Persediaan Barang | WH | | 135.000 |

What never arrives is settled at the source (**Selesaikan sisa**): returned to its stock, or written off (Dr 5-2000; Cr 1-1400 at the source).

### 4.8 Shift close (`cash_session`)

Expected cash = opening float + cash received − change − cash refunds (voided sales excluded). If the counted cash differs: short → Dr 6-9100 Selisih Kas, Cr 1-1100; over → the opposite. No journal when the count matches. The opening float itself is not booked: it is cash already in *Kas*.

### 4.9 Expense (`expense`, `expense_void`)

Dr the chosen expense account; Cr 1-1100 Kas or 1-1200 Bank, at the expense's location or at Pusat. Voiding posts the reverse (`expense_void`); the expense stays listed as *Dibatalkan*. Expense numbers: `EXP-{LOC|HQ}-{YYMMDD}-{seq}`.

### 4.10 Pulsa deposit top-up (`pulsa_deposit`)

Dr 1-1600 Deposit Pulsa; Cr 1-1100 or 1-1200. Each pulsa sale then uses the deposit at the item's *Harga modal* (see [§4.1](#41-sale-sale)).

### 4.11 Opening balances (`opening_balance`)

Entered once per location (and once for Pusat) on the day the business starts using the system. Only balance-sheet accounts are allowed. *Persediaan* is refused (stock is entered as opening stock, so quantity and value always match), as are 3-3000 (it is the computed difference) and 1-1700. The difference between debits and credits goes to **3-3000 Ekuitas Saldo Awal** automatically.

*Example (head office): Bank Rp 450 jt debit, Hutang Usaha Rp 86,5 jt credit, Modal Pemilik Rp 300 jt credit → Ekuitas Saldo Awal Rp 63,5 jt credit.*

### 4.12 Manual journal (`manual`)

Free entries by the accountant: at least two lines, each debit *or* credit, balanced, dated, at a location or at Pusat. Typical uses:

| Purpose | Entry |
|---|---|
| Branch cash deposited to the bank | Dr 1-1200 Bank; Cr 1-1100 Kas (at the branch) |
| QRIS / EDC settlement minus MDR | Dr 1-1200 (net), Dr 6-4000 (fee); Cr 1-1300 / 1-1310 |
| Monthly PPN payment | Dr 2-1200 (output of the month); Cr 1-1500 (input available); Cr 1-1200 (the difference paid) |
| Owner drawing | Dr 3-1100 Prive Pemilik; Cr 1-1200 |
| Capital injection | Dr 1-1200; Cr 3-1000 Modal Pemilik |
| Correcting a supplier payment or a shift difference | Mirror of the wrong entry, then the right one |

---

## 5. Reports

All reports read the journals (posted and voided entries together with their reversals, so voids cancel out), can be filtered per location, and export to CSV in the web app.

### 5.1 Neraca Saldo (trial balance)

Total debit and credit per account and its balance on the account's normal side, up to a date (and optionally from a date). Debits always equal credits.

### 5.2 Laba Rugi (profit & loss)

Income and expense accounts for a date range (default: this month):

```
Pendapatan            4-xxxx
− Harga pokok         5-xxxx (HPP + Selisih Persediaan)
= Laba kotor
− Beban operasional   6-xxxx
= Laba bersih
```

### 5.3 Neraca (balance sheet)

Assets, liabilities and equity at the end of a chosen day. There are no year-end closing entries: profit stays in the income and expense accounts and the report computes two equity lines:

- **Laba ditahan (tahun-tahun sebelumnya)**: all profit before 1 January of the report's year.
- **Laba tahun berjalan {year}**: profit from 1 January to the report date.

The header shows *Seimbang: aset = kewajiban + ekuitas* or the difference. Each location's own balance sheet balances too (thanks to 1-1700).

### 5.4 Buku Besar (general ledger)

One account over a date range (default: this month): opening balance, every line with a running balance, closing balance. Clicking a line opens its journal. Ranges with more than 5,000 lines are cut off and say so.

### 5.5 Operational reports that feed the books

| Report | Where | Source |
|---|---|---|
| Expenses by category, total | Web **Biaya** | `expenses` table (void ones excluded) |
| Deposit balance, top-ups, monthly usage | Web **Deposit Pulsa** | Journal lines on 1-1600 |
| Supplier debt per supplier, unpaid receipts | Web **Supplier** (*Hutang*), **Penerimaan Barang** (payment status, due date) | Receipts and payments |
| Shift summaries and cash differences | Web **Shift Kasir**, app shift sheet | Cash sessions |
| Dashboard / Analitik revenue | Web **Dashboard**, **Analitik**; app home | The `sales` table, **including PPN**, returns deducted |

> Dashboard and Analitik figures are sales figures (what customers paid, PPN included), not accounting figures. *Laba Rugi* revenue is lower by the PPN and also counts services and pulsa separately. Use *Laba Rugi* for profit, the dashboards for daily sales.

---

## 6. Roles and permissions

Permissions are held per location (from `user_locations`); a role "for every location" also sees head-office (Pusat) data. The owner has every permission.

| Action | Permission | Owner | Accountant | Branch manager | Warehouse | Cashier |
|---|---|:-:|:-:|:-:|:-:|:-:|
| View journals, ledger, trial balance and every location's reports | `accounting.view` | ✓ | ✓ | | | |
| Laba Rugi and Neraca of own location | `reports.view_location` (or `accounting.view`) | ✓ | ✓ | own branch | | |
| Manual journals, opening balances, new accounts, journal voids | `accounting.post_manual` | ✓ | ✓ | | | |
| Close / reopen periods | `accounting.close_period` | ✓ | ✓ | | | |
| Change account mappings | `settings.manage` | ✓ | | | | |
| Expenses and pulsa top-ups | `expenses.manage` | ✓ | ✓ | own branch | | |
| Goods receipts and supplier payments | `purchases.manage` | ✓ | ✓ | | WH | |
| Suppliers | `suppliers.manage` | ✓ | ✓ | | ✓ | |
| Sale voids, returns, offline review | `sales.void` | ✓ | | own branch | | |
| Sell, open / close own shift | `sales.create`, `cash_session.*` | ✓ | | ✓ | | ✓ |
| Stock adjustments, opening stock, counts | `stock.adjust`, `stock.opname` | ✓ | | ✓ | ✓ | |
| Transfers | `transfers.*` | ✓ | | ✓ | ✓ | |
| All-locations analytics | `reports.view_all` | ✓ | ✓ | | | |

A branch manager sees **Biaya**, **Deposit Pulsa**, **Neraca** and **Laba Rugi** in the web *Akuntansi* menu (and the app's Finance tab), always for their own branch only; journals, the ledger, the trial balance and the setup pages stay closed. The accountant sees everything except mapping edits.

---

## 7. API reference

All routes need a login (`Authorization: Bearer` or the `token` cookie). The interactive API docs are at `/api/docs` on the API server (they have their own login).

**Accounting** (`/api/accounting`)

| Method & path | Permission | Purpose |
|---|---|---|
| `GET /accounts` | accounting.view | Chart of accounts |
| `POST /accounts` · `PUT /accounts/:id` | accounting.post_manual | New account `{ code, name, type?, parent_code? }`; rename / (de)activate |
| `GET /journals?from=&to=&location_id=&source_type=&account_id=` | accounting.view | Up to 300 entries |
| `GET /journals/:id` | accounting.view | Entry with lines |
| `POST /journals` | accounting.post_manual | Manual journal `{ date, location_id?, memo, lines: [{ account_code, debit, credit, memo }] }` |
| `POST /journals/:id/void` | accounting.post_manual | Void a manual journal, opening balance or top-up `{ reason }` |
| `POST /opening-balances` | accounting.post_manual | `{ date, location_id?, memo?, lines: [{ account_code, debit?, credit? }] }` |
| `GET /trial-balance?from=&to=&location_id=` | accounting.view | Neraca saldo |
| `GET /profit-loss?from=&to=&location_id=` | accounting.view, or reports.view_location for own locations | Laba rugi |
| `GET /balance-sheet?to=&location_id=` | accounting.view, or reports.view_location for own locations | Neraca |
| `GET /ledger?account_id=&from=&to=&location_id=` | accounting.view | Buku besar |
| `GET /periods` | accounting.view | Periods and who closed them |
| `POST /periods/:year/:month/close` · `/reopen` | accounting.close_period | Close / reopen a month |
| `GET /mappings` · `PUT /mappings` | accounting.view · settings.manage | Mapping keys `{ key, account_code, location_id? }` |

**Expenses** (`/api/expenses`) and **pulsa deposit** (`/api/pulsa-deposit`)

| Method & path | Permission | Purpose |
|---|---|---|
| `GET /api/expenses/categories` | expenses.manage or accounting.view | Expense accounts usable as categories |
| `GET /api/expenses?location_id=&from=&to=&account_id=&status=` | expenses.manage or accounting.view | List, total, per category |
| `GET /api/expenses/:id` | same | One expense with its journal number |
| `POST /api/expenses` | expenses.manage | `{ location_id?, date, account_code, amount, paid_from: cash|bank, payee?, note? }` |
| `POST /api/expenses/:id/void` | expenses.manage | `{ reason }` |
| `GET /api/pulsa-deposit?location_id=&from=&to=` | expenses.manage or accounting.view | Balance, top-ups, usage per month |
| `POST /api/pulsa-deposit/top-ups` | expenses.manage | `{ location_id?, date, amount, paid_from, note? }` |

**Documents that post journals**: `POST /api/sales`, `POST /api/sales/:id/void`, `POST /api/sales/:id/returns`, `POST /api/cash-sessions/:id/close`, `POST /api/purchasing/receipts/:id/post`, `POST /api/purchasing/payments`, `POST /api/stock/adjust`, `POST /api/stock/units`, `POST /api/stock/units/:id/write-off`, `POST /api/opnames/:id/approve`, `POST /api/transfers/:id/receive`, `POST /api/transfers/:id/resolve`.

---

## 8. Web back office: views and usage

The back office (`web/`, React + Vite, `http://localhost:5173`) is where accounting is done. The menu group **Akuntansi** holds the accounting pages; other groups hold the pages whose documents post journals. Menu items appear only for users with the needed permission (the API checks again).

### 8.1 The Akuntansi menu

| Page | Path | Who | What it shows | What you can do |
|---|---|---|---|---|
| **Biaya** | `/accounting/expenses` | expenses.manage or accounting.view | Expenses with location, category, payee, paid from, amount, status; *Per kategori* totals | Filter by location, dates (default this month), category, status. **Catat biaya** (date, location or Pusat, category, amount, paid from Kas/Bank, payee, note). Open an expense to see its journal number and **Batalkan** it with a reason. CSV. |
| **Deposit Pulsa** | `/accounting/pulsa-deposit` | expenses.manage or accounting.view | *Saldo deposit sekarang* (red when negative), top-ups and usage in the period, monthly usage table | Filter by location and dates (default 1 Jan to today). **Top up** (date, location, amount, paid from, note). Click a top-up to open its journal. |
| **Jurnal** | `/accounting/journals` | accounting.view | Entries: number, date, location, source, memo, amount, *Dibatalkan* / *Pembalik* badges | Filter by location, dates, source, account. Open an entry to see its lines (with each line's location). **Jurnal manual** (post_manual). Void manual journals, opening balances and top-ups with a reason. CSV. |
| **Saldo Awal** | `/accounting/opening-balances` | accounting.view (posting: post_manual) | A form listing every balance-sheet account, with a live *Ekuitas Saldo Awal (otomatis)* line; the opening balances already posted | Enter debit / credit per account, choose date and location (or Pusat), **Posting saldo awal**. The page explains that stock is entered as opening stock in **Stok**. |
| **Neraca** | `/accounting/balance-sheet` | accounting.view; branch managers for their own branch | Assets, liabilities, equity with the computed *Laba ditahan* and *Laba tahun berjalan* lines; balance check | Choose location and *Per tanggal*. CSV. |
| **Laba Rugi** | `/accounting/profit-loss` | accounting.view; branch managers for their own branch | Income and expense accounts; *Pendapatan, Harga pokok penjualan, Laba kotor, Beban operasional, Laba bersih* | Choose location and dates (default this month). CSV. |
| **Neraca Saldo** | `/accounting/trial-balance` | accounting.view | Debit, credit and balance per account; totals | Choose location, *Dari (opsional)*, *Sampai*. CSV. |
| **Buku Besar** | `/accounting/ledger` | accounting.view | Opening balance, lines with running balance, closing balance | Choose account, location, dates. Click a line to open its journal. CSV. |
| **Bagan Akun** | `/accounting/accounts` | accounting.view (editing: post_manual) | Account tree with *Sistem* / *Nonaktif* badges | **Akun baru** (code, name, parent, type); rename, deactivate. |
| **Periode** | `/accounting/periods` | accounting.view (closing: close_period) | Periods with status and who closed them, when | **Tutup periode** (year, month); **Buka kembali**. |
| **Pemetaan Akun** | `/accounting/mappings` | accounting.view (editing: settings.manage) | Every mapping key with its account, company-wide and per location | Change a mapping, add a per-location mapping (**Pemetaan lokasi**), remove a per-location mapping. |

### 8.2 Other pages that create accounting entries

| Page | Path | Accounting effect |
|---|---|---|
| **Penjualan** / sale detail | `/sales`, `/sales/:id` | List with filters (including *Penjualan offline*, *Offline, perlu dicek*). On a sale: **Retur** (lines, quantity, restock or broken, refund method, *Tanggal retur*), **Batalkan** (void), **Tandai sudah dicek** for offline sales with differences. |
| **Shift Kasir** | `/shifts` | Shifts with opening float, expected and counted cash, difference. View only: shifts are opened and closed in the cashier app. |
| **Penerimaan Barang** / receipt | `/receipts`, `/receipts/:id` | Drafts with *Tanggal barang diterima*, invoice number and dates, items and IMEIs; **Posting** books stock and the invoice; **Catat pembayaran** records a supplier payment (amount, method, reference, *Tanggal bayar*). Filter by payment status (*Belum dibayar, Dibayar sebagian, Lunas*). |
| **Supplier** | `/suppliers` | *Hutang* (outstanding debt) per supplier. |
| **Stok** | `/stock` | **Sesuaikan** with *Tanggal* and the *Stok awal* checkbox (opening stock needs a unit cost); **Unit** → *Daftarkan unit* registers IMEI units, also as *Stok awal*; location prices. |
| **Unit IMEI/Serial** | `/units` | Find a unit by IMEI; **Tandai rusak** or **Hapus dari stok** writes it off (Selisih Persediaan). |
| **Stok Opname** / count | `/opnames`, `/opnames/:id` | Count quantities, scan IMEIs, approve with *Tanggal penyesuaian*. |
| **Transfer Stok** / transfer | `/transfers`, `/transfers/:id` | Send, receive (full or partial) and resolve, each with its date. |
| **Produk** / product | `/catalog/:id` | *Harga modal* (cost price) for pulsa and digital variants. |
| **Metode Pembayaran** | `/settings/payment-methods` | Which asset account each payment method books to. |
| **Tarif Pajak** | `/settings/tax-rates` | PPN rates per product (default PPN 11%). |
| **Dashboard**, **Analitik** | `/`, `/analytics` | Sales figures (PPN included), not accounting figures. |

### 8.3 Typical flows in the web app

**Starting to use the system (once)**
1. **Bagan Akun**: add any accounts the business needs (e.g. *Prive Pemilik*, *Beban Pemasaran*).
2. **Saldo Awal**: enter bank, debts and capital for Pusat; cash and pulsa deposit for each branch.
3. **Stok**: enter what is on the shelves with **Sesuaikan** and *Stok awal* ticked, with its cost; register phones with **Unit → Daftarkan unit**, *Stok awal* ticked.
4. **Produk**: set *Harga modal* on pulsa and digital items.
5. **Metode Pembayaran** and **Pemetaan Akun**: check the accounts (e.g. a per-branch bank).

**Every day / week**
- Supplier invoices: **Penerimaan Barang** → **Posting**; pay on the due date with **Catat pembayaran**.
- Branch cash and QRIS / EDC: **Jurnal → Jurnal manual** (deposit, settlement minus MDR).
- Returns and voids: from the sale's page.
- Costs: **Biaya**; pulsa top-ups: **Deposit Pulsa**.

**Every month**
1. Check *Offline, perlu dicek* in **Penjualan** and differences in **Shift Kasir**.
2. Pay PPN for the previous month (manual journal).
3. Review **Neraca Saldo**, **Laba Rugi**, **Neraca** per location.
4. **Periode → Tutup periode** for the previous month.

---

## 9. Flutter app: views and usage

The cashier app (`app/`, Flutter) is where most documents are **created**, and since 14 November 2026 it also has its own **Finance** tab for accounting inputs and reports.

### 9.1 The Finance tab (Keuangan)

A tab between *Inventory* and *Settings*, shown only to users with `expenses.manage`, `reports.view_location` or `accounting.view` (a cashier doesn't see it, and `#/finance` sends them back to Home). The home screen of branch staff also gets a **Keuangan** quick action. Code: `app/lib/features/finance/`, `core/models/accounting.dart`, `core/services/accounting_service.dart`. It uses the same API as the web, so every permission is checked again by the server.

| What | Branch admin (own branch) | Owner / accountant (every location and Pusat) |
|---|---|---|
| **Keuangan** hub | This month's revenue, net profit, expenses and pulsa balance for the branch | This month's revenue and net profit, expenses and pulsa balance, company-wide |
| **Biaya** | List by month with per-category totals; **Catat Biaya** (date, category, amount, from Kas / Bank, payee, note); open one to see its journal number and **Batalkan biaya** | The same for every location; filter by location or *Semua lokasi*; can record head-office (Pusat) expenses |
| **Deposit Pulsa** | Current balance, top-ups and usage per month for a year; **Top Up** | The same per location or all; tapping a top-up opens its journal (and can void it) |
| **Jurnal Manual** | — | Balanced entry with any number of lines, a searchable account picker, quick templates (*Setor kas ke bank, Pencairan QRIS, Pencairan EDC, Setoran modal*) and the amount mirrored to the other side for two-line entries |
| **Jurnal** | — | List by month, location and source; detail with lines (credits indented, line locations for transfers); **Batalkan jurnal** for manual journals, opening balances and top-ups |
| **Laba Rugi** | Their branch, per month or from 1 January | Per month or from 1 January, per location or all: revenue, cost of goods, gross profit, operating costs, net profit, and every account |
| **Neraca** | Their branch, as of any day | As of any day, per location or all, with the balance check and the computed retained-earnings lines |
| **Periode** | — | The last 18 months; **Tutup** / **Buka kembali** with confirmation (`accounting.close_period`) |

Re-tapping the Finance tab (or any tab) returns to its first screen.

Not in the app (web only): Saldo Awal, Bagan Akun, Pemetaan Akun, Neraca Saldo and Buku Besar.

### 9.2 Screens that create accounting documents

| Screen | Where in the app | Accounting effect |
|---|---|---|
| **Home** (cashier / branch view) | Tab *Home* | *Pendapatan Hari Ini, Transaksi Hari Ini, Transaksi Bulan Ini, Stok Kritis* and the latest transactions (tap one to reprint its receipt). Sales figures from `/api/dashboard`, PPN included. |
| **Dashboard Analitik** (owner / accountant) | Tab *Home*, for users with `reports.view_all` | *Tren Pendapatan*, *Pendapatan per Cabang*, *Penjualan per Kategori*, *Produk Terlaris*. Sales figures, not accounting. |
| **Kasir** (cashier) | Tab *Kasir* | Builds the cart (goods, IMEI units, services with a typed price, pulsa), applies vouchers, prices it through the server (`/api/sales/quote`) and takes payment. Each sale posts a **sale** journal (§4.1). |
| Payment sheet | Kasir → Bayar | One or more methods (**split bayar**), reference numbers where required, change from cash, customer for IMEI sales. Offline: cash only. |
| **Shift** sheet | Kasir → shift button | **Buka Shift** with an opening float; shows *Modal awal, Penjualan, per method, Kas seharusnya*; **Tutup Shift** with *Uang tunai dihitung* and a note. A difference posts to *Selisih Kas* (§4.8). The shift can't be closed while its offline sales are still unsent. |
| Offline sales and **Sinkronisasi** | Settings → *Sinkronisasi* | Sales made without a connection are queued and uploaded later as facts. Differences (price changed, stock gone, closed shift) are flagged for review in the web app; journals of sales that land in a closed month are dated on upload (§3.5). |
| Receipt / reprint | After payment; Home → a transaction | ESC/POS printing over Bluetooth or network. No accounting effect. |
| **Gudang** menu → *Penerimaan Barang* | Inventory → warehouse icon | Create and post receipts (with IMEIs, invoice no., invoice and due dates). Posting books stock and supplier debt (§4.4). **Catat Pembayaran** records a supplier payment (amount, Transfer / Tunai / Giro / Lain, reference, *Tanggal bayar*) (§4.5). |
| Gudang → *Transfer Stok* | same | Create, send, receive (with quantities received), resolve. Receiving posts the transfer (§4.7). |
| Gudang → *Stok Opname* | same | Start a count, enter quantities, scan IMEIs, approve (§4.6). |
| Gudang → *Supplier* | same | Supplier list and details. |
| Inventory → **Sesuaikan Stok** | Product detail | Add or remove quantity with an optional unit cost and a reason (§4.6). |
| Inventory → register IMEI units | Product detail | Register units with their cost (§4.6). |
| **Vouchers** | Settings → *Vouchers* | Create and edit vouchers (discounts reduce revenue in the sale journal). |

What the app sends compared with the web: it **does not send document dates** (receipts, adjustments, counts and transfers are dated today) and **does not have the "Stok awal" option**. Stock added in the app is a normal adjustment and lands in *Selisih Persediaan*, not *Ekuitas Saldo Awal* (see [§12.1](#121-flutter-app)).

---

## 10. How the accounting is used day to day

The demo data (`npm run seed:demo-year`) follows this routine for a year, and it is the intended way to run the store:

| When | Who | Where | What |
|---|---|---|---|
| First day | Owner | Web: Saldo Awal, Stok | Opening balances (Pusat bank, supplier debt, capital; each branch's cash and pulsa deposit) and opening stock with IMEIs |
| Every morning | Cashier | App: Shift | Open the shift with a Rp 500.000 float |
| All day | Cashier | App: Kasir | Sales; phones need a customer; vouchers during promos |
| All day | Branch manager | Web: Penjualan | Returns and voids; discounts beyond the cashier's rights |
| Every evening | Cashier | App: Shift | Close the shift; small differences go to *Selisih Kas* |
| Mondays (phones), 1st and 16th (accessories) | Warehouse | App or web: Penerimaan Barang | Receive and post supplier deliveries |
| Tuesdays and Fridays | Warehouse → branch manager | App or web: Transfer Stok | Ship from WH, receive at the branch |
| On the due date | Accountant | Web: Penerimaan Barang → Catat pembayaran | Pay supplier invoices |
| Twice a week | Accountant | App or web: Jurnal manual | Deposit branch cash to the bank; settle QRIS / EDC minus MDR |
| When the deposit runs low | Branch manager | App (Finance) or web: Deposit Pulsa → Top up | Top up the pulsa deposit |
| Monthly | Accountant | App or web: Biaya | Rent (1st), utilities (5th–8th), salaries (25th), THR before Lebaran, PBB once a year |
| 2nd and 16th, 10th | Branch manager | App (Finance) or web: Biaya | Store supplies and security fee paid from branch cash |
| 20th | Accountant | App or web: Jurnal manual | Pay last month's PPN (output − input) |
| 28th | Owner | App or web: Jurnal manual | Owner drawing (*Prive*) |
| 8th | Accountant | App or web: Periode | Close last month |
| Quarter end | Branch manager, warehouse | App or web: Stok Opname | Full count with IMEI scanning |

---

## 11. Demo data and tests

**Demo data.** `npm run seed:demo-year -- --reset` rebuilds the dev database (`DB_NAME`) with one year of operations, 1 November 2025 to today, through the real API code with a simulated clock (JavaScript `Date` and MySQL `NOW()` follow the simulated day). The last run produced about 26,000 sales, 3,100 customers, 228 returns, 158 receipts, 334 transfers, 410 expenses, 672 manual journals and 16 stock counts. November 2025 to October 2026 are closed. Net profit was about Rp 79 jt for Nov–Dec 2025 and Rp 353 jt for 2026 to date. The books balance company-wide and per location. It refuses `NODE_ENV=production`; details in the README.

**Tests.**

```bash
TEST_DB_NAME=gg_test_accounting npm run test:integration
```

The test database (its name must start with `gg_test`) is dropped and rebuilt. It covers opening balances, opening stock, dated receipts, closed periods, dated sales and returns, pulsa cost and refunds, expenses (permissions, numbering, void), transfers through the inter-location account, stock-count dates, and checks that the trial balance, profit & loss, balance sheet (company and per location) and ledger agree.

---

## 12. Unfinished and missing

### 12.1 Flutter app

**Unfinished screens and dead buttons** (they show, but do nothing or go to the wrong place):

| Where | Item | State |
|---|---|---|
| Settings → Store | **Store Profile** | Empty `onTap`, no page |
| Settings → Preferences | **Notifications** | Empty `onTap`, no page |
| Settings → Support | **Privacy & Security** | Empty `onTap`, no page |
| Settings → Support | **Help Center** | Empty `onTap`, no page |
| Home → *Transaksi Terbaru* | **Lihat Semua** | Empty `onPressed`; there is no sales history screen in the app |
| Home → quick actions | **Pasang Kupon** | Opens the cashier, not the coupon page |
| Home → quick actions | **Kontrol Perangkat** | Opens the cashier, not the device manager (route `/devices/manager` exists) |

**Accounting functions the app doesn't have** (web only today):

- No sales history or sale detail, so no **returns**, **voids** or **review of offline sales** in the app.
- The Finance tab (§9.1) has no **Saldo Awal**, **Bagan Akun**, **Pemetaan Akun**, **Neraca Saldo** or **Buku Besar**, and no CSV export.
- No **document dates** on warehouse documents: receipts, adjustments, counts, transfers and unit registrations made in the app are always dated today, so goods received yesterday and entered today land on today.
- No **Stok awal** option: stock added in the app books to *Selisih Persediaan* instead of *Ekuitas Saldo Awal*, which overstates profit when used for opening stock.
- The supplier payment date picker allows future dates (up to 2100); the API refuses them with an error message instead of the app preventing it.

### 12.2 Web back office

- **Shift Kasir is view-only.** A manager can't close a shift left open (the API allows it for `cash_session.view_all`). A stuck shift blocks its cashier from opening a new one until it is closed through the API.
- **Pemetaan Akun** has no labels for `inter_location` and `pulsa_deposit` (added with the accounting completion); they show their raw key.
- The **Periode** page says closed months refuse sales dated in them; in fact sales are accepted and their journal is moved to today (§3.5).
- No dedicated screens for routine accountant work that is done with manual journals today: **cash deposit to bank**, **QRIS / EDC settlement with MDR**, **PPN settlement** (no PPN report either), **owner drawings**.
- Missing reports: **cash flow statement** (arus kas), **supplier ageing** (only total debt per supplier and due dates), **comparative / monthly P&L**, **PPN report** (output vs input per month).
- The sales list ignores filters in the URL (e.g. `/sales?sync=issues`); the filter has to be picked on the page.

### 12.3 API and the module as a whole

- **Purchase returns are not built.** Posting a goods receipt is final and the code says corrections "go through purchase returns", but there is no purchase-return document. Today a wrong receipt can only be corrected with a stock adjustment plus a manual journal.
- **Trade-ins and repair parts**: stock movement reasons `trade_in` and `service_part` exist in the schema, but no flow uses them. Service revenue therefore has no cost of parts.
- **Cash refunds aren't limited to the cash in the drawer.** A cash refund larger than the drawer holds makes the expected cash negative, and the shift then can't be closed with a normal count.
- **No customer receivables**: every sale must be paid in full at the counter; there is no credit sale / piutang pelanggan.
- **No bank reconciliation** and a single bank account unless per-location mappings are added; supplier payments make the warehouse's own *Bank* balance negative (§3.4).
- **No year-end closing entry** (by design: retained earnings are computed). Account *3-2000 Laba Ditahan* stays unused.
- Mapping keys `ewallet_clearing` and `card_clearing` are defined but not used by any posting (payment methods carry their own account).
