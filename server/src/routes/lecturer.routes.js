const express = require('express');
const { query } = require('../config/db');
const { ensureLecturer } = require('../middleware/auth');

const router = express.Router();

function fullName(first, last) {
  return `${first}${last ? ` ${last}` : ''}`;
}

router.get('/lecturer/bookings/pending', ensureLecturer, async (req, res, next) => {
  try {
    const rows = await query(`
      SELECT
        b.booking_id,
        DATE_FORMAT(b.booking_date, '%Y-%m-%d') AS booking_date,
        b.booking_status, b.user_id, b.slot_id,
        r.room_name, t.start_time, t.end_time,
        u.first_name AS student_first, u.last_name AS student_last
      FROM booking b
      JOIN room r ON r.room_id = b.room_id
      JOIN time_slot t ON t.slot_id = b.slot_id
      JOIN users u ON u.user_id = b.user_id
      WHERE b.booking_status = 'Waiting'
      ORDER BY b.booking_id DESC
    `);

    const bookings = rows.map((row) => ({
      booking_id: row.booking_id,
      booking_date: row.booking_date,
      booking_status: 'Waiting',
      room_name: row.room_name,
      slot_id: row.slot_id,
      start_time: String(row.start_time).slice(0, 5),
      end_time: String(row.end_time).slice(0, 5),
      booked_by_name: fullName(row.student_first, row.student_last),
    }));

    return res.json({ ok: true, bookings });
  } catch (err) {
    return next(err);
  }
});

router.get('/lecturer/bookings/history', ensureLecturer, async (req, res, next) => {
  try {
    const rows = await query(
      `SELECT
         b.booking_id,
         DATE_FORMAT(b.booking_date, '%Y-%m-%d') AS booking_date,
         b.booking_status,
         b.reason AS reject_reason,
         b.slot_id,
         r.room_name, t.start_time, t.end_time,
         u.first_name AS student_first, u.last_name AS student_last,
         a.first_name AS approver_first, a.last_name AS approver_last
       FROM booking b
       JOIN room r ON r.room_id = b.room_id
       JOIN time_slot t ON t.slot_id = b.slot_id
       JOIN users u ON u.user_id = b.user_id
       JOIN users a ON a.user_id = b.approver_id
       WHERE b.approver_id = ?
         AND b.booking_status IN ('Approved', 'Rejected')
       ORDER BY b.booking_id DESC`,
      [req.user.id]
    );

    const bookings = rows.map((row) => ({
      booking_id: row.booking_id,
      booking_date: row.booking_date,
      booking_status: row.booking_status,
      reject_reason: row.reject_reason || '',
      room_name: row.room_name,
      slot_id: row.slot_id,
      start_time: String(row.start_time).slice(0, 5),
      end_time: String(row.end_time).slice(0, 5),
      booked_by_name: fullName(row.student_first, row.student_last),
      approver_name: fullName(row.approver_first, row.approver_last),
    }));

    return res.json({ ok: true, bookings });
  } catch (err) {
    return next(err);
  }
});

// Approve and reject both narrow the UPDATE to rows still Waiting, so the same
// request cannot be decided twice and one lecturer cannot silently overwrite
// another's decision.
router.post('/lecturer/bookings/:id/approve', ensureLecturer, async (req, res, next) => {
  const id = Number(req.params.id) || 0;

  try {
    const result = await query(
      `UPDATE booking
       SET booking_status = 'Approved', approver_id = ?, reason = NULL
       WHERE booking_id = ? AND booking_status = 'Waiting'`,
      [req.user.id, id]
    );

    if (result.affectedRows === 0) {
      return res.status(409).json({ error: 'Booking not found or already handled' });
    }
    return res.json({ ok: true });
  } catch (err) {
    return next(err);
  }
});

router.post('/lecturer/bookings/:id/reject', ensureLecturer, async (req, res, next) => {
  const id = Number(req.params.id) || 0;
  const reason = String((req.body && req.body.reason) || '').trim();
  if (!reason) return res.status(400).json({ error: 'Reason required' });

  try {
    const result = await query(
      `UPDATE booking
       SET booking_status = 'Rejected', approver_id = ?, reason = ?
       WHERE booking_id = ? AND booking_status = 'Waiting'`,
      [req.user.id, reason, id]
    );

    if (result.affectedRows === 0) {
      return res.status(409).json({ error: 'Booking not found or already handled' });
    }
    return res.json({ ok: true });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
