#!/usr/bin/env node
/**
 * Database commands, artisan style:
 *
 *   npm run db <command> [args]
 *
 *   setup                  create the database, run every migration, then the seeds
 *   create                 create DB_NAME if it does not exist
 *   migrate                run pending migrations (creates the database first if needed)
 *   migrate:status         list ran and pending migrations
 *   migrate:rollback       roll back the last batch (--step=N: the last N migrations instead)
 *   migrate:fresh          drop every table and view, then migrate (--seed: also seed)
 *   seed [name]            run every seed in API/seeds, or only the one whose file name starts with [name]
 *   wipe                   drop every table and view
 *   make:migration <name>  new file in API/migrations
 *   make:seed <name>       new file in API/seeds
 *   demo [options]         one year of demo data (see API/scripts/demo-year.js)
 *   backfill               create journals for documents that have none
 *   docs                   rewrite Database.md from the current schema
 *
 * Flags work with or without "--" (npm run db migrate:fresh --seed).
 * migrate:fresh, wipe and demo refuse to run with NODE_ENV=production.
 */
const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

require('dotenv').config({ path: path.resolve(__dirname, '../../.env'), quiet: true });

const mysql = require('mysql2/promise');
const knexConfig = require('../knexfile');

const SCRIPTS = __dirname;
const [command = 'help', ...rest] = process.argv.slice(2);
const positional = rest.filter((a) => !a.startsWith('--'));

// npm swallows "--flag" when it is not after "--" and exposes it as npm_config_flag instead.
const flag = (name) => {
    const arg = rest.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
    if (arg) return arg.includes('=') ? arg.split('=').slice(1).join('=') : true;
    const env = process.env[`npm_config_${name}`];
    return env === undefined || env === '' ? undefined : env === 'true' ? true : env;
};

const DB = process.env.DB_NAME;
const c = { green: (s) => `\x1b[32m${s}\x1b[0m`, yellow: (s) => `\x1b[33m${s}\x1b[0m`, red: (s) => `\x1b[31m${s}\x1b[0m`, dim: (s) => `\x1b[2m${s}\x1b[0m` };
const info = (s) => console.log(`${c.green('✔')} ${s}`);
const fail = (s) => {
    console.error(`${c.red('✖')} ${s}`);
    process.exit(1);
};

const notProduction = (what) => {
    if (process.env.NODE_ENV === 'production') fail(`refusing to ${what} with NODE_ENV=production`);
};

const server = () =>
    mysql.createConnection({
        host: process.env.DB_HOST,
        port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 3306,
        user: process.env.DB_USER,
        password: process.env.DB_PASS,
        multipleStatements: false,
    });

let knexInstance;
const knex = () => (knexInstance ??= require('knex')(knexConfig));

const quoteId = (name) => `\`${String(name).replace(/`/g, '``')}\``;

// ── commands ──────────────────────────────────────────────────────────────────

async function createDatabase() {
    if (!DB) fail('DB_NAME is not set in .env');
    const conn = await server().catch((e) => fail(`cannot connect to MySQL at ${process.env.DB_HOST}:${process.env.DB_PORT || 3306} (${e.code || e.message}). Is it running?`));
    try {
        const [rows] = await conn.query('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?', [DB]);
        if (rows.length) return false;
        await conn.query(`CREATE DATABASE ${quoteId(DB)} CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci`);
        info(`created database ${DB}`);
        return true;
    } finally {
        await conn.end();
    }
}

async function migrate() {
    await createDatabase();
    const [batch, ran] = await knex().migrate.latest();
    if (ran.length === 0) return info('nothing to migrate');
    for (const file of ran) console.log(`  ${c.green('migrated')} ${file}`);
    info(`batch ${batch}: ${ran.length} migration(s)`);
}

async function status() {
    const [done, pending] = await knex().migrate.list();
    for (const m of done) console.log(`  ${c.green('Ran    ')} ${m.name}`);
    for (const m of pending) console.log(`  ${c.yellow('Pending')} ${m.file}`);
    if (!done.length && !pending.length) console.log('  no migrations');
}

async function rollback() {
    const step = flag('step');
    if (step !== undefined) {
        const n = Number(step);
        if (!Number.isInteger(n) || n < 1) fail('--step must be a positive whole number');
        for (let i = 0; i < n; i++) {
            const [, files] = await knex().migrate.down();
            if (!files.length) break;
            for (const file of files) console.log(`  ${c.yellow('rolled back')} ${file}`);
        }
        return info('done');
    }
    const [batch, files] = await knex().migrate.rollback();
    if (!files.length) return info('nothing to roll back');
    for (const file of files) console.log(`  ${c.yellow('rolled back')} ${file}`);
    info(`rolled back batch ${batch}`);
}

