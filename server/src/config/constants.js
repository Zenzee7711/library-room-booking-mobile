// Bookings, "today" and slot cut-off times are all evaluated in the
// university's timezone rather than the server's local clock.
const TIMEZONE = process.env.APP_TIMEZONE || 'Asia/Bangkok';

const BOOKING_STATUS = {
  WAITING: 'Waiting',
  APPROVED: 'Approved',
  REJECTED: 'Rejected',
};

module.exports = { TIMEZONE, BOOKING_STATUS };
