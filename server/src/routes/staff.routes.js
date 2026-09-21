const express = require('express');
const { query } = require('../config/db');
const { ensureStaff } = require('../middleware/auth');
const { upload, publicPathFor } = require('../middleware/upload');
const { todayInTimezone } = require('../lib/time');

const router = express.Router();

function fullName(first, last) {
  return `${first}${last ? ` ${last}` : ''}`;
}

router.get('/staff/bookings/pending', ensureStaff, async (req, res, next) => {
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

router.get('/staff/bookings/history', ensureStaff, async (req, res, next) => {
  try {
    const rows = await query(`
      SELECT
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
      LEFT JOIN users a ON a.user_id = b.approver_id
      WHERE b.booking_status IN ('Approved', 'Rejected')
      ORDER BY b.booking_id DESC
    `);

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
      approver_name: row.approver_first ? fullName(row.approver_first, row.approver_last) : '',
    }));

    return res.json({ ok: true, bookings });
  } catch (err) {
    return next(err);
  }
});

router.get('/staff/rooms/management', ensureStaff, async (req, res, next) => {
  try {
    const rows = await query(`
      SELECT
        r.room_id AS id,
        r.room_name AS name,
        r.room_status,
        r.description,
        r.image,
        COALESCE(r.capacity, 0) AS capacity,
        (
          SELECT COUNT(*)
          FROM booking b
          WHERE b.room_id = r.room_id
            AND b.booking_status IN ('Waiting', 'Approved')
            AND b.booking_date >= CURDATE()
        ) AS active_bookings
      FROM room r
      ORDER BY r.room_name ASC
    `);

    const rooms = rows.map((row) => ({
      id: row.id,
      name: row.name,
      description: row.description,
      capacity: Number(row.capacity) || 0,
      image_url: publicPathFor(row.image),
      room_status: row.room_status,
      active_bookings: Number(row.active_bookings) || 0,
    }));

    return res.json({ ok: true, rooms });
  } catch (err) {
    return next(err);
  }
});

router.post('/staff/rooms/create', ensureStaff, async (req, res, next) => {
  const { name, capacity, description } = req.body || {};
  const roomName = String(name || '').trim();
  const roomDescription = String(description || '').trim();
  const roomCapacity = Number.parseInt(capacity, 10);

  if (!roomName) return res.status(400).json({ error: 'Room name is required' });
  if (!Number.isInteger(roomCapacity) || roomCapacity < 0) {
    return res.status(400).json({ error: 'Capacity must be a non-negative whole number' });
  }

  try {
    const duplicate = await query('SELECT room_id FROM room WHERE room_name = ? LIMIT 1', [
      roomName,
    ]);
    if (duplicate.length > 0) {
      return res.status(409).json({ error: 'Room name already exists' });
    }

    // The image is uploaded in a second request once the room has an id, so
    // the column starts empty.
    const result = await query(
      `INSERT INTO room (room_name, room_status, capacity, description, image)
       VALUES (?, 1, ?, ?, '')`,
      [roomName, roomCapacity, roomDescription]
    );

    const id = Number(result.insertId);
    return res.status(201).json({
      ok: true,
      id,
      room: {
        id,
        name: roomName,
        capacity: roomCapacity,
        description: roomDescription,
        room_status: 1,
        image_url: '',
      },
    });
  } catch (err) {
    return next(err);
  }
});

router.post('/staff/rooms/:id/edit', ensureStaff, async (req, res, next) => {
  const roomId = Number(req.params.id) || 0;
  const { name, description, capacity } = req.body || {};
  const roomName = String(name || '').trim();
  const roomCapacity = Number.parseInt(capacity, 10);

  if (!roomId) return res.status(400).json({ error: 'Invalid room id' });
  if (!roomName) return res.status(400).json({ error: 'Room name is required' });
  if (!Number.isInteger(roomCapacity) || roomCapacity < 0) {
    return res.status(400).json({ error: 'Capacity must be a non-negative whole number' });
  }

  try {
    // Room names are unique, so a rename must not collide with another room.
    const duplicate = await query(
      'SELECT room_id FROM room WHERE room_name = ? AND room_id <> ? LIMIT 1',
      [roomName, roomId]
    );
    if (duplicate.length > 0) {
      return res.status(409).json({ error: 'Room name already exists' });
    }

    const result = await query(
      'UPDATE room SET room_name = ?, description = ?, capacity = ? WHERE room_id = ?',
      [roomName, String(description || '').trim(), roomCapacity, roomId]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Room not found' });
    }

    const rows = await query(
      `SELECT room_id AS id, room_name AS name,
              COALESCE(description, '') AS description,
              COALESCE(image, '') AS image,
              COALESCE(capacity, 0) AS capacity,
              room_status
       FROM room WHERE room_id = ? LIMIT 1`,
      [roomId]
    );
    const room = rows[0];

    return res.json({
      ok: true,
      room: {
        id: room.id,
        name: room.name,
        description: room.description,
        capacity: Number(room.capacity) || 0,
        image_url: publicPathFor(room.image),
        room_status: Number(room.room_status),
      },
    });
  } catch (err) {
    return next(err);
  }
});

// Enable or disable a room. Disabling is blocked while bookings are still
// outstanding, so nobody loses a reservation they already hold.
router.post('/staff/rooms/:id/toggle', ensureStaff, async (req, res, next) => {
  const roomId = Number(req.params.id) || 0;

  try {
    const rooms = await query('SELECT room_status FROM room WHERE room_id = ? LIMIT 1', [roomId]);
    if (rooms.length === 0) return res.status(404).json({ error: 'Room not found' });

    const isEnabled = Number(rooms[0].room_status) === 1;

    if (isEnabled) {
      const active = await query(
        `SELECT booking_id FROM booking
         WHERE room_id = ?
           AND booking_status IN ('Waiting', 'Approved')
           AND booking_date >= ?
         LIMIT 1`,
        [roomId, todayInTimezone()]
      );
      if (active.length > 0) {
        return res
          .status(409)
          .json({ error: 'Cannot disable this room while it has active bookings.' });
      }
    }

    const nextStatus = isEnabled ? 0 : 1;
    await query('UPDATE room SET room_status = ? WHERE room_id = ?', [nextStatus, roomId]);
    return res.json({ ok: true, room_status: nextStatus });
  } catch (err) {
    return next(err);
  }
});

// Upload or replace a room photo. This previously ran with no authentication
// at all, which let anyone replace any room's image.
router.post('/rooms/:id/image', ensureStaff, upload.single('image'), async (req, res, next) => {
  const roomId = Number(req.params.id) || 0;
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

  try {
    const result = await query('UPDATE room SET image = ? WHERE room_id = ?', [
      req.file.filename,
      roomId,
    ]);
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Room not found' });
    }

    return res.json({
      ok: true,
      filename: req.file.filename,
      url: publicPathFor(req.file.filename),
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
