const express = require('express');
const { query } = require('../config/db');
const { requireAuth } = require('../middleware/auth');
const { publicPathFor } = require('../middleware/upload');
const { todayInTimezone, nowHourMinute } = require('../lib/time');

const router = express.Router();

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

router.get('/time-slots', requireAuth, async (req, res, next) => {
  try {
    const slots = await query(
      'SELECT slot_id, start_time, end_time FROM time_slot ORDER BY slot_id ASC'
    );
    return res.json({ ok: true, slots });
  } catch (err) {
    return next(err);
  }
});

// The room grid for a given day: every room, with a status for every slot.
router.get('/common/rooms/availability', requireAuth, async (req, res, next) => {
  const date = String(req.query.date || '').slice(0, 10);
  if (!DATE_PATTERN.test(date)) {
    return res.status(400).json({ error: 'date (YYYY-MM-DD) required' });
  }

  try {
    const [rooms, slots, bookings] = await Promise.all([
      query(
        `SELECT room_id, room_name, room_status, description, image, capacity
         FROM room ORDER BY room_name`
      ),
      query('SELECT slot_id, start_time, end_time FROM time_slot ORDER BY slot_id'),
      query(
        `SELECT room_id, slot_id, booking_status
         FROM booking
         WHERE booking_date = ? AND booking_status IN ('Waiting', 'Approved')`,
        [date]
      ),
    ]);

    const takenByRoom = new Map();
    for (const booking of bookings) {
      if (!takenByRoom.has(booking.room_id)) takenByRoom.set(booking.room_id, new Map());
      takenByRoom
        .get(booking.room_id)
        .set(booking.slot_id, booking.booking_status === 'Waiting' ? 'pending' : 'reserved');
    }

    const isToday = date === todayInTimezone();
    const currentTime = nowHourMinute();

    const slotLabels = slots.map((slot) => ({
      id: slot.slot_id,
      label: `${String(slot.start_time).slice(0, 5)} - ${String(slot.end_time).slice(0, 5)}`,
      start: String(slot.start_time).slice(0, 5),
    }));

    const payload = rooms.map((room) => {
      const statuses = {};
      for (const slot of slotLabels) {
        const taken = takenByRoom.get(room.room_id);
        if (room.room_status !== 1) {
          statuses[slot.label] = 'disabled';
        } else if (taken && taken.has(slot.id)) {
          statuses[slot.label] = taken.get(slot.id);
        } else if (isToday && currentTime >= slot.start) {
          statuses[slot.label] = 'passed';
        } else {
          statuses[slot.label] = 'available';
        }
      }

      return {
        id: room.room_id,
        name: room.room_name,
        description: room.description,
        image_url: publicPathFor(room.image),
        room_status: room.room_status,
        capacity: Number(room.capacity ?? 0),
        statuses,
      };
    });

    return res.json({
      ok: true,
      date,
      slots: slots.map((slot) => ({
        slot_id: slot.slot_id,
        start_time: String(slot.start_time).slice(0, 5),
        end_time: String(slot.end_time).slice(0, 5),
      })),
      rooms: payload,
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
