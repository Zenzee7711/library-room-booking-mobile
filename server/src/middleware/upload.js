const path = require('path');
const fs = require('fs');
const multer = require('multer');

const uploadsDir = path.join(__dirname, '..', '..', 'uploads');
fs.mkdirSync(uploadsDir, { recursive: true });

const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    const unique = `${Date.now().toString(36)}-${Math.random().toString(16).slice(2)}`;
    cb(null, `${unique}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_TYPES.has(file.mimetype)) {
      return cb(new Error('Only JPEG, PNG, WebP and HEIC images are allowed'));
    }
    return cb(null, true);
  },
});

// The API returns image paths relative to its own host, so that the same
// response works from an emulator, a simulator and a physical device.
function publicPathFor(filename) {
  return filename ? `/uploads/${encodeURIComponent(filename)}` : '';
}

module.exports = { upload, uploadsDir, publicPathFor };
