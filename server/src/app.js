const express = require('express');
const cors = require('cors');
const multer = require('multer');

const { corsOrigins } = require('./config/env');
const { uploadsDir } = require('./middleware/upload');

const authRoutes = require('./routes/auth.routes');
const roomRoutes = require('./routes/rooms.routes');
const studentRoutes = require('./routes/student.routes');
const lecturerRoutes = require('./routes/lecturer.routes');
const staffRoutes = require('./routes/staff.routes');

const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// With CORS_ORIGINS unset every origin is allowed, which is what a mobile
// client needs locally. Setting it restricts the API to those origins.
app.use(cors(corsOrigins.length > 0 ? { origin: corsOrigins } : undefined));

app.use('/uploads', express.static(uploadsDir));

app.use('/', authRoutes);
app.use('/', roomRoutes);
app.use('/', studentRoutes);
app.use('/', lecturerRoutes);
app.use('/', staffRoutes);

app.get('/health', (req, res) => res.json({ ok: true }));

app.use((req, res) => res.status(404).json({ error: 'Not found' }));

// eslint-disable-next-line no-unused-vars -- Express identifies error handlers by arity
app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError || String(err.message).startsWith('Only JPEG')) {
    return res.status(400).json({ error: err.message });
  }

  // Logged in full for the operator; the client only ever sees a generic
  // message, so internal details are not leaked in a response.
  console.error(err);
  return res.status(500).json({ error: 'Server error' });
});

module.exports = app;
