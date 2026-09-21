const express = require('express');
const { query } = require('../config/db');
const { ensureStudent } = require('../middleware/auth');
const { todayInTimezone, nowHourMinute } = require('../lib/time');

const router = express.Router();

// Create a booking request. The booking is always filed against the caller's
// own token; no user id is read from the request body.
router.post('/student/bookings', ensureStudent, async (req, res, next) => {
  const { room_id, slot_id, booking_date, objective = '' } = req.body || {};
  if (!room_id || !slot_id || !booking_date) {
    return res.status(400).json({ error: 'room_id, slot_id and booking_date are required' });
  }

  try {
    const slots = await query('SELECT slot_id, start_time FROM time_slot WHERE slot_id = ?', [
      slot_id,
    ]);
    if (slots.length === 0) return res.status(400).json({ error: 'Invalid slot' });

    const today = todayInTimezone();
    const slotStart = String(slots[0].start_time).slice(0, 5);

    if (booking_date < today) {
      return res.status(400).json({ error: 'Cannot book in the past' });
    }
    if (booking_date === today && nowHourMinute() >= slotStart) {
      return res.status(400).json({ error: 'This time slot has already started today' });
    }

    const rooms = await query('SELECT room_status FROM room WHERE room_id = ?', [room_id]);
    if (rooms.length === 0) return res.status(404).json({ error: 'Room not found' });
    if (rooms[0].room_status !== 1) {
      return res.status(409).json({ error: 'Room is not available' });
    }

    const slotTaken = await query(
      `SELECT booking_id FROM booking
       WHERE room_id = ? AND slot_id = ? AND booking_date = ?
         AND booking_status IN ('Waiting', 'Approved')
       LIMIT 1`,
      [room_id, slot_id, booking_date]
    );
    if (slotTaken.length > 0) {
      return res.status(409).json({ error: 'Time slot already booked for this room' });
    }

    const ownBooking = await query(
      `SELECT booking_id FROM booking
       WHERE user_id = ? AND booking_date = ?
         AND booking_status IN ('Waiting', 'Approved')
       LIMIT 1`,
      [req.user.id, booking_date]
    );
    if (ownBooking.length > 0) {
      return res.status(409).json({ error: 'You already have an active booking for this day' });
    }

    const result = await query(
      `INSERT INTO booking (user_id, room_id, slot_id, booking_date, objective, booking_status, created_time)
       VALUES (?, ?, ?, ?, ?, 'Waiting', NOW())`,
      [req.user.id, room_id, slot_id, booking_date, objective]
    );

    return res.status(201).json({ ok: true, id: result.insertId });
  } catch (err) {
    return next(err);
  }
});

router.get('/student/bookings/history', ensureStudent, async (req, res, next) => {
  try {
    const rows = await query(
      `SELECT
         b.booking_id,
         DATE_FORMAT(b.booking_date, '%Y-%m-%d') AS booking_date,
         b.booking_status,
         b.objective,
         b.reason AS reject_reason,
         b.approver_id,
         r.room_id, r.room_name,
         t.slot_id, t.start_time, t.end_time,
         approver.first_name AS approver_first,
         approver.last_name AS approver_last
       FROM booking b
       JOIN room r ON r.room_id = b.room_id
       JOIN time_slot t ON t.slot_id = b.slot_id
       LEFT JOIN users approver ON approver.user_id = b.approver_id
       WHERE b.user_id = ?
       ORDER BY b.booking_id DESC`,
      [req.user.id]
    );

    const bookings = rows.map((row) => ({
      booking_id: row.booking_id,
      booking_date: row.booking_date,
      booking_status: row.booking_status,
      objective: row.objective,
      reject_reason: row.reject_reason || '',
      approver_id: row.approver_id,
      approver_name: row.approver_first
        ? `${row.approver_first}${row.approver_last ? ` ${row.approver_last}` : ''}`
        : '',
      room_id: row.room_id,
      room_name: row.room_name,
      slot_id: row.slot_id,
      start_time: String(row.start_time).slice(0, 5),
      end_time: String(row.end_time).slice(0, 5),
    }));

    return res.json({ ok: true, bookings });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
