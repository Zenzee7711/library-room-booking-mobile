const mysql = require('mysql2/promise');
const { db } = require('./env');

// A pool rather than a single connection: the single connection used previously
// died permanently if MySQL dropped it, taking every later request with it.
const pool = mysql.createPool({
  host: db.host,
  port: db.port,
  user: db.user,
  password: db.password,
  database: db.database,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  dateStrings: ['DATE'],
});

async function query(sql, params = []) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

module.exports = { pool, query };
