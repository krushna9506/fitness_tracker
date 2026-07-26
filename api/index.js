const { neon } = require('@neondatabase/serverless');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'fitness_tracker_secret_key_2026';
const DATABASE_URL = process.env.DATABASE_URL;

function getDb() {
  if (!DATABASE_URL) {
    throw new Error('DATABASE_URL environment variable is not configured.');
  }
  return neon(DATABASE_URL);
}

function verifyToken(req) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  const token = authHeader.split(' ')[1];
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (err) {
    return null;
  }
}

module.exports = async (req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Authorization'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const url = req.url || '';
  const sql = getDb();

  try {
    // ----------------------------------------------------
    // AUTH: REGISTER
    // ----------------------------------------------------
    if (url.startsWith('/api/auth/register') && req.method === 'POST') {
      const { email, password, display_name } = req.body || {};
      if (!email || !password) {
        return res.status(400).json({ error: 'Email and password required' });
      }

      const existing = await sql`SELECT id FROM users WHERE email = ${email}`;
      if (existing.length > 0) {
        return res.status(400).json({ error: 'Email already registered' });
      }

      const hash = await bcrypt.hash(password, 10);
      const rows = await sql`
        INSERT INTO users (email, password_hash, display_name)
        VALUES (${email}, ${hash}, ${display_name || ''})
        RETURNING id, email, display_name, weekly_goal, weekly_calorie_goal
      `;
      const user = rows[0];
      const token = jwt.sign({ uid: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });
      return res.status(200).json({ token, user });
    }

    // ----------------------------------------------------
    // AUTH: LOGIN
    // ----------------------------------------------------
    if (url.startsWith('/api/auth/login') && req.method === 'POST') {
      const { email, password } = req.body || {};
      if (!email || !password) {
        return res.status(400).json({ error: 'Email and password required' });
      }

      const rows = await sql`SELECT * FROM users WHERE email = ${email}`;
      if (rows.length === 0) {
        return res.status(400).json({ error: 'Invalid credentials' });
      }

      const user = rows[0];
      const valid = await bcrypt.compare(password, user.password_hash);
      if (!valid) {
        return res.status(400).json({ error: 'Invalid credentials' });
      }

      const token = jwt.sign({ uid: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });
      return res.status(200).json({
        token,
        user: {
          id: user.id,
          email: user.email,
          display_name: user.display_name,
          weekly_goal: user.weekly_goal,
          weekly_calorie_goal: user.weekly_calorie_goal
        }
      });
    }

    // Authenticated endpoints require JWT
    const decoded = verifyToken(req);
    if (!decoded) {
      return res.status(401).json({ error: 'Unauthorized token' });
    }
    const uid = decoded.uid;

    // ----------------------------------------------------
    // PROFILE
    // ----------------------------------------------------
    if (url.startsWith('/api/profile')) {
      if (req.method === 'GET') {
        const rows = await sql`SELECT id, email, display_name, weekly_goal, weekly_calorie_goal FROM users WHERE id = ${uid}`;
        if (rows.length === 0) return res.status(404).json({ error: 'User not found' });
        return res.status(200).json(rows[0]);
      }
      if (req.method === 'PUT') {
        const { weekly_goal, weekly_calorie_goal, display_name } = req.body || {};
        const rows = await sql`
          UPDATE users
          SET weekly_goal = COALESCE(${weekly_goal}, weekly_goal),
              weekly_calorie_goal = COALESCE(${weekly_calorie_goal}, weekly_calorie_goal),
              display_name = COALESCE(${display_name}, display_name)
          WHERE id = ${uid}
          RETURNING id, email, display_name, weekly_goal, weekly_calorie_goal
        `;
        return res.status(200).json(rows[0]);
      }
    }

    // ----------------------------------------------------
    // WORKOUTS
    // ----------------------------------------------------
    if (url.startsWith('/api/workouts')) {
      if (req.method === 'GET') {
        const rows = await sql`
          SELECT id, type, duration, calories, time, notes, intensity, rpe
          FROM workouts
          WHERE user_id = ${uid}
          ORDER BY time DESC
        `;
        return res.status(200).json(rows);
      }
      if (req.method === 'POST') {
        const { type, duration, calories, notes, intensity, rpe } = req.body || {};
        const rows = await sql`
          INSERT INTO workouts (user_id, type, duration, calories, notes, intensity, rpe)
          VALUES (${uid}, ${type || 'Workout'}, ${duration || 0}, ${calories || 0}, ${notes || ''}, ${intensity || 'Moderate'}, ${rpe || 3})
          RETURNING id, type, duration, calories, time, notes, intensity, rpe
        `;
        return res.status(200).json(rows[0]);
      }
    }

    // ----------------------------------------------------
    // PLANS
    // ----------------------------------------------------
    if (url.startsWith('/api/plans')) {
      if (req.method === 'GET') {
        const rows = await sql`
          SELECT id, name, description, sessions_per_week, minutes
          FROM plans
          WHERE user_id = ${uid}
          ORDER BY created_at DESC
        `;
        return res.status(200).json(rows);
      }
      if (req.method === 'POST') {
        const { name, description, sessions_per_week, minutes } = req.body || {};
        const rows = await sql`
          INSERT INTO plans (user_id, name, description, sessions_per_week, minutes)
          VALUES (${uid}, ${name || 'Plan'}, ${description || ''}, ${sessions_per_week || 3}, ${minutes || 30})
          RETURNING id, name, description, sessions_per_week, minutes
        `;
        return res.status(200).json(rows[0]);
      }
    }

    return res.status(404).json({ error: 'Endpoint not found' });
  } catch (err) {
    console.error('API Error:', err);
    return res.status(500).json({ error: err.message || 'Internal Server Error' });
  }
};
