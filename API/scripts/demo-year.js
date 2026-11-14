#!/usr/bin/env node
/**
 * A year of demo data for the dev database, made through the real API code.
 *
 *   npm run seed:demo-year -- --reset
 *
 * Options:
 *   --reset            drop and re-create DB_NAME, then migrate and seed it (needed unless the
 *                      database has no products, sales or journals yet)
 *   --from=YYYY-MM-DD  the day the shop starts using the system (default 2025-11-01)
 *   --to=YYYY-MM-DD    last day (default today; today stops at the current time and its shifts
 *                      stay open)
 *   --scale=1          more or fewer customers per day
 *   --seed=2025        random seed: the same seed gives the same data
 *
 * How: the routers are mounted in this process (no rate limit, no socket events) and every request
 * runs at a simulated time. JavaScript's Date and MySQL's NOW() (SET TIMESTAMP on each connection)
 * both follow that clock, so document numbers, stock movements, journals, shifts and created_at
 * columns all carry the moment they "happened", and closed periods are enforced as in real use.
 *
 * The story: GG Store sells phones, accessories, pulsa and repairs from three branches (BR01 busiest,
 * BR03 smallest) supplied by a warehouse (WH).
 *   - Day one: opening balances (bank, branch cash, pulsa deposit, supplier debt, capital) and
 *     opening stock with IMEIs. New accounts: 3-1100 Prive Pemilik, 6-4000 admin bank & MDR,
 *     6-5000 pemasaran, 6-6000 perlengkapan toko.
 *   - Every day each branch opens a shift, sells (busier on weekends, paydays, December, the
 *     run-up to Lebaran; closed on Idul Fitri), closes the shift (sometimes a little short).
 *     Phones need a customer; vouchers run during promos; a few sales are returned or voided.
 *   - The warehouse buys phones every Monday and accessories on the 1st and 16th, and ships to the
 *     branches every Tuesday and Friday. Supplier invoices are paid on their due date.
 *   - The accountant deposits branch cash, settles QRIS/EDC (minus MDR), pays rent, salaries
 *     (and THR), utilities and ads, settles PPN on the 20th and closes last month on the 8th. The
 *     owner takes Rp 30 jt a month (3-1100 Prive Pemilik) and adds capital if the bank runs low.
 *   - Branch managers top up the pulsa deposit, buy store supplies from cash, write off damaged
 *     items and run the quarter-end stock counts.
 *   - Prices change a few times, two new phones launch, BR03 loses its connection one afternoon
 *     (offline sales with a price difference to review) and one transfer arrives short.
 *
 * Refuses NODE_ENV=production.
 */
'use strict';
const path = require('path');
const crypto = require('crypto');

const ROOT = path.join(__dirname, '..', '..');
require('dotenv').config({ path: path.join(ROOT, '.env') });

const RealDate = Date;
const pad = (n) => String(n).padStart(2, '0');
const ymdOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

// ── options ──────────────────────────────────────────────────────────────────

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
    const [key, ...value] = a.replace(/^--/, '').split('=');
    return [key, value.length ? value.join('=') : true];
}));
const REAL_TODAY = ymdOf(new RealDate());
const FROM = args.from || '2025-11-01';
const TO = args.to || REAL_TODAY;
const SCALE = Number(args.scale || 1);
const SEED = Number(args.seed || 2025);
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

const die = (message) => {
    console.error(`demo-year: ${message}`);
    process.exit(1);
};
if (process.env.NODE_ENV === 'production') die('refusing to run with NODE_ENV=production');
if (!DAY_RE.test(FROM) || !DAY_RE.test(TO) || FROM > TO) die('--from and --to must be YYYY-MM-DD with from <= to');
if (TO > REAL_TODAY) die('--to cannot be in the future');
if (!(SCALE > 0)) die('--scale must be > 0');
if (!process.env.DB_NAME) die('DB_NAME is not set');

// ── random numbers (seeded) ──────────────────────────────────────────────────

