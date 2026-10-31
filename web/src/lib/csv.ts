// Client-side CSV export for report tables (opens in Excel / Google Sheets).

type Cell = string | number | null | undefined;

const escape = (value: Cell): string => {
  if (value === null || value === undefined) return '';
  const s = String(value);
  return /[",\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/** Downloads rows as a UTF-8 CSV (with BOM so Excel reads non-ASCII names correctly). */
export function downloadCsv(filename: string, header: string[], rows: Cell[][]): void {
  const text = [header, ...rows].map((r) => r.map(escape).join(',')).join('\r\n');
  const blob = new Blob(['﻿', text], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename.endsWith('.csv') ? filename : `${filename}.csv`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