async function wipe() {
    notProduction('drop every table');
    if (await createDatabase()) return;
    const conn = await server();
    try {
        await conn.query(`USE ${quoteId(DB)}`);
        const [objects] = await conn.query(
            'SELECT TABLE_NAME AS name, TABLE_TYPE AS type FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?',
            [DB]
        );
        await conn.query('SET FOREIGN_KEY_CHECKS = 0');
        for (const o of objects.filter((o) => o.type === 'VIEW')) await conn.query(`DROP VIEW IF EXISTS ${quoteId(o.name)}`);
        for (const o of objects.filter((o) => o.type !== 'VIEW')) await conn.query(`DROP TABLE IF EXISTS ${quoteId(o.name)}`);
        await conn.query('SET FOREIGN_KEY_CHECKS = 1');
        info(`dropped ${objects.length} table(s)/view(s) from ${DB}`);
    } finally {
        await conn.end();
    }
}

async function seed(name) {
    const options = {};
    if (name) {
        const dir = knexConfig.seeds.directory;
        const match = fs.readdirSync(dir).filter((f) => f.endsWith('.js') && (f === name || f.startsWith(name) || f.replace(/^\d+_/, '').startsWith(name)));
        if (match.length === 0) fail(`no seed matches "${name}" in API/seeds`);
        if (match.length > 1) fail(`"${name}" matches several seeds: ${match.join(', ')}`);
        options.specific = match[0];
    }
    const [files] = await knex().seed.run(options);
    if (!files.length) return info('no seeds to run');
    for (const file of files) console.log(`  ${c.green('seeded')} ${path.basename(file)}`);
    info(`${files.length} seed(s)`);
}

async function make(kind, name) {
    if (!name) fail(`usage: npm run db make:${kind} <name>`);
    const slug = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
    if (!slug) fail('name must contain letters or digits');
    if (kind === 'migration') {
        const file = await knex().migrate.make(slug);
        return info(`created ${path.relative(process.cwd(), file)}`);
    }
    const dir = knexConfig.seeds.directory;
    const next = fs.readdirSync(dir).map((f) => Number(f.match(/^(\d+)_/)?.[1] || 0)).reduce((a, b) => Math.max(a, b), 0) + 1;
    const file = path.join(dir, `${String(next).padStart(2, '0')}_${slug}.js`);
    fs.writeFileSync(
        file,
        `/** @param {import('knex').Knex} knex */\nexports.seed = async function (knex) {\n    // await knex('table').insert([{ ... }]);\n};\n`
    );
    info(`created ${path.relative(process.cwd(), file)}`);
}

// Re-adds flags npm swallowed (see flag()) so the child script sees them in argv.
const withFlags = (names) => [
    ...rest,
    ...names.filter((n) => !rest.some((a) => a.startsWith(`--${n}`)) && flag(n) !== undefined).map((n) => (flag(n) === true ? `--${n}` : `--${n}=${flag(n)}`)),
];

function runScript(file, args = []) {
    const result = spawnSync(process.execPath, [path.join(SCRIPTS, file), ...args], { stdio: 'inherit' });
    process.exit(result.status ?? 1);
}

function help() {
    const lines = fs.readFileSync(__filename, 'utf8').split('\n');
    const start = lines.findIndex((l) => l.includes('npm run db <command>'));
    const end = lines.findIndex((l, i) => i > start && l.trim() === '*/');
    console.log(lines.slice(start, end).map((l) => l.replace(/^ \* ?/, '')).join('\n'));
}

// ── dispatch ──────────────────────────────────────────────────────────────────

const commands = {
    setup: async () => {
        await migrate();
        await seed();
    },
    create: async () => {
        if (!(await createDatabase())) info(`database ${DB} already exists`);
    },
    migrate,
    'migrate:status': status,
    'migrate:rollback': rollback,
    'migrate:fresh': async () => {
        notProduction('run migrate:fresh');
        await wipe();
        await migrate();
        if (flag('seed')) await seed();
    },
    seed: () => seed(positional[0]),
    wipe,
    'make:migration': () => make('migration', positional.join('_')),
    'make:seed': () => make('seed', positional.join('_')),
    demo: () => runScript('demo-year.js', withFlags(['reset', 'from', 'to', 'scale', 'seed'])),
    backfill: () => runScript('backfill-journals.js', rest),
    docs: () => runScript('schema-doc.js', rest),
    help,
};

const run = commands[command];
if (!run) {
    console.error(c.red(`unknown command "${command}"\n`));
    help();
    process.exit(1);
}

Promise.resolve(run())
    .catch((err) => {
        console.error(`${c.red('✖')} ${err.message}`);
        if (process.env.DEBUG) console.error(err);
        process.exitCode = 1;
    })
    .finally(() => knexInstance?.destroy());