let rngState = SEED >>> 0;
const rand = () => {
    rngState = (rngState + 0x6D2B79F5) >>> 0;
    let t = rngState;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const chance = (p) => rand() < p;
const between = (a, b) => a + Math.floor(rand() * (b - a + 1));
const pick = (list) => list[Math.floor(rand() * list.length)];
const weighted = (items, weightOf) => {
    const total = items.reduce((s, i) => s + weightOf(i), 0);
    let r = rand() * total;
    for (const item of items) {
        r -= weightOf(item);
        if (r <= 0) return item;
    }
    return items[items.length - 1];
};
const roundTo = (n, step) => Math.round(n / step) * step;

// ── calendar ─────────────────────────────────────────────────────────────────

const parseDay = (s) => {
    const [y, m, d] = s.split('-').map(Number);
    return new RealDate(y, m - 1, d);
};
const addDays = (s, n) => {
    const d = parseDay(s);
    d.setDate(d.getDate() + n);
    return ymdOf(d);
};
const dow = (s) => parseDay(s).getDay(); // 0 = Sunday
const dayNum = (s) => Number(s.slice(8));
const monthOf = (s) => s.slice(0, 7);
const lastDayOfMonth = (s) => {
    const d = parseDay(s);
    return ymdOf(new RealDate(d.getFullYear(), d.getMonth() + 1, 0));
};
const prevMonth = (ym) => monthOf(addDays(`${ym}-01`, -1));
const at = (day, h, m = 0, s = 0) => {
    const d = parseDay(day);
    d.setHours(h, m, s, between(0, 999));
    return d.getTime();
};
const MONTHS_ID = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
const monthName = (ym) => `${MONTHS_ID[Number(ym.slice(5)) - 1]} ${ym.slice(0, 4)}`;
const stamp = (day) => day.slice(2).replace(/-/g, '');

// Idul Fitri 1447 H: the shops are closed.
const CLOSED = new Set(['2026-03-20', '2026-03-21']);
const LEBARAN_RUSH = (day) => day >= '2026-03-09' && day <= '2026-03-19';
const QUARTER_ENDS = new Set(['2025-12-31', '2026-03-31', '2026-06-30', '2026-09-30']);

// How busy a day is compared with an ordinary Thursday (no randomness: also used for planning).
const dayMult = (day) => {
    if (CLOSED.has(day)) return 0;
    let m = [1.2, 0.9, 0.95, 0.95, 1.0, 1.05, 1.3][dow(day)];
    const d = dayNum(day);
    const md = day.slice(5);
    if (d >= 25 || d <= 2) m *= 1.15; // payday
    if (md >= '12-15' && md <= '12-24') m *= 1.2;
    if (md >= '12-25') m *= 1.3;
    if (md === '01-01') m *= 0.6;
    if (md === '12-12') m *= 1.4;
    if (md === '11-11') m *= 1.2;
    if (md >= '02-01' && md <= '02-17') m *= 0.9;
    if (day >= '2026-02-18' && day <= '2026-03-08') m *= 1.05; // Ramadan
    if (LEBARAN_RUSH(day)) m *= day === '2026-03-19' ? 1.3 : 1.6; // THR money, mudik
    if (day >= '2026-03-22' && day <= '2026-03-28') m *= 0.7; // many still away
    if (md >= '07-06' && md <= '07-20') m *= 1.1; // new school year
    if (md >= '08-14' && md <= '08-18') m *= 1.15;
    if (day === '2026-05-27') m *= 0.8; // Idul Adha
    m *= 1 + 0.08 * Math.min(1, (parseDay(day) - parseDay(FROM)) / (365 * 864e5)); // slow growth
    return m;
};

// ── the shop ─────────────────────────────────────────────────────────────────

const BRANCHES = [
    { code: 'BR01', weight: 1.2, kasir: 'kasir1', admin: 'admin1', dayOff: 1, rent: 6_000_000, elec: [1_300_000, 1_750_000] },
    { code: 'BR02', weight: 1.0, kasir: 'kasir2', admin: 'admin2', dayOff: 2, rent: 5_000_000, elec: [1_100_000, 1_500_000] },
    { code: 'BR03', weight: 0.78, kasir: 'kasir3', admin: 'admin3', dayOff: 3, rent: 4_000_000, elec: [900_000, 1_250_000] },
];
const BASE_TX = 20 * SCALE; // transactions on an ordinary day at a branch of weight 1
const TYPE_P = { phone: 0.10, acc: 0.52, digital: 0.30, service: 0.08 };
const typeProbs = (day) => {
    const p = { ...TYPE_P };
    if (LEBARAN_RUSH(day)) p.phone *= 1.8;
    const md = day.slice(5);
    if (md >= '12-10' && md <= '12-14') p.phone *= 1.3;
    const total = Object.values(p).reduce((s, x) => s + x, 0);
    for (const k of Object.keys(p)) p[k] /= total;
    return p;
};
const ACC_LINES = [[1, 0.65], [2, 0.27], [3, 0.08]];
const E_ACC_LINES = 1.43 * 1.05;

const SUPPLIERS = [
    { key: 'SSD', name: 'PT Sinar Seluler Distribusi', address: 'Jl. Urip Sumoharjo No. 120, Makassar', terms: 14 },
    { key: 'MGN', name: 'PT Mega Gadget Nusantara', address: 'Jl. A.P. Pettarani No. 45, Makassar', terms: 14 },
    { key: 'PAM', name: 'CV Prima Aksesori Makassar', address: 'Jl. Sulawesi No. 88, Makassar', terms: 30 },
    { key: 'MDK', name: 'CV Mitra Digital Komunika', address: 'Jl. Veteran Selatan No. 17, Makassar', terms: 30 },
];

// Phones are sold per IMEI unit (dual SIM, 12 months warranty). w = how popular.
const PHONES = [
    { name: 'Samsung Galaxy A06', brand: 'Samsung', supplier: 'SSD', variants: [
        { key: 'A06-464', name: '4/64GB', price: 1_549_000, cost: 1_265_000, w: 10 },
        { key: 'A06-4128', name: '4/128GB', price: 1_749_000, cost: 1_430_000, w: 7 },
    ] },
    { name: 'Samsung Galaxy A16', brand: 'Samsung', supplier: 'SSD', variants: [
        { key: 'A16-8128', name: '8/128GB', price: 2_999_000, cost: 2_430_000, w: 6 },
    ] },
    { name: 'Xiaomi Redmi 14C', brand: 'Xiaomi', supplier: 'MGN', variants: [
        { key: 'R14C-4128', name: '4/128GB', price: 1_499_000, cost: 1_215_000, w: 12 },
        { key: 'R14C-6128', name: '6/128GB', price: 1_699_000, cost: 1_375_000, w: 6 },
    ] },
    { name: 'Xiaomi Redmi Note 14', brand: 'Xiaomi', supplier: 'MGN', variants: [
        { key: 'RN14-8256', name: '8/256GB', price: 2_899_000, cost: 2_350_000, w: 6, later: { from: '2026-03-03', w: 2.5 } },
    ] },
    { name: 'OPPO A3x', brand: 'OPPO', supplier: 'MGN', variants: [
        { key: 'A3X-464', name: '4/64GB', price: 1_699_000, cost: 1_385_000, w: 6, later: { from: '2026-08-04', w: 3 } },
        { key: 'A3X-4128', name: '4/128GB', price: 1_899_000, cost: 1_545_000, w: 4 },
    ] },
    { name: 'vivo Y19s', brand: 'vivo', supplier: 'MGN', variants: [
        { key: 'Y19S-6128', name: '6/128GB', price: 1_899_000, cost: 1_540_000, w: 6 },
    ] },
    { name: 'realme C61', brand: 'realme', supplier: 'SSD', variants: [
        { key: 'C61-6128', name: '6/128GB', price: 1_599_000, cost: 1_295_000, w: 7 },
    ] },
    { name: 'Xiaomi Redmi Note 15', brand: 'Xiaomi', supplier: 'MGN', launch: '2026-03-02', variants: [
        { key: 'RN15-8256', name: '8/256GB', price: 3_299_000, cost: 2_680_000, w: 8 },
    ] },
    { name: 'OPPO A6x', brand: 'OPPO', supplier: 'MGN', launch: '2026-08-03', variants: [
        { key: 'A6X-6128', name: '6/128GB', price: 1_999_000, cost: 1_620_000, w: 7 },
    ] },
];
// addon = chance it is bought together with a phone.
const ACCESSORIES = [
    { name: 'Tempered Glass', supplier: 'PAM', variants: [
        { key: 'TG-STD', name: 'Standar', price: 25_000, cost: 6_500, w: 14, addon: 0.44 },
        { key: 'TG-SPY', name: 'Anti-Spy', price: 55_000, cost: 17_000, w: 4, addon: 0.11 },
    ] },
    { name: 'Casing Silikon', supplier: 'PAM', variants: [
        { key: 'CS-HTM', name: 'Hitam', price: 30_000, cost: 9_000, w: 6, addon: 0.22 },
        { key: 'CS-BNG', name: 'Bening', price: 30_000, cost: 9_000, w: 6, addon: 0.23 },
    ] },
    { name: 'Kabel Data USB-C 1m', supplier: 'PAM', variants: [{ key: 'KBL-C', price: 35_000, cost: 13_500, w: 10 }] },
    { name: 'Kabel Data Lightning 1m', supplier: 'PAM', variants: [{ key: 'KBL-L', price: 45_000, cost: 18_000, w: 4 }] },
    { name: 'Kabel Data Micro USB 1m', supplier: 'PAM', variants: [{ key: 'KBL-M', price: 25_000, cost: 9_000, w: 4 }] },
    { name: 'Charger 20W USB-C', supplier: 'PAM', variants: [{ key: 'CHG-20', price: 89_000, cost: 49_000, w: 6 }] },
    { name: 'Charger 33W Fast Charging', supplier: 'PAM', variants: [{ key: 'CHG-33', price: 135_000, cost: 76_000, w: 3 }] },
    { name: 'Earphone Kabel 3.5mm', supplier: 'PAM', variants: [{ key: 'EAR-35', price: 35_000, cost: 14_000, w: 4 }] },
    { name: 'Holder HP Motor', supplier: 'PAM', variants: [{ key: 'HLD-MTR', price: 55_000, cost: 24_000, w: 2 }] },
    { name: 'TWS Bluetooth Earbuds', supplier: 'MDK', variants: [{ key: 'TWS', price: 149_000, cost: 82_000, w: 4 }] },
    { name: 'Powerbank 10.000mAh', supplier: 'MDK', variants: [{ key: 'PB-10K', price: 199_000, cost: 122_000, w: 3 }] },
    { name: 'Powerbank 20.000mAh', supplier: 'MDK', variants: [{ key: 'PB-20K', price: 289_000, cost: 182_000, w: 1.5 }] },
    { name: 'MicroSD 64GB', supplier: 'MDK', variants: [{ key: 'SD-64', price: 99_000, cost: 61_000, w: 2, addon: 0.05 }] },
    { name: 'MicroSD 128GB', supplier: 'MDK', variants: [{ key: 'SD-128', price: 159_000, cost: 101_000, w: 1.5 }] },
    { name: 'Flashdisk 32GB', supplier: 'MDK', variants: [{ key: 'FD-32', price: 69_000, cost: 39_000, w: 1.5 }] },
    { name: 'Kartu Perdana', supplier: 'MDK', variants: [{ key: 'SIM', price: 25_000, cost: 15_500, w: 5, addon: 0.1 }] },
];
// cost = harga modal, booked from the pulsa deposit.
const DIGITAL = [
    { name: 'Pulsa', variants: [
        { key: 'PLS-5', name: '5rb', price: 7_000, cost: 5_600, w: 4 },
        { key: 'PLS-10', name: '10rb', price: 12_000, cost: 10_300, w: 10 },
        { key: 'PLS-20', name: '20rb', price: 22_000, cost: 20_200, w: 7 },
        { key: 'PLS-25', name: '25rb', price: 27_000, cost: 25_100, w: 6 },
        { key: 'PLS-50', name: '50rb', price: 52_000, cost: 49_800, w: 6 },
        { key: 'PLS-100', name: '100rb', price: 101_000, cost: 98_700, w: 3 },
    ] },
    { name: 'Paket Data', variants: [
        { key: 'DATA-10', name: '10GB 30 hari', price: 55_000, cost: 49_500, w: 6 },
        { key: 'DATA-25', name: '25GB 30 hari', price: 95_000, cost: 87_000, w: 3 },
    ] },
    { name: 'Token Listrik', variants: [
        { key: 'PLN-20', name: '20rb', price: 23_500, cost: 20_600, w: 4 },
        { key: 'PLN-50', name: '50rb', price: 53_000, cost: 50_600, w: 5 },
        { key: 'PLN-100', name: '100rb', price: 103_000, cost: 100_600, w: 2 },
    ] },
];
// Repairs: the price is typed at the counter.
const SERVICES = [
    { name: 'Jasa Servis Ringan', key: 'SRV-RINGAN', price: 50_000, range: [35_000, 75_000], w: 5 },
    { name: 'Jasa Flash / Install Ulang', key: 'SRV-FLASH', price: 100_000, range: [75_000, 150_000], w: 3 },
    { name: 'Jasa Ganti Baterai', key: 'SRV-BATT', price: 175_000, range: [150_000, 250_000], w: 2 },
    { name: 'Jasa Ganti LCD', key: 'SRV-LCD', price: 450_000, range: [350_000, 950_000], w: 1.5 },
];
const DEVICES = ['Samsung A12', 'Samsung A05', 'Redmi 9A', 'Redmi 10C', 'Redmi Note 11', 'OPPO A5s', 'OPPO A16', 'vivo Y12', 'realme C11', 'Infinix Hot 30', 'iPhone 7', 'iPhone XR'];

const PRICE_CHANGES = [
    { day: '2026-01-15', h: 7, key: 'CHG-33', price: 125_000 },
    { day: '2026-04-01', h: 12, key: 'R14C-4128', price: 1_399_000, cost: 1_140_000 },
    { day: '2026-06-01', h: 7, key: 'KBL-C', price: 39_000, cost: 15_000 },
    { day: '2026-06-01', h: 7, key: 'KBL-L', price: 49_000, cost: 20_000 },
    { day: '2026-08-15', h: 7, key: 'A06-464', price: 1_449_000, cost: 1_180_000 },
    { day: '2026-08-15', h: 7, key: 'A06-4128', price: 1_649_000, cost: 1_345_000 },
];

const VOUCHERS = [
    { code: '1212HEMAT', description: 'Harbolnas 12.12: potongan Rp100.000 semua HP', target: 'phone', type: 'fixed', value: 100_000, from: '2025-12-10', to: '2025-12-14', use: 0.45 },
    { code: 'AKHIRTAHUN10', description: 'Diskon 10% aksesoris akhir tahun', target: 'acc', type: 'percent', value: 10, from: '2025-12-20', to: '2025-12-31', use: 0.35 },
    { code: 'RAMADAN26', description: 'Diskon 10% aksesoris selama Ramadan', target: 'acc', type: 'percent', value: 10, from: '2026-02-18', to: '2026-03-19', use: 0.3 },
    { code: 'LEBARAN150', description: 'Potongan Rp150.000 HP menjelang Lebaran', target: 'phone', type: 'fixed', value: 150_000, from: '2026-03-09', to: '2026-03-19', use: 0.5 },
    { code: 'MERDEKA17', description: 'HUT RI: diskon 17% aksesoris', target: 'acc', type: 'percent', value: 17, from: '2026-08-14', to: '2026-08-18', use: 0.4 },
    { code: '1111DEAL', description: '11.11: diskon 11% aksesoris', target: 'acc', type: 'percent', value: 11, from: '2026-11-11', to: '2026-11-11', use: 0.4 },
];

// BR03 loses its connection; the price change at 12:00 doesn't reach its tablet.
const OUTAGE = { code: 'BR03', day: '2026-04-01', from: [11, 30], to: [16, 30], upload: [16, 35] };
const SHORT_TRANSFER = { code: 'BR02', day: '2026-05-12' };
const MISSING_PHONE = { code: 'BR02', day: '2026-06-30' };

const FIRST_NAMES = ['Andi', 'Budi', 'Citra', 'Dewi', 'Eka', 'Fajar', 'Gita', 'Hendra', 'Indah', 'Joko', 'Kartika', 'Lukman', 'Maya', 'Nur',
    'Oki', 'Putri', 'Rizky', 'Sari', 'Taufik', 'Vina', 'Wahyu', 'Yusuf', 'Zahra', 'Ahmad', 'Ayu', 'Bayu', 'Dian', 'Fitri', 'Hasan', 'Ilham',
    'Lina', 'Mega', 'Nanda', 'Rahmat', 'Rina', 'Siti', 'Teguh', 'Wulan', 'Yani', 'Agus', 'Ani', 'Arif', 'Desi', 'Dimas', 'Fikri', 'Irfan',
    'Kurnia', 'Mira', 'Novi', 'Reza', 'Ratna', 'Sinta', 'Tono', 'Yogi', 'Andika', 'Anisa', 'Bagus', 'Fadli', 'Hilda', 'Iwan', 'Lestari',
    'Muhammad', 'Nurul', 'Puspita', 'Ridwan', 'Syahrul', 'Wawan', 'Yuli', 'Zulkifli', 'Asri', 'Akbar', 'Irma', 'Jumadi', 'Rosmini'];
const LAST_NAMES = ['Saputra', 'Wijaya', 'Santoso', 'Pratama', 'Hidayat', 'Nugroho', 'Kusuma', 'Rahman', 'Setiawan', 'Siregar', 'Hasibuan',
    'Daeng', 'Mappa', 'Syamsuddin', 'Rasyid', 'Halim', 'Gunawan', 'Wibowo', 'Putra', 'Utami', 'Ramadhan', 'Firmansyah', 'Kurniawan',
    'Hakim', 'Amir', 'Basri', 'Tahir', 'Latif', 'Salim', 'Anwar', 'Arsyad', 'Baso', 'Jufri', 'Nasir', 'Effendi', 'Paturusi', 'Mattalitti'];

// ── simulated clock ──────────────────────────────────────────────────────────

let simNow = RealDate.now();
class SimDate extends RealDate {
    constructor(...a) {
        if (a.length === 0) super(simNow);
        else super(...a);
    }
    static now() {
        return simNow;
    }
}
const setClock = (t) => {
    simNow = Math.max(t, simNow + 1);
};

// ── run state ────────────────────────────────────────────────────────────────

let pool;
let jwt;
let BASE_URL;
const USERS = {};
const LOC = {};
const PM = {}; // payment method id by type
const CAT = {}; // category id by key
const VARIANTS = []; // every sellable variant
const BY_KEY = {};
const SUPPLIER_ID = {};
const STOCK = {}; // location id -> { qty: Map(variantId -> qty), units: Map(variantId -> [unitId]) }
const SHIFT = {}; // branch code -> { id, user }
const FUTURE = new Map(); // day -> [ (day) => event ]
const CUSTOMERS = [];
const usedPhones = new Set();
const deferredPayments = new Map(); // receipt id -> day to pay the rest
const stats = {
    requests: 0, sales: 0, revenue: 0, lost: 0, returns: 0, voids: 0, receipts: 0, transfers: 0, expenses: 0, journals: 0,
    offline: 0, failures: 0, errors: new Map(),
};
const month = { sales: 0, revenue: 0, failures: 0 };
let EVENTS = [];

const recordError = (label, error) => {
    stats.failures += 1;
    month.failures += 1;
    const key = `${label}: ${String(error.message).replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, '…').slice(0, 220)}`;
    stats.errors.set(key, (stats.errors.get(key) || 0) + 1);
    if (process.env.DEMO_VERBOSE) console.error(`  ! ${new RealDate(simNow).toISOString()} ${key}`);
};

const api = async (user, method, url, body) => {
    const token = jwt.sign({ userId: USERS[user] }, process.env.JWT_SECRET, { expiresIn: '1d' });
    const res = await fetch(`${BASE_URL}/api${url}`, {
        method,
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    stats.requests += 1;
    const text = await res.text();
    let data = null;
    try {
        data = text ? JSON.parse(text) : null;
    } catch {
        data = { error: text.slice(0, 200) };
    }
    if (!res.ok) {
        const error = new Error(`${method} ${url.split('?')[0]} (${user}) ${res.status}: ${data?.error || text.slice(0, 200)}`);
        error.status = res.status;
        throw error;
    }
    return data;
};
const q = async (sql, params = []) => (await pool.execute(sql, params))[0];

const schedule = (t, label, fn) => EVENTS.push({ t, label, fn });
const later = (day, fn) => {
    if (day > TO) return;
    if (!FUTURE.has(day)) FUTURE.set(day, []);
    FUTURE.get(day).push(fn);
};

// ── catalog helpers ──────────────────────────────────────────────────────────

const sellableOn = (v, day) => !v.sellFrom || day >= v.sellFrom;
const weightAt = (v, day) => (v.later && day >= v.later.from ? v.later.w : v.w);
const ofCat = (cat, day) => VARIANTS.filter((v) => v.cat === cat && sellableOn(v, day));
const share = (v, day) => {
    const all = ofCat(v.cat, day);
    const total = all.reduce((s, x) => s + weightAt(x, day), 0);
    return total ? weightAt(v, day) / total : 0;
};
// Units a branch is expected to sell on a day (planning; the real day is random around it).
const expectedDemand = (branch, v, day) => {
    if (!sellableOn(v, day)) return 0;
    const p = typeProbs(day);
    const tx = BASE_TX * branch.weight * dayMult(day);
    if (v.cat === 'phone') return tx * p.phone * share(v, day);
    if (v.cat === 'acc') return tx * (p.acc * E_ACC_LINES * share(v, day) + p.phone * (v.addon || 0));
    return 0;
};
const demandOver = (branches, v, fromDay, days) => {
    let total = 0;
    for (let i = 0; i < days; i += 1) {
        const day = addDays(fromDay, i);
        for (const b of branches) total += expectedDemand(b, v, day);
    }
    return total;
};

const onHand = (locId, v) => (v.serialized ? (STOCK[locId].units.get(v.id) || []).length : STOCK[locId].qty.get(v.id) || 0);
const takeStock = (locId, v, qty, unitId) => {
    if (v.serialized) {
        const list = STOCK[locId].units.get(v.id) || [];
        STOCK[locId].units.set(v.id, list.filter((id) => id !== unitId));
    } else {
        STOCK[locId].qty.set(v.id, (STOCK[locId].qty.get(v.id) || 0) - qty);
    }
};
const putStock = (locId, v, qty, unitIds = []) => {
    if (v.serialized) STOCK[locId].units.set(v.id, [...(STOCK[locId].units.get(v.id) || []), ...unitIds]);
    else STOCK[locId].qty.set(v.id, (STOCK[locId].qty.get(v.id) || 0) + qty);
};
const reloadStock = async (locId) => {
    const qty = new Map();
    for (const r of await q('SELECT variant_id, qty FROM stock_levels WHERE location_id = ?', [locId])) qty.set(r.variant_id, Number(r.qty));
    const units = new Map();
    for (const r of await q("SELECT id, variant_id FROM product_units WHERE location_id = ? AND status = 'in_stock' ORDER BY created_at, id", [locId])) {
        if (!units.has(r.variant_id)) units.set(r.variant_id, []);
        units.get(r.variant_id).push(r.id);
    }
    STOCK[locId] = { qty, units };
};

let imeiSeq = 0;
const luhn = (digits) => {
    let sum = 0;
    for (let i = 0; i < digits.length; i += 1) {
        let x = Number(digits[i]);
        if (i % 2 === 1) {
            x *= 2;
            if (x > 9) x -= 9;
        }
        sum += x;
    }
    return String((10 - (sum % 10)) % 10);
};
const newUnit = (v, unitCost) => {
    const serial = 100000 + imeiSeq;
    imeiSeq += 2;
    const a = `${v.tac}${serial}`;
    const b = `${v.tac}${serial + 1}`;
    return { imei1: a + luhn(a), imei2: b + luhn(b), ...(unitCost !== undefined ? { unit_cost: unitCost } : {}) };
};
let barcodeSeq = 1;
const ean13 = () => {
    const d = `20${String(barcodeSeq++).padStart(10, '0')}`;
    let sum = 0;
    for (let i = 0; i < 12; i += 1) sum += Number(d[i]) * (i % 2 ? 3 : 1);
    return d + ((10 - (sum % 10)) % 10);
};

const newCustomer = () => {
    let phone;
    do phone = `0800${between(10_000_000, 99_999_999)}`; while (usedPhones.has(phone));
    usedPhones.add(phone);
    return { name: `${pick(FIRST_NAMES)} ${pick(LAST_NAMES)}`, phone };
};

// ── accounting helpers ───────────────────────────────────────────────────────

const balanceOf = async (code, locId, { to } = {}) => {
    const params = [code];
    let where = '';
    if (locId === null) where += ' AND jl.location_id IS NULL';
    else if (locId !== undefined) {
        where += ' AND jl.location_id = ?';
        params.push(locId);
    }
    if (to) {
        where += ' AND e.entry_date <= ?';
        params.push(to);
    }
    const [row] = await q(
        `SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS b FROM journal_lines jl
         JOIN accounts a ON a.id = jl.account_id JOIN journal_entries e ON e.id = jl.entry_id
         WHERE a.code = ?${where}`,
        params
    );
    return Math.round(Number(row.b));
};
const journal = async (user, locId, memo, lines) => {
    stats.journals += 1;
    return api(user, 'POST', '/accounting/journals', {
        location_id: locId,
        memo,
        lines: lines.filter((l) => (l.debit || 0) > 0 || (l.credit || 0) > 0),
    });
};
const expense = async (user, { location = null, code, amount, paidFrom = 'bank', payee, note }) => {
    stats.expenses += 1;
    return api(user, 'POST', '/expenses', { location_id: location, account_code: code, amount, paid_from: paidFrom, payee, note });
};
const step = async (label, fn) => {
    try {
        await fn();
    } catch (error) {
        recordError(label, error);
    }
};

// ── setup (first morning) ────────────────────────────────────────────────────

const setupCatalog = async () => {
    for (const [code, name] of [['3-1100', 'Prive Pemilik'], ['6-4000', 'Biaya Administrasi Bank & MDR'], ['6-5000', 'Beban Pemasaran'], ['6-6000', 'Perlengkapan Toko']]) {
        await api('akuntan', 'POST', '/accounting/accounts', { code, name, parent_code: `${code[0]}-0000` });
    }
    for (const [key, name, description] of [
        ['phone', 'Handphone', 'HP baru bergaransi resmi'],
        ['acc', 'Aksesoris', 'Aksesoris HP'],
        ['digital', 'Pulsa & Digital', 'Pulsa, paket data, token listrik'],
        ['service', 'Jasa Servis', 'Perbaikan dan perawatan HP'],
    ]) {
        CAT[key] = (await api('superadmin', 'POST', '/categories', { name, description })).categoryId;
    }
    const brandIds = {};
    for (const name of [...new Set(PHONES.map((p) => p.brand))]) {
        brandIds[name] = (await api('superadmin', 'POST', '/catalog/brands', { name })).brand.id;
    }
    for (const s of SUPPLIERS) {
        SUPPLIER_ID[s.key] = (await api('gudang', 'POST', '/purchasing/suppliers', {
            code: s.key, name: s.name, address: s.address, notes: `Tempo ${s.terms} hari`,
        })).supplier.id;
    }
};

const createProduct = async (def, cat) => {
    const phone = cat === 'phone';
    const body = {
        name: def.name,
        category_id: CAT[cat],
        kind: cat === 'digital' ? 'digital' : cat === 'service' ? 'service' : 'goods',
        ...(phone ? { brand_id: def.brandId, is_serialized: true, serial_type: 'imei_dual', warranty_months: 12 } : {}),
        variants: def.variants.map((v) => ({
            sku: v.key,
            ...(v.name ? { name: v.name } : {}),
            ...(phone ? { attributes: { ram: v.name.split('/')[0] + 'GB', storage: v.name.split('/')[1] }, min_price: v.price - 100_000 } : {}),
            ...(cat === 'acc' ? { barcode: ean13() } : {}),
            ...(cat === 'digital' ? { cost_price: v.cost } : {}),
            base_price: v.price,
        })),
    };
    const { product } = await api('superadmin', 'POST', '/catalog/products', body);
    const tac = `3588${pad(VARIANTS.length % 100)}${pad(product.id % 100)}`;
    for (const v of def.variants) {
        const created = product.variants.find((x) => x.sku === v.key);
        const variant = {
            ...v, id: created.id, cat, kind: body.kind, serialized: phone, supplier: def.supplier, product: def.name,
            label: v.name ? `${def.name} ${v.name}` : def.name, tac, sellFrom: def.launch ? addDays(def.launch, 1) : null,
        };
        VARIANTS.push(variant);
        BY_KEY[v.key] = variant;
    }
};

const openingDay = async () => {
    await setupCatalog();
    for (const p of PHONES) p.brandId = (await q('SELECT id FROM brands WHERE name = ?', [p.brand]))[0].id;
    for (const p of PHONES.filter((x) => !x.launch)) await createProduct(p, 'phone');
    for (const p of ACCESSORIES) await createProduct(p, 'acc');
    for (const p of DIGITAL) await createProduct(p, 'digital');
    for (const s of SERVICES) await createProduct({ name: s.name, variants: [{ key: s.key, price: s.price, w: s.w, range: s.range }] }, 'service');

    // Opening balances: the head office's bank, debt and capital; each branch's cash and pulsa deposit.
    setClock(at(FROM, 6, 40));
    await api('superadmin', 'POST', '/accounting/opening-balances', {
        date: FROM,
        memo: 'Saldo awal kantor pusat',
        lines: [
            { account_code: '1-1200', debit: 450_000_000 },
            { account_code: '2-1100', credit: 86_500_000 },
            { account_code: '3-1000', credit: 300_000_000 },
        ],
    });
    for (const b of BRANCHES) {
        await api('superadmin', 'POST', '/accounting/opening-balances', {
            date: FROM,
            location_id: LOC[b.code],
            memo: `Saldo awal ${b.code}`,
            lines: [{ account_code: '1-1100', debit: 3_000_000 }, { account_code: '1-1600', debit: 3_000_000 }],
        });
    }

    // Opening stock: about a week at each branch, the rest of the next weeks at the warehouse.
    setClock(at(FROM, 7, 0));
    for (const v of VARIANTS.filter((x) => x.cat === 'phone' || x.cat === 'acc')) {
        const perBranch = BRANCHES.map((b) => Math.ceil(demandOver([b], v, FROM, 5) * 1.3) + (v.cat === 'phone' ? 1 : 2));
        const horizon = v.cat === 'phone' ? 14 : 21;
        const total = Math.ceil(demandOver(BRANCHES, v, FROM, horizon) * 1.15) + (v.cat === 'phone' ? 5 : 17);
        const wh = Math.max(v.cat === 'phone' ? 4 : 10, total - perBranch.reduce((s, x) => s + x, 0));
        const places = [['WH', 'gudang', wh], ...BRANCHES.map((b, i) => [b.code, b.admin, perBranch[i]])];
        for (const [code, user, qty] of places) {
            if (qty <= 0) continue;
            if (v.serialized) {
                await api(user, 'POST', '/stock/units', {
                    location_id: LOC[code], variant_id: v.id, opening: true, note: 'Stok awal',
                    units: Array.from({ length: qty }, () => newUnit(v, v.cost)),
                });
            } else {
                await api(user, 'POST', '/stock/adjust', {
                    location_id: LOC[code], variant_id: v.id, qty_change: qty, unit_cost: v.cost, opening: true, note: 'Stok awal',
                });
            }
        }
    }
    for (const loc of Object.values(LOC)) await reloadStock(loc);
};

// ── the accountant's morning ─────────────────────────────────────────────────

const closePeriod = async (ym) => {
    await api('akuntan', 'POST', `/accounting/periods/${ym.slice(0, 4)}/${Number(ym.slice(5))}/close`);
};

// PPN for month `ym`: output tax of the month minus input tax still unclaimed, paid from the bank.
const settlePpn = async (ym) => {
    const end = lastDayOfMonth(`${ym}-01`);
    const [out] = await q(
        `SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS v FROM journal_lines jl
         JOIN accounts a ON a.id = jl.account_id JOIN journal_entries e ON e.id = jl.entry_id
         WHERE a.code = '2-1200' AND e.entry_date BETWEEN ? AND ? AND e.source_type <> 'manual'`,
        [`${ym}-01`, end]
    );
    const output = Math.round(Number(out.v));
    const input = Math.max(0, await balanceOf('1-1500', undefined, { to: end }));
    if (output <= 0) return;
    const name = monthName(ym);
    if (output > input) {
        await journal('akuntan', null, `Setor PPN masa ${name}`, [
            { account_code: '2-1200', debit: output, memo: `PPN keluaran ${name}` },
            { account_code: '1-1500', credit: input, memo: 'PPN masukan dikreditkan' },
            { account_code: '1-1200', credit: output - input, memo: 'Setoran ke kas negara' },
        ]);
    } else {
        await journal('akuntan', null, `Kompensasi PPN masa ${name} (lebih bayar dibawa ke masa berikutnya)`, [
            { account_code: '2-1200', debit: output },
            { account_code: '1-1500', credit: output },
        ]);
    }
};

const paySuppliers = async (day) => {
    const due = await q(
        `SELECT r.id, r.number, s.code AS supplier, r.grand_total - r.paid_total AS outstanding, r.paid_total,
                DATE_FORMAT(r.due_date, '%Y-%m-%d') AS due
         FROM goods_receipts r JOIN suppliers s ON s.id = r.supplier_id
         WHERE r.status = 'posted' AND r.grand_total > r.paid_total AND r.due_date <= ? ORDER BY r.due_date, r.number`,
        [day]
    );
    for (const r of due) {
        // A few invoices are paid a little late, a few in two parts.
        const delay = parseInt(r.id.replace(/-/g, '').slice(-4), 16) % 10 < 2 ? between(1, 4) : 0;
        if (addDays(r.due, delay) > day && !deferredPayments.has(r.id)) continue;
        if (deferredPayments.has(r.id) && deferredPayments.get(r.id) > day) continue;
        let amount = Math.round(Number(r.outstanding) * 100) / 100;
        if (Number(r.paid_total) === 0 && chance(0.1)) {
            amount = Math.round(amount / 2);
            deferredPayments.set(r.id, addDays(day, 7));
        }
        await step('supplier payment', () => api('akuntan', 'POST', '/purchasing/payments', {
            receipt_id: r.id, amount, method: 'transfer', reference: `TRF/${r.supplier}/${stamp(day)}`, note: `Pembayaran ${r.number}`,
        }));
    }
};

const accountantMorning = async (day) => {
    const d = dayNum(day);
    const ym = monthOf(day);
    const lastYm = prevMonth(ym);
    if (d === 8 && lastYm >= monthOf(FROM)) await step('close period', () => closePeriod(lastYm));
    if (d === 20 && lastYm >= monthOf(FROM)) await step('PPN', () => settlePpn(lastYm));
    await paySuppliers(day);

    if (day === addDays(FROM, 13)) {
        await step('opening AP', () => journal('akuntan', null, `Pelunasan hutang supplier per ${addDays(FROM, -1)} (sebelum memakai sistem)`, [
            { account_code: '2-1100', debit: 86_500_000 }, { account_code: '1-1200', credit: 86_500_000 },
        ]));
    }
    const places = [...BRANCHES.map((b) => ({ code: b.code, branch: b })), { code: 'WH' }];
    if (d === 1) {
        for (const p of places) {
            const amount = p.branch ? p.branch.rent : 3_000_000;
            await step('rent', () => expense('akuntan', { location: LOC[p.code], code: '6-1000', amount, payee: `Pemilik ruko ${p.code}`, note: `Sewa ${monthName(ym)}` }));
        }
    }
    if (d === 3) await step('ads', () => expense('akuntan', { code: '6-5000', amount: 1_500_000, payee: 'Iklan media sosial', note: monthName(ym) }));
    places.forEach((p, i) => {
        if (d !== 5 + i) return;
        const hot = ['10', '11', '12'].includes(day.slice(5, 7));
        const elec = p.branch ? roundTo(between(...p.branch.elec) * (hot ? 1.1 : 1), 1000) : roundTo(between(600_000, 800_000), 1000);
        EVENTS.push({ t: at(day, 6, 10 + i), label: 'utilities', fn: async () => {
            if (day === '2026-02-10' && p.code === 'BR02') {
                // Typed one zero too many, voided, entered again.
                const wrong = await expense('akuntan', { location: LOC[p.code], code: '6-3000', amount: elec * 10, payee: 'PLN', note: `Listrik ${monthName(lastYm)}` });
                await api('akuntan', 'POST', `/expenses/${wrong.expense.id}/void`, { reason: 'Salah ketik nominal' });
            }
            await expense('akuntan', { location: LOC[p.code], code: '6-3000', amount: elec, payee: 'PLN', note: `Listrik ${monthName(lastYm)}` });
            if (p.branch) await expense('akuntan', { location: LOC[p.code], code: '6-3000', amount: roundTo(between(110_000, 190_000), 500), payee: 'PDAM', note: `Air ${monthName(lastYm)}` });
            await expense('akuntan', { location: LOC[p.code], code: '6-3000', amount: 385_000, payee: 'Internet', note: `Internet ${monthName(ym)}` });
        } });
    });
    if (d === 25) {
        const payroll = [...BRANCHES.map((b) => [LOC[b.code], 8_400_000, b.code]), [LOC.WH, 3_800_000, 'WH'], [null, 5_500_000, 'kantor pusat']];
        for (const [location, amount, who] of payroll) {
            await step('salary', () => expense('akuntan', { location, code: '6-2000', amount, payee: `Karyawan ${who}`, note: `Gaji ${monthName(ym)}` }));
        }
    }
    if (day === '2026-03-10') {
        const thr = [...BRANCHES.map((b) => [LOC[b.code], 8_400_000, b.code]), [LOC.WH, 3_800_000, 'WH'], [null, 5_500_000, 'kantor pusat']];
        for (const [location, amount, who] of thr) {
            await step('THR', () => expense('akuntan', { location, code: '6-2000', amount, payee: `Karyawan ${who}`, note: 'THR Idul Fitri 1447 H' }));
        }
    }
    if (day === '2026-08-20') await step('PBB', () => expense('akuntan', { location: LOC.WH, code: '6-1100', amount: 2_350_000, payee: 'Bapenda Kota Makassar', note: 'PBB 2026 gudang' }));
    if (day === '2026-05-18') await step('repair', () => expense('akuntan', { location: LOC.BR01, code: '6-9000', amount: 450_000, payee: 'Teknisi AC', note: 'Servis AC toko' }));
    if (d === 28) {
        await step('owner drawing', () => journal('superadmin', null, `Pengambilan pribadi pemilik ${monthName(ym)}`, [
            { account_code: '3-1100', debit: 30_000_000 }, { account_code: '1-1200', credit: 30_000_000 },
        ]));
    }
    if (day === lastDayOfMonth(day)) await step('bank fee', () => expense('akuntan', { code: '6-4000', amount: 25_000, payee: 'Bank', note: `Biaya administrasi rekening ${monthName(ym)}` }));
    if (dow(day) === 1) {
        await step('capital', async () => {
            if ((await balanceOf('1-1200')) < 100_000_000) {
                await journal('superadmin', null, 'Setoran modal pemilik', [
                    { account_code: '1-1200', debit: 150_000_000 }, { account_code: '3-1000', credit: 150_000_000 },
                ]);
            }
        });
    }
};

// Branch cash to the bank, QRIS / EDC settlements (minus MDR), twice a week.
const depositsAndSettlements = async () => {
    for (const b of BRANCHES) {
        const loc = LOC[b.code];
        await step('cash deposit', async () => {
            const kas = await balanceOf('1-1100', loc);
            const deposit = Math.floor((kas - 2_500_000) / 100_000) * 100_000;
            if (deposit > 0) {
                await journal('akuntan', loc, `Setoran tunai ${b.code} ke bank`, [{ account_code: '1-1200', debit: deposit }, { account_code: '1-1100', credit: deposit }]);
            }
        });
        await step('settlement', async () => {
            const qris = await balanceOf('1-1300', loc);
            const card = await balanceOf('1-1310', loc);
            if (qris + card <= 0) return;
            const fee = Math.round(Math.max(0, qris) * 0.007) + Math.round(Math.max(0, card) * 0.015);
            await journal('akuntan', loc, `Pencairan QRIS / e-wallet & EDC ${b.code}`, [
                { account_code: '1-1200', debit: qris + card - fee },
                { account_code: '6-4000', debit: fee, memo: 'MDR QRIS 0,7% / EDC 1,5%' },
                { account_code: '1-1300', credit: qris },
                { account_code: '1-1310', credit: card },
            ]);
        });
    }
};

// ── the warehouse ────────────────────────────────────────────────────────────

const totalOnHand = (v) => [LOC.WH, ...BRANCHES.map((b) => LOC[b.code])].reduce((s, loc) => s + onHand(loc, v), 0);

const warehouseReceipts = async (day) => {
    const phones = dow(day) === 1;
    const accessories = dayNum(day) === 1 || dayNum(day) === 16;
    if (!phones && !accessories) return;
    const orders = new Map();
    for (const v of VARIANTS) {
        if (!((phones && v.cat === 'phone') || (accessories && v.cat === 'acc'))) continue;
        if (v.sellFrom && addDays(day, 14) < v.sellFrom) continue;
        const horizon = v.cat === 'phone' ? 14 : 21;
        const target = Math.ceil(demandOver(BRANCHES, v, addDays(day, 1), horizon) * (v.cat === 'phone' ? 1.1 : 1.2)) + (v.cat === 'phone' ? 5 : 17);
        let need = target - totalOnHand(v);
        if (need <= 0) continue;
        const packSize = v.cat === 'phone' ? 2 : v.price < 50_000 ? 10 : v.price < 150_000 ? 5 : 2;
        need = Math.ceil(need / packSize) * packSize;
        if (!orders.has(v.supplier)) orders.set(v.supplier, []);
        orders.get(v.supplier).push({ v, qty: need });
    }
    for (const [supplier, items] of orders) {
        const terms = SUPPLIERS.find((s) => s.key === supplier).terms;
        // Sometimes the goods came in yesterday and are entered this morning.
        const received = dayNum(day) !== 1 && chance(0.15) && addDays(day, -1) >= FROM ? addDays(day, -1) : day;
        await step('goods receipt', async () => {
            const { receipt } = await api('gudang', 'POST', '/purchasing/receipts', {
                location_id: LOC.WH,
                supplier_id: SUPPLIER_ID[supplier],
                received_date: received,
                invoice_no: `INV/${supplier}/${stamp(received)}/${between(100, 999)}`,
                invoice_date: received,
                due_date: addDays(received, terms),
                items: items.map(({ v, qty }) => ({
                    variant_id: v.id,
                    qty,
                    unit_cost: v.serialized ? v.cost : roundTo(v.cost * (0.97 + rand() * 0.06), 50),
                    tax_rate: 11,
                    ...(v.serialized ? { units: Array.from({ length: qty }, () => newUnit(v)) } : {}),
                })),
            });
            await api('gudang', 'POST', `/purchasing/receipts/${receipt.id}/post`);
            stats.receipts += 1;
        });
    }
    await reloadStock(LOC.WH);
};

const sendTransfer = async (user, fromLoc, toLoc, items, note) => {
    const { transfer } = await api(user, 'POST', '/transfers', {
        from_location_id: fromLoc,
        to_location_id: toLoc,
        note,
        items: items.map(({ v, qty, unitIds }) => (v.serialized ? { variant_id: v.id, unit_ids: unitIds } : { variant_id: v.id, qty })),
    });
    await api(user, 'POST', `/transfers/${transfer.id}/send`, {});
    for (const { v, qty, unitIds } of items) {
        if (v.serialized) for (const id of unitIds) takeStock(fromLoc, v, 1, id);
        else takeStock(fromLoc, v, qty);
    }
    stats.transfers += 1;
    return transfer;
};

const receiveTransfer = async (user, transfer, items, body = {}) => {
    await api(user, 'POST', `/transfers/${transfer.id}/receive`, body);
    const short = new Map((body.items || []).map((i) => [i.item_id, i.qty_received]));
    for (const { v, qty, unitIds } of items) {
        const item = transfer.items.find((i) => i.variant_id === v.id);
        if (v.serialized) putStock(transfer.to_location_id, v, 0, unitIds);
        else putStock(transfer.to_location_id, v, short.has(item?.id) ? short.get(item.id) : qty);
    }
};

const warehouseTransfers = async (day) => {
    if (![2, 5].includes(dow(day))) return;
    const untilNext = dow(day) === 2 ? 3 : 4;
    for (const b of BRANCHES) {
        if (CLOSED.has(day)) continue;
        const loc = LOC[b.code];
        const items = [];
        for (const v of VARIANTS) {
            if (!(v.cat === 'phone' || v.cat === 'acc')) continue;
            if (v.sellFrom && v.sellFrom > addDays(day, 1)) continue;
            const target = Math.ceil(demandOver([b], v, day, untilNext + 1) * 1.3) + (v.cat === 'phone' ? 1 : 2);
            const need = target - onHand(loc, v);
            if (need <= 0) continue;
            if (v.cat === 'acc' && need < Math.max(2, Math.ceil(target * 0.3)) && onHand(loc, v) > 2) continue;
            const qty = Math.min(need, onHand(LOC.WH, v));
            if (qty <= 0) continue;
            items.push(v.serialized ? { v, qty, unitIds: STOCK[LOC.WH].units.get(v.id).slice(0, qty) } : { v, qty });
        }
        if (items.length === 0) continue;
        await step('transfer', async () => {
            const transfer = await sendTransfer('gudang', LOC.WH, loc, items, `Kirim stok rutin ke ${b.code}`);
            const short = SHORT_TRANSFER.day === day && SHORT_TRANSFER.code === b.code;
            schedule(at(day, between(11, 13), between(0, 59)), 'receive transfer', async () => {
                const full = (await api(b.admin, 'GET', `/transfers/${transfer.id}`)).transfer;
                const first = full.items.find((i) => !i.is_serialized && i.qty_sent > 1);
                if (short && first) {
                    await receiveTransfer(b.admin, full, items, {
                        items: [{ item_id: first.id, qty_received: first.qty_sent - 1 }], note: `1 pcs ${first.name} tidak ada di koli`,
                    });
                    later(addDays(day, 1), (d) => schedule(at(d, 8, 15), 'resolve transfer', () => api('gudang', 'POST', `/transfers/${transfer.id}/resolve`, {
                        action: 'write_off', note: 'Hilang dalam pengiriman, ditanggung toko',
                    })));
                } else {
                    await receiveTransfer(b.admin, full, items);
                }
            });
        });
    }
};

// A branch out of a phone gets one from a branch that has several (1st and 15th).
const branchTransfers = async (day) => {
    if (![1, 15].includes(dayNum(day)) || CLOSED.has(day)) return;
    let done = 0;
    for (const v of ofCat('phone', day)) {
        if (done >= 2) break;
        const empty = BRANCHES.find((b) => onHand(LOC[b.code], v) === 0);
        const full = BRANCHES.find((b) => onHand(LOC[b.code], v) >= 3);
        if (!empty || !full) continue;
        done += 1;
        const unitIds = STOCK[LOC[full.code]].units.get(v.id).slice(0, 1);
        await step('branch transfer', async () => {
            const transfer = await sendTransfer(full.admin, LOC[full.code], LOC[empty.code], [{ v, qty: 1, unitIds }], `Permintaan ${empty.code}: ${v.label}`);
            schedule(at(day, between(15, 16), between(0, 59)), 'receive branch transfer', async () => {
                const t = (await api(empty.admin, 'GET', `/transfers/${transfer.id}`)).transfer;
                await receiveTransfer(empty.admin, t, [{ v, qty: 1, unitIds }]);
            });
        });
    }
};

// ── the branches ─────────────────────────────────────────────────────────────

const shiftUser = (b, day) => (dow(day) === b.dayOff ? b.admin : b.kasir);

const openShift = async (b, day) => {
    const user = shiftUser(b, day);
    try {
        const { session } = await api(user, 'POST', '/cash-sessions', { location_id: LOC[b.code], opening_cash: 500_000 });
        SHIFT[b.code] = { id: session.id, user };
    } catch (error) {
        if (error.status !== 409) throw error;
        const { session } = await api(user, 'GET', `/cash-sessions/current?location_id=${LOC[b.code]}`);
        SHIFT[b.code] = { id: session.id, user };
        throw error; // still reported: a shift was left open
    }
};

const CASH_DIFFS = [[-50_000, 1], [-20_000, 2], [-10_000, 3], [-5_000, 4], [-2_000, 4], [1_000, 2], [5_000, 2], [10_000, 1]];
const closeShift = async (b) => {
    const s = SHIFT[b.code];
    if (!s) return;
    const { session } = await api(s.user, 'GET', `/cash-sessions/${s.id}`);
    const expected = Number(session.summary.expected_cash);
    const diff = chance(0.92) ? 0 : weighted(CASH_DIFFS, (x) => x[1])[0];
    await api(s.user, 'POST', `/cash-sessions/${s.id}/close`, {
        counted_cash: Math.max(0, expected + diff),
        note: diff < 0 ? 'Kas kurang, sudah dihitung ulang' : diff > 0 ? 'Kas lebih' : null,
    });
    SHIFT[b.code] = null;
};

const activeVouchers = (day) => VOUCHERS.filter((v) => day >= v.from && day <= v.to);

const tender = (amount) => {
    if (chance(0.3)) return amount;
    const options = [...new Set([5_000, 10_000, 20_000, 50_000, 100_000].map((n) => Math.ceil(amount / n) * n))].filter((x) => x - amount < 100_000);
    return options.length ? pick(options) : amount;
};
const reference = (type) => {
    if (type === 'ewallet') return `${pick(['DANA', 'OVO', 'GOPAY', 'SHOPEEPAY'])}-${between(10_000_000, 99_999_999)}`;
    if (type === 'card') return `EDC-${between(100_000, 999_999)}`;
    return `TRF-${between(10_000_000, 99_999_999)}`;
};
const PAYMENT_MIX = {
    phone: [['cash', 32], ['qris', 20], ['card', 30], ['transfer', 15], ['ewallet', 3]],
    acc: [['cash', 58], ['qris', 36], ['ewallet', 6]],
    digital: [['cash', 72], ['qris', 28]],
    service: [['cash', 60], ['qris', 35], ['transfer', 5]],
};

// Builds what one customer buys at branch b. Returns null when nothing they want is in stock.
const buildCart = (b, day, type, { prices = null, preferKey = null, force = false } = {}) => {
    const loc = LOC[b.code];
    const lines = [];
    const inStock = (v, qty = 1) => onHand(loc, v) - lines.filter((l) => l.v === v).reduce((s, l) => s + l.qty, 0) >= qty;
    const priceOf = (v) => (prices ? prices[v.key] : v.price);
    const add = (v, qty = 1, extra = {}) => {
        const line = { v, qty, unitPrice: priceOf(v), ...extra };
        if (v.serialized) {
            const used = new Set(lines.filter((l) => l.unitId).map((l) => l.unitId));
            line.unitId = STOCK[loc].units.get(v.id).find((id) => !used.has(id));
        }
        lines.push(line);
    };
    if (type === 'phone') {
        const phones = ofCat('phone', day);
        let v = preferKey && (force || chance(0.5)) ? BY_KEY[preferKey] : weighted(phones, (x) => weightAt(x, day));
        if (!inStock(v)) {
            const others = phones.filter((x) => inStock(x));
            if (others.length === 0 || chance(0.3)) return null;
            v = weighted(others, (x) => weightAt(x, day));
        }
        add(v);
        if (chance(0.55)) {
            const glass = BY_KEY[chance(0.2) ? 'TG-SPY' : 'TG-STD'];
            if (inStock(glass)) add(glass);
        }
        if (chance(0.45)) {
            const casing = BY_KEY[chance(0.5) ? 'CS-HTM' : 'CS-BNG'];
            if (inStock(casing)) add(casing);
        }
        if (chance(0.1) && inStock(BY_KEY.SIM)) add(BY_KEY.SIM);
        if (chance(0.05) && inStock(BY_KEY['SD-64'])) add(BY_KEY['SD-64']);
    } else if (type === 'acc') {
        const count = weighted(ACC_LINES, (x) => x[1])[0];
        let candidates = ofCat('acc', day);
        for (let i = 0; i < count && candidates.length; i += 1) {
            let v = weighted(candidates, (x) => weightAt(x, day));
            candidates = candidates.filter((x) => x !== v);
            const qty = v.price < 60_000 && chance(0.1) ? 2 : 1;
            if (!inStock(v, qty)) {
                const sibling = ofCat('acc', day).find((x) => x.product === v.product && x !== v && inStock(x, qty));
                if (!sibling) continue;
                v = sibling;
            }
            add(v, qty);
        }
    } else if (type === 'digital') {
        const digital = ofCat('digital', day);
        add(weighted(digital, (x) => weightAt(x, day)));
        if (chance(0.1)) add(weighted(digital.filter((x) => x.product === 'Paket Data'), (x) => weightAt(x, day)));
    } else {
        const v = weighted(ofCat('service', day), (x) => weightAt(x, day));
        add(v, 1, { unitPrice: roundTo(between(...v.range), 5_000), description: pick(DEVICES) });
    }
    return lines.length ? lines : null;
};

const doSale = async (b, day, { offlineQueue = null, prices = null, forceType = null } = {}) => {
    const shift = SHIFT[b.code];
    if (!shift) return;
    const loc = LOC[b.code];
    const p = typeProbs(day);
    const type = forceType || weighted(Object.keys(p), (k) => p[k]);
    const lines = buildCart(b, day, type, { prices, preferKey: offlineQueue ? 'R14C-4128' : null, force: !!forceType });
    if (!lines) {
        stats.lost += 1;
        return;
    }

    // Customer: required for phones, often given for repairs, sometimes by members.
    let customer = null;
    const wants = type === 'phone' ? 1 : type === 'service' ? 0.4 : 0.04;
    if (chance(wants)) {
        const returning = CUSTOMERS.length > 20 && chance(type === 'phone' ? 0.15 : 0.5);
        customer = returning ? pick(CUSTOMERS) : newCustomer();
    }

    // Discounts: promo vouchers; the branch manager sometimes gives a little off a phone.
    const cents = (n) => Math.round(n * 100);
    const gross = lines.reduce((s, l) => s + cents(l.unitPrice * l.qty), 0);
    let voucher = null;
    let voucherCents = 0;
    if (!offlineQueue) {
        for (const v of activeVouchers(day)) {
            const eligible = lines.filter((l) => l.v.cat === v.target).reduce((s, l) => s + cents(l.unitPrice * l.qty), 0);
            if (eligible > 0 && chance(v.use)) {
                voucher = v;
                voucherCents = v.type === 'percent' ? Math.round(eligible * v.value / 100) : Math.min(cents(v.value), eligible);
                break;
            }
        }
    }
    const manual = !offlineQueue && shift.user === b.admin && type === 'phone' && chance(0.25) ? pick([25_000, 50_000]) : 0;
    const manualCents = Math.min(cents(manual), gross - voucherCents);
    const total = (gross - voucherCents - manualCents) / 100;

    // Payment
    const method = offlineQueue ? 'cash' : weighted(PAYMENT_MIX[type], (x) => x[1])[0];
    let payments;
    if (type === 'phone' && method === 'card' && chance(0.2) && total > 1_000_000) {
        const cash = pick([500_000, 1_000_000]);
        payments = [{ payment_method_id: PM.cash, amount: cash }, { payment_method_id: PM.card, amount: Math.round((total - cash) * 100) / 100, reference: reference('card') }];
    } else if (method === 'cash') {
        payments = [{ payment_method_id: PM.cash, amount: tender(total) }];
    } else {
        payments = [{ payment_method_id: PM[method], amount: total, ...(['ewallet', 'card', 'transfer'].includes(method) ? { reference: reference(method) } : {}) }];
    }

    const body = {
        id: crypto.randomUUID(),
        location_id: loc,
        cash_session_id: shift.id,
        occurred_at: new RealDate(simNow).toISOString(),
        lines: lines.map((l) => {
            if (l.v.serialized) return { variant_id: l.v.id, unit_ids: [l.unitId], ...(offlineQueue ? { unit_price: l.unitPrice } : {}) };
            if (l.v.cat === 'service') return { variant_id: l.v.id, qty: 1, unit_price: l.unitPrice, description: l.description };
            return { variant_id: l.v.id, qty: l.qty, ...(offlineQueue ? { unit_price: l.unitPrice } : {}) };
        }),
        payments,
        ...(voucher ? { voucher_code: voucher.code } : {}),
        ...(manualCents ? { discount: manualCents / 100 } : {}),
        ...(customer ? (customer.id ? { customer_id: customer.id } : { customer: { name: customer.name, phone: customer.phone } }) : {}),
    };

    if (offlineQueue) {
        // The tablet sold it; the server hears about it when the connection is back.
        Object.assign(body, { offline: true, priced_on_device: true, charged_total: total });
        for (const l of lines) takeStock(loc, l.v, l.qty, l.unitId);
        offlineQueue.push({ body, user: shift.user, lines, type, customer });
        return;
    }
    await postSale(b, day, { body, user: shift.user, lines, type, customer }, false);
};

const postSale = async (b, day, { body, user, lines, type, customer }, wasOffline) => {
    const loc = LOC[b.code];
    let sale;
    try {
        sale = (await api(user, 'POST', '/sales', body)).sale;
    } catch (error) {
        recordError(`sale ${type}${wasOffline ? ' (offline)' : ''}`, error);
        if (error.status === 409 || error.status === 400) await reloadStock(loc);
        return;
    }
    if (!wasOffline) for (const l of lines) takeStock(loc, l.v, l.qty, l.unitId);
    stats.sales += 1;
    month.sales += 1;
    stats.revenue += Number(sale.grand_total);
    month.revenue += Number(sale.grand_total);
    if (wasOffline) stats.offline += 1;
    if (customer && !customer.id && sale.customer_id) {
        customer.id = sale.customer_id;
        CUSTOMERS.push(customer);
    }

    // A few come back: a broken cable, a phone dead on arrival, pulsa that never arrived.
    const paidCash = body.payments.some((p) => p.payment_method_id === PM.cash);
    const saleLine = (pred) => sale.lines.find((l) => pred(lines.find((x) => x.v.id === l.variant_id)));
    if (type === 'acc' && chance(0.012)) {
        const line = sale.lines[0];
        const restock = chance(0.5);
        scheduleReturn(b, day, between(0, 6), sale, line, restock, restock ? pick(['Tidak cocok dengan HP', 'Salah beli tipe']) : 'Barang cacat', paidCash);
    } else if (type === 'phone' && chance(0.004)) {
        const line = saleLine((x) => x && x.v.serialized);
        if (line) scheduleReturn(b, day, between(0, 3), sale, line, false, 'HP mati total / cacat pabrik (DOA)', paidCash);
    } else if (type === 'digital' && chance(0.004)) {
        scheduleReturn(b, day, 0, sale, sale.lines[0], true, 'Pulsa gagal masuk', paidCash);
    } else if (type !== 'phone' && !wasOffline && chance(0.0025)) {
        // Rung up wrongly and cancelled a few minutes later.
        schedule(simNow + between(2, 15) * 60_000, 'void', async () => {
            await api(b.admin, 'POST', `/sales/${sale.id}/void`, { reason: 'Salah input barang' });
            stats.voids += 1;
            await reloadStock(loc);
        });
    }
};

// Cash back only from a drawer that holds enough; otherwise the refund goes by bank transfer.
const drawerCovers = async (b, shift, amount) => {
    const { session } = await api(shift.user, 'GET', `/cash-sessions/${shift.id}`);
    return Number(session.summary.expected_cash) >= amount + 50_000;
};

const scheduleReturn = (b, day, afterDays, sale, line, restock, reason, paidCash) => {
    const refund = Number(line.line_total) / Number(line.qty);
    const run = (d) => {
        if (CLOSED.has(d)) return later(addDays(d, 1), run);
        schedule(at(d, between(10, 19), between(0, 59)), 'return', async () => {
            const shift = SHIFT[b.code];
            if (!shift) return later(addDays(d, 1), run);
            const cash = (paidCash || chance(0.5)) && (await drawerCovers(b, shift, refund));
            await api(b.admin, 'POST', `/sales/${sale.id}/returns`, {
                lines: [{ sale_line_id: line.id, qty: 1, restock }],
                refund_method_id: cash ? PM.cash : PM.transfer,
                ...(cash ? { cash_session_id: shift.id } : {}),
                reason,
            });
            stats.returns += 1;
            if (restock && line.line_type === 'goods') await reloadStock(LOC[b.code]);
        });
    };
    if (afterDays === 0) {
        // Same day: a little later.
        schedule(simNow + between(20, 120) * 60_000, 'return', async () => {
            const shift = SHIFT[b.code];
            if (!shift) return later(addDays(day, 1), run);
            const cash = await drawerCovers(b, shift, refund);
            await api(b.admin, 'POST', `/sales/${sale.id}/returns`, {
                lines: [{ sale_line_id: line.id, qty: 1, restock }],
                refund_method_id: cash ? PM.cash : PM.transfer,
                ...(cash ? { cash_session_id: shift.id } : {}),
                reason,
            });
            stats.returns += 1;
        });
    } else {
        later(addDays(day, afterDays), run);
    }
};

const pulsaTopUps = async () => {
    for (const b of BRANCHES) {
        await step('pulsa top-up', async () => {
            const balance = await balanceOf('1-1600', LOC[b.code]);
            if (balance < 1_500_000) {
                await api(b.admin, 'POST', '/pulsa-deposit/top-ups', {
                    location_id: LOC[b.code], amount: 5_000_000, paid_from: 'bank', note: 'Transfer ke server pulsa',
                });
            }
        });
    }
};

const eveningTasks = async (day) => {
    const d = dayNum(day);
    for (const b of BRANCHES) {
        const loc = LOC[b.code];
        if ((d === 2 || d === 16) && !CLOSED.has(day)) {
            await step('supplies', () => expense(b.admin, {
                location: loc, code: '6-6000', amount: roundTo(between(150_000, 400_000), 5_000), paidFrom: 'cash',
                payee: 'Toko grosir', note: 'Kantong plastik, kertas struk, alat tulis',
            }));
        }
        if (d === 10) {
            await step('security fee', () => expense(b.admin, { location: loc, code: '6-9000', amount: 100_000, paidFrom: 'cash', payee: 'Pengelola ruko', note: `Iuran keamanan & kebersihan ${monthName(monthOf(day))}` }));
        }
        if (['12-08', '02-15', '08-10'].includes(day.slice(5))) {
            await step('banner', () => expense(b.admin, { location: loc, code: '6-5000', amount: 350_000, paidFrom: 'cash', payee: 'Percetakan', note: 'Spanduk promo' }));
        }
        if (chance(1 / 25)) {
            const damaged = ofCat('acc', day).filter((v) => onHand(loc, v) > 2);
            if (damaged.length) {
                const v = pick(damaged);
                await step('write-off', async () => {
                    await api(b.admin, 'POST', '/stock/adjust', { location_id: loc, variant_id: v.id, qty_change: -1, note: 'Rusak / cacat, tidak bisa dijual' });
                    takeStock(loc, v, 1);
                });
            }
        }
    }
    if (QUARTER_ENDS.has(day)) {
        for (const [code, user] of [...BRANCHES.map((b) => [b.code, b.admin]), ['WH', 'gudang']]) {
            await step('stock count', () => stockCount(day, code, user));
        }
    }
};

// Quarter-end count: a little shrinkage on cheap items, every IMEI scanned.
const stockCount = async (day, code, user) => {
    const loc = LOC[code];
    const { opname } = await api(user, 'POST', '/opnames', { location_id: loc, note: `Stok opname akhir kuartal ${day}` });
    const counts = opname.items.filter((i) => !i.is_serialized).map((i) => {
        let counted = Number(i.system_qty);
        if (counted > 0 && chance(0.06)) counted -= chance(0.8) ? 1 : 2;
        else if (chance(0.015)) counted += 1;
        return { variant_id: i.variant_id, counted_qty: Math.max(0, counted), ...(counted !== Number(i.system_qty) ? { note: 'Selisih hitung' } : {}) };
    });
    if (counts.length) await api(user, 'PUT', `/opnames/${opname.id}/counts`, { counts });
    const missing = MISSING_PHONE.day === day && MISSING_PHONE.code === code;
    let skipped = false;
    for (const item of opname.items.filter((i) => i.is_serialized)) {
        for (const unit of item.units) {
            if (missing && !skipped) {
                skipped = true;
                continue;
            }
            await api(user, 'POST', `/opnames/${opname.id}/scan`, { identifier: unit.imei1 });
        }
    }
    await api(user, 'POST', `/opnames/${opname.id}/approve`, {});
    await reloadStock(loc);
};

// ── one day ──────────────────────────────────────────────────────────────────

const branchDay = (b, day) => {
    const loc = LOC[b.code];
    schedule(at(day, 9, between(0, 9)), 'open shift', () => openShift(b, day));
    const n = Math.round(BASE_TX * b.weight * dayMult(day) * (0.8 + rand() * 0.4));
    const outage = OUTAGE.day === day && OUTAGE.code === b.code ? OUTAGE : null;
    let queue = null;
    let devicePrices = null;
    if (outage) {
        queue = [];
        schedule(at(day, ...outage.from), 'outage starts', () => {
            devicePrices = Object.fromEntries(VARIANTS.map((v) => [v.key, v.price]));
        });
        // Two buyers of the phone whose price dropped at 12:00: the tablet still charges the old price.
        for (const [h, m] of [[12, 40], [15, 10]]) {
            schedule(at(day, h, m), 'sale', () => doSale(b, day, { offlineQueue: queue, prices: devicePrices, forceType: 'phone' }));
        }
        schedule(at(day, ...outage.upload), 'offline upload', async () => {
            for (const entry of queue) {
                setClock(simNow + 2_000);
                await postSale(b, day, entry, true);
            }
            queue = null;
        });
    }
    const HOURS = [[9, 0.5], [10, 0.8], [11, 1.0], [12, 1.1], [13, 1.0], [14, 0.8], [15, 0.8], [16, 0.9], [17, 1.0], [18, 1.25], [19, 1.3], [20, 0.9]];
    for (let i = 0; i < n; i += 1) {
        const hour = weighted(HOURS, (x) => x[1])[0];
        const minute = hour === 9 ? between(15, 59) : hour === 20 ? between(0, 55) : between(0, 59);
        const t = at(day, hour, minute, between(0, 59));
        const offline = outage && t >= at(day, ...outage.from, 0) && t < at(day, ...outage.to, 0);
        schedule(t, 'sale', () => doSale(b, day, offline ? { offlineQueue: queue, prices: devicePrices } : {}));
    }
    schedule(at(day, 21, between(0, 14)), 'close shift', () => closeShift(b));
    return loc;
};

const runDay = async (day) => {
    EVENTS = [];
    const cutoff = day === REAL_TODAY ? RealDate.now() - 60_000 : Infinity;
    for (const loc of Object.values(LOC)) await reloadStock(loc);

    if (day === FROM) schedule(at(day, 6, 0), 'opening day', openingDay);
    schedule(at(day, 6, 5), 'accountant', () => accountantMorning(day));
    for (const v of VOUCHERS) {
        if (addDays(v.from, -2) === day || (day === FROM && v.from > day && addDays(v.from, -2) < day)) {
            schedule(at(day, 7, 30), 'voucher', () => api('superadmin', 'POST', '/vouchers', {
                code: v.code, description: v.description, target_type: 'categories', target_id: CAT[v.target],
                discount_type: v.type, discount_value: v.value, valid_from: v.from, valid_to: v.to,
            }));
        }
    }
    for (const p of PHONES.filter((x) => x.launch === day)) schedule(at(day, 7, 0), 'launch', () => createProduct(p, 'phone'));
    for (const c of PRICE_CHANGES.filter((x) => x.day === day)) {
        schedule(at(day, c.h, 0), 'price change', async () => {
            const v = BY_KEY[c.key];
            await api('superadmin', 'PUT', `/catalog/variants/${v.id}`, { base_price: c.price, ...(v.serialized ? { min_price: c.price - 100_000 } : {}) });
            v.price = c.price;
            if (c.cost) v.cost = c.cost;
        });
    }
    schedule(at(day, 8, 0), 'warehouse receipts', () => warehouseReceipts(day));
    schedule(at(day, 8, 20), 'warehouse transfers', () => warehouseTransfers(day));
    if ([1, 4].includes(dow(day))) schedule(at(day, 8, 30), 'deposits', depositsAndSettlements);
    schedule(at(day, 8, 45), 'pulsa', pulsaTopUps);
    if (!CLOSED.has(day)) {
        for (const b of BRANCHES) branchDay(b, day);
        schedule(at(day, 10, 0), 'branch transfers', () => branchTransfers(day));
    }
    if (day === addDays(OUTAGE.day, 1)) {
        schedule(at(day, 10, 15), 'sync review', async () => {
            const b = BRANCHES.find((x) => x.code === OUTAGE.code);
            const { sales } = await api(b.admin, 'GET', `/sales?location_id=${LOC[b.code]}&sync=issues`);
            // One is left for later: it shows on the "perlu dicek" list.
            for (const s of sales.slice(1)) {
                await api(b.admin, 'POST', `/sales/${s.id}/sync-review`, { note: 'Harga lama di tablet kasir saat offline; selisih sudah dicek' });
            }
        });
    }
    for (const fn of FUTURE.get(day) || []) fn(day);
    FUTURE.delete(day);
    schedule(at(day, 21, 30), 'evening', () => eveningTasks(day));

    while (EVENTS.length) {
        let index = 0;
        for (let i = 1; i < EVENTS.length; i += 1) if (EVENTS[i].t < EVENTS[index].t) index = i;
        const event = EVENTS.splice(index, 1)[0];
        if (event.t > cutoff) continue;
        setClock(event.t);
        try {
            await event.fn();
        } catch (error) {
            if (event.label === 'opening day') throw error;
            recordError(event.label, error);
        }
    }
};

// ── main ─────────────────────────────────────────────────────────────────────

const resetDatabase = async () => {
    const mysql = require('mysql2/promise');
    const admin = await mysql.createConnection({
        host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 3306), user: process.env.DB_USER, password: process.env.DB_PASS,
    });
    const [[schema]] = await admin.query(
        'SELECT DEFAULT_CHARACTER_SET_NAME AS cs, DEFAULT_COLLATION_NAME AS co FROM information_schema.schemata WHERE schema_name = ?', [process.env.DB_NAME]
    );
    await admin.query(`DROP DATABASE IF EXISTS \`${process.env.DB_NAME}\``);
    await admin.query(`CREATE DATABASE \`${process.env.DB_NAME}\` CHARACTER SET ${schema?.cs || 'utf8mb4'} COLLATE ${schema?.co || 'utf8mb4_0900_ai_ci'}`);
    await admin.end();
};

const main = async () => {
    const started = RealDate.now();
    const knex = require('knex')(require('../knexfile'));
    if (args.reset) {
        console.log(`demo-year: re-creating database ${process.env.DB_NAME}`);
        await knex.destroy();
        await resetDatabase();
        const fresh = require('knex')(require('../knexfile'));
        await fresh.migrate.latest();
        await fresh.seed.run();
        await fresh.destroy();
    } else {
        await knex.migrate.latest();
        const [[used]] = await knex.raw('SELECT (SELECT COUNT(*) FROM products) + (SELECT COUNT(*) FROM sales) + (SELECT COUNT(*) FROM journal_entries) AS n');
        if (Number(used.n) > 0) {
            await knex.destroy();
            die(`${process.env.DB_NAME} already has products, sales or journals; run with --reset to rebuild it (drops the database)`);
        }
        await knex.seed.run();
        await knex.destroy();
    }

    // From here on every Date and every NOW() follows the simulated clock.
    globalThis.Date = SimDate;
    simNow = at(addDays(FROM, -1), 9, 0);

    pool = require('../src/db');
    const rawGet = pool.getConnection.bind(pool);
    pool.getConnection = async () => {
        const conn = await rawGet();
        if (conn.connection.__simNow !== simNow) {
            await conn.query(`SET TIMESTAMP = ${(simNow / 1000).toFixed(3)}`);
            conn.connection.__simNow = simNow;
        }
        return conn;
    };
    for (const method of ['execute', 'query']) {
        pool[method] = async (...a) => {
            const conn = await pool.getConnection();
            try {
                return await conn[method](...a);
            } finally {
                conn.release();
            }
        };
    }
    jwt = require('jsonwebtoken');
    const express = require('express');
    const cookieParser = require('cookie-parser');
    const app = express();
    app.use(express.json({ limit: '20mb' }));
    app.use(cookieParser());
    for (const [prefix, file] of [['categories', 'categories'], ['vouchers', 'vouchers'], ['catalog', 'catalog'], ['stock', 'stock'],
        ['purchasing', 'purchasing'], ['transfers', 'transfers'], ['opnames', 'opnames'], ['customers', 'customers'],
        ['cash-sessions', 'cash_sessions'], ['sales', 'sales'], ['accounting', 'accounting'], ['expenses', 'expenses'], ['pulsa-deposit', 'pulsa_deposit']]) {
        app.use(`/api/${prefix}`, require(`../src/routes/${file}`));
    }
    const server = await new Promise((resolve) => {
        const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    BASE_URL = `http://127.0.0.1:${server.address().port}`;

    for (const u of await q('SELECT id, username FROM users')) USERS[u.username] = u.id;
    for (const l of await q('SELECT id, code FROM locations')) LOC[l.code] = l.id;
    for (const m of await q('SELECT id, type FROM payment_methods WHERE is_active = 1 ORDER BY sort_order, id')) PM[m.type] = PM[m.type] || m.id;
    for (const need of ['superadmin', 'akuntan', 'gudang', ...BRANCHES.flatMap((b) => [b.admin, b.kasir])]) {
        if (!USERS[need]) die(`user ${need} is missing; run npm run seed`);
    }

    // The accounts and branches existed before the shop started using the system.
    // A string, not a Date: Dates made by the real Date class are not instanceof the simulated one.
    const before = `${addDays(FROM, -7)} 09:00:00`;
    for (const table of ['users', 'locations', 'user_locations', 'accounts', 'payment_methods', 'roles', 'tax_rates']) {
        const columns = (await q('SELECT column_name AS c FROM information_schema.columns WHERE table_schema = ? AND table_name = ?', [process.env.DB_NAME, table])).map((r) => r.c);
        const set = ['created_at', 'updated_at'].filter((c) => columns.includes(c));
        if (set.length) await q(`UPDATE \`${table}\` SET ${set.map((c) => `${c} = ?`).join(', ')}`, set.map(() => before));
    }

    console.log(`demo-year: ${FROM} → ${TO}${TO === REAL_TODAY ? ' (today until now)' : ''}, scale ${SCALE}, seed ${SEED}`);
    let monthStarted = RealDate.now();
    for (let day = FROM; day <= TO; day = addDays(day, 1)) {
        await runDay(day);
        if (day === lastDayOfMonth(day) || day === TO) {
            const secs = ((RealDate.now() - monthStarted) / 1000).toFixed(0);
            console.log(`  ${monthOf(day)}  ${String(month.sales).padStart(5)} penjualan  Rp ${Math.round(month.revenue).toLocaleString('id-ID').padStart(15)}  ${month.failures ? `${month.failures} gagal  ` : ''}(${secs}s)`);
            Object.assign(month, { sales: 0, revenue: 0, failures: 0 });
            monthStarted = RealDate.now();
        }
    }

    // Checks: the books balance, company-wide and per location.
    setClock(simNow + 60_000);
    const tb = await api('akuntan', 'GET', '/accounting/trial-balance');
    const bs = await api('akuntan', 'GET', `/accounting/balance-sheet?to=${TO}`);
    const perLocation = [];
    for (const [code, id] of Object.entries(LOC)) {
        const own = await api('akuntan', 'GET', `/accounting/balance-sheet?to=${TO}&location_id=${id}`);
        perLocation.push(`${code} ${own.totals.difference === 0 ? 'seimbang' : `selisih ${own.totals.difference}`}`);
    }
    const years = [...new Set([FROM.slice(0, 4), TO.slice(0, 4)])];
    const rp = (n) => `Rp ${Math.round(n).toLocaleString('id-ID')}`;
    console.log('\ndemo-year: selesai');
    console.log(`  ${stats.sales} penjualan (${stats.offline} offline), ${rp(stats.revenue)}; ${stats.lost} pembeli batal karena stok kosong`);
    console.log(`  ${CUSTOMERS.length} pelanggan, ${stats.returns} retur, ${stats.voids} pembatalan, ${stats.receipts} penerimaan barang, ${stats.transfers} transfer`);
    console.log(`  ${stats.expenses} biaya, ${stats.journals} jurnal manual, ${stats.requests} request API`);
    for (const year of years) {
        const from = `${year}-01-01` < FROM ? FROM : `${year}-01-01`;
        const to = `${year}-12-31` > TO ? TO : `${year}-12-31`;
        const pl = await api('akuntan', 'GET', `/accounting/profit-loss?from=${from}&to=${to}`);
        console.log(`  Laba bersih ${year}: ${rp(pl.totals.net_profit)}`);
    }
    console.log(`  Neraca saldo: debit ${rp(tb.totals.debit)} = kredit ${rp(tb.totals.credit)}${tb.totals.debit === tb.totals.credit ? '' : '  (TIDAK SEIMBANG)'}`);
    console.log(`  Neraca ${TO}: aset ${rp(bs.totals.assets)}, selisih ${bs.totals.difference}; per lokasi: ${perLocation.join(', ')}`);
    if (stats.failures) {
        console.log(`  ${stats.failures} langkah gagal:`);
        for (const [key, n] of [...stats.errors.entries()].sort((a, b) => b[1] - a[1]).slice(0, 15)) console.log(`    ${String(n).padStart(4)}× ${key}`);
    }
    console.log(`  (${((RealDate.now() - started) / 60000).toFixed(1)} menit)`);

    server.close();
    await pool.end();
};

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
