const { TIMEZONE } = require('../config/constants');

// 'en-CA' formats as YYYY-MM-DD, which is what the DATE columns and the client
// both use. Formatting in a fixed timezone rather than reading the server's
// local clock keeps "today" the same wherever the API is deployed.
function todayInTimezone() {
  return new Date().toLocaleDateString('en-CA', { timeZone: TIMEZONE });
}

function nowHourMinute() {
  return new Date().toLocaleTimeString('en-GB', {
    timeZone: TIMEZONE,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
  });
}

module.exports = { todayInTimezone, nowHourMinute };
