// The date a business document took effect: goods received, an item returned, stock counted, an
// expense paid. It may be earlier than the day it is entered (a receipt typed in two days late
// still belongs to the day the goods arrived), so its stock movements, journal and number use it.
const { AppError } = require('../utils/errors');
const { dateOnly, isPeriodClosed } = require('./journal');

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Validates `value` (YYYY-MM-DD, empty = today) and returns { date, at }:
 *   date  'YYYY-MM-DD'
 *   at    the moment to store: now for today, noon of that day for an earlier date
 * Refuses dates in the future, before `notBefore` (YYYY-MM-DD) and in closed accounting periods.
 */
const documentDate = async (conn, value, { label = 'Tanggal', notBefore = null, notBeforeLabel = null } = {}) => {
    const today = dateOnly();
    if (value === undefined || value === null || value === '') {
        if (notBefore && today < notBefore) throw new AppError(`${label} tidak boleh sebelum ${notBeforeLabel || notBefore}`);
        if (await isPeriodClosed(conn, today)) throw new AppError(`Periode ${today.slice(0, 7)} sudah ditutup`);
        return { date: today, at: new Date() };
    }
    const date = String(value).slice(0, 10);
    const [y, m, d] = date.split('-').map(Number);
    const at = DATE.test(date) ? new Date(y, m - 1, d, 12) : null;
    if (!at || Number.isNaN(at.getTime()) || dateOnly(at) !== date) throw new AppError(`${label} harus berformat YYYY-MM-DD`);
    if (date > today) throw new AppError(`${label} tidak boleh di masa depan`);
    if (notBefore && date < notBefore) throw new AppError(`${label} tidak boleh sebelum ${notBeforeLabel || notBefore}`);
    if (await isPeriodClosed(conn, date)) throw new AppError(`Periode ${date.slice(0, 7)} sudah ditutup`);
    return { date, at: date === today ? new Date() : at };
};

module.exports = { documentDate };
