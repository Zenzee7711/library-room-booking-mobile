const app = require('./app');
const { port } = require('./config/env');
const { pool } = require('./config/db');

const server = app.listen(port, () => {
  console.log(`Room booking API listening on http://localhost:${port}`);
});

// Finish in-flight requests and hand the database connections back before the
// process exits, instead of dropping them.
function shutdown(signal) {
  console.log(`${signal} received, shutting down.`);
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
