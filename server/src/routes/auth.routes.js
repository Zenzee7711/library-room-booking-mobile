const express = require('express');
const argon2 = require('argon2');
const { query } = require('../config/db');
const { signUser, requireAuth } = require('../middleware/auth');

const router = express.Router();

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD_LENGTH = 8;

const ARGON2_OPTIONS = {
  type: argon2.argon2id,
  timeCost: 3,
  memoryCost: 1 << 16,
  parallelism: 1,
  hashLength: 32,
  saltLength: 16,
};

function toPublicUser(row) {
  return {
    id: row.user_id,
    email: row.email,
    role: row.role,
    first_name: row.first_name,
    last_name: row.last_name,
    name: `${row.first_name}${row.last_name ? ` ${row.last_name}` : ''}`,
  };
}

router.post('/api/login', async (req, res, next) => {
  const { email, password } = req.body || {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password required' });
  }

  try {
    const rows = await query(
      `SELECT user_id, email, password, first_name, last_name, role
       FROM users WHERE email = ? LIMIT 1`,
      [email]
    );

    // One message for both cases, so the response cannot be used to find out
    // which email addresses are registered.
    const invalid = { error: 'Incorrect email or password' };
    if (rows.length === 0) return res.status(401).json(invalid);

    const user = rows[0];
    const passwordMatches = await argon2.verify(user.password || '', password);
    if (!passwordMatches) return res.status(401).json(invalid);

    return res.json({ ok: true, user: toPublicUser(user), token: signUser(user) });
  } catch (err) {
    return next(err);
  }
});

router.post('/api/register/create', async (req, res, next) => {
  const { email, password, first_name, last_name = '' } = req.body || {};

  if (!email || !first_name || !password) {
    return res.status(400).json({ error: 'email, first_name and password are required' });
  }
  if (!EMAIL_PATTERN.test(email)) {
    return res.status(400).json({ error: 'Please enter a valid email address' });
  }
  if (String(password).length < MIN_PASSWORD_LENGTH) {
    return res
      .status(400)
      .json({ error: `Password must be at least ${MIN_PASSWORD_LENGTH} characters` });
  }

  try {
    const existing = await query('SELECT user_id FROM users WHERE email = ? LIMIT 1', [email]);
    if (existing.length > 0) {
      return res.status(409).json({ error: 'Email already registered' });
    }

    const passwordHash = await argon2.hash(password, ARGON2_OPTIONS);

    // Self-registration always creates a student. A pre-hashed password is
    // never accepted from the client, and neither is a role: either would let
    // a caller hand themselves staff or lecturer rights.
    const result = await query(
      'INSERT INTO users (email, password, first_name, last_name, role) VALUES (?, ?, ?, ?, ?)',
      [email, passwordHash, first_name, last_name, 'student']
    );

    const user = {
      user_id: result.insertId,
      email,
      first_name,
      last_name,
      role: 'student',
    };

    return res.status(201).json({ ok: true, user: toPublicUser(user), token: signUser(user) });
  } catch (err) {
    return next(err);
  }
});

// Lets the app confirm a stored token is still valid on launch.
router.get('/common/user_auth', requireAuth, async (req, res, next) => {
  try {
    const rows = await query(
      `SELECT user_id, email, first_name, last_name, role
       FROM users WHERE user_id = ? LIMIT 1`,
      [req.user.id]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'User not found' });

    return res.json({ ok: true, user: toPublicUser(rows[0]) });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
