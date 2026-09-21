const jwt = require('jsonwebtoken');
const { jwt: jwtConfig } = require('../config/env');

function signUser(user) {
  return jwt.sign(
    {
      id: user.user_id,
      email: user.email,
      role: user.role,
      first_name: user.first_name,
      last_name: user.last_name || '',
    },
    jwtConfig.secret,
    { expiresIn: jwtConfig.expiresIn }
  );
}

function readBearerToken(req) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (!token || !/^Bearer$/i.test(scheme)) return null;

  try {
    return jwt.verify(token, jwtConfig.secret);
  } catch {
    return null;
  }
}

function requireAuth(req, res, next) {
  const user = readBearerToken(req);
  if (!user) return res.status(401).json({ error: 'Not logged in' });
  req.user = user;
  return next();
}

// Always mounted after requireAuth, so req.user is set by the time this runs.
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Not logged in' });
    if (!roles.includes(req.user.role)) return res.status(403).json({ error: 'Forbidden' });
    return next();
  };
}

const ensureStudent = [requireAuth, requireRole('student')];
const ensureLecturer = [requireAuth, requireRole('lecturer')];
const ensureStaff = [requireAuth, requireRole('staff')];

module.exports = {
  signUser,
  requireAuth,
  requireRole,
  ensureStudent,
  ensureLecturer,
  ensureStaff,
};
