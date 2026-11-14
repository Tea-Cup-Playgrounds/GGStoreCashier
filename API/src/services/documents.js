// Numbers for server-side documents: {PREFIX}-{LOCATION CODE}-{YYMMDD}-{seq}, e.g. GR-WH-261031-0001.
// The counter row is incremented with LAST_INSERT_ID(expr), which is atomic per row, so two
// requests never get the same number even outside a shared transaction.
// locationId null = a company-wide document (e.g. a manual journal), numbered under "HQ".
// `date` (YYYY-MM-DD or a Date) is the document's own date, so a receipt entered late for 31 Oct
// is numbered GR-…-261031-…; default today.
const nextDocumentNumber = async (conn, prefix, locationId, date = null) => {
    let code = 'HQ';
    if (locationId) {
        const [[location]] = await conn.execute('SELECT code FROM locations WHERE id = ?', [locationId]);
        code = location?.code || `L${locationId}`;
    }
    locationId = locationId || 0;

    let day;
    if (typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
        day = date;
    } else {
        const d = date ? new Date(date) : new Date();
        day = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    }
    const [result] = await conn.execute(
        `INSERT INTO document_counters (prefix, location_id, day, last_seq) VALUES (?, ?, ?, LAST_INSERT_ID(1))
         ON DUPLICATE KEY UPDATE last_seq = LAST_INSERT_ID(last_seq + 1)`,
        [prefix, locationId, day]
    );
    const seq = result.insertId;
    return `${prefix}-${code}-${day.slice(2).replace(/-/g, '')}-${String(seq).padStart(4, '0')}`;
};

module.exports = { nextDocumentNumber };
