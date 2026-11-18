import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { GIFT_BACKDROPS, GIFT_PATTERNS, GIFT_SKINS_BY_CATEGORY } from './giftUpgradesData.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const dbPath = path.join(__dirname, 'portal.db');
const db = new DatabaseSync(dbPath);

// Provide transaction wrapper for node:sqlite DatabaseSync
db.transaction = function (fn) {
  return (...args) => {
    db.exec('BEGIN');
    try {
      const result = fn(...args);
      db.exec('COMMIT');
      return result;
    } catch (err) {
      try {
        db.exec('ROLLBACK');
      } catch (_) {}
      throw err;
    }
  };
};

// Enable WAL journal mode and busy timeout for safe concurrent access
try {
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA busy_timeout = 5000;");
} catch (pragmaErr) {
  console.warn('[DB] PRAGMA WAL/busy_timeout warning:', pragmaErr);
}

// Register UTF-8 case-folding for SQLite so Cyrillic / non-ASCII search works properly
try {
  db.function('LOWER', (str) => {
    if (str === null || str === undefined) return '';
    return String(str).toLowerCase();
  });
} catch (fnErr) {
  console.warn('[DB] Could not register custom LOWER function:', fnErr);
}

// Initialize database schema
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT UNIQUE DEFAULT NULL,
    first_name TEXT DEFAULT '',
    last_name TEXT DEFAULT '',
    username TEXT UNIQUE,
    avatar TEXT DEFAULT '',
    profile_completed INTEGER DEFAULT 0,
    token TEXT,
    is_bot INTEGER DEFAULT 0,
    bot_owner_id INTEGER DEFAULT NULL,
    bot_token TEXT UNIQUE,
    description TEXT DEFAULT '',
    verification TEXT DEFAULT 'none',
    pinned_channel_id INTEGER DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS auth_codes (
    identifier TEXT PRIMARY KEY,
    code TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    attempts INTEGER DEFAULT 0,
    sent_at INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS chat_participants (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(chat_id, user_id),
    FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    reply_markup TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_read INTEGER DEFAULT 0,
    FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS bot_updates (
    update_id INTEGER PRIMARY KEY AUTOINCREMENT,
    bot_id INTEGER NOT NULL,
    chat_id INTEGER NOT NULL,
    message_id INTEGER NOT NULL,
    update_type TEXT DEFAULT 'message',
    callback_id TEXT DEFAULT NULL,
    callback_data TEXT DEFAULT NULL,
    user_id INTEGER DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS botfather_sessions (
    user_id INTEGER PRIMARY KEY,
    step TEXT NOT NULL DEFAULT 'IDLE',
    draft_name TEXT DEFAULT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS channels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER UNIQUE NOT NULL,
    owner_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    username TEXT UNIQUE NOT NULL,
    avatar TEXT DEFAULT '',
    description TEXT DEFAULT '',
    verification TEXT DEFAULT 'none',
    pinned_channel_id INTEGER DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
    FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS post_likes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(message_id, user_id),
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS post_views (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(message_id, user_id),
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS post_comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS user_gifts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id INTEGER NOT NULL,
    recipient_id INTEGER NOT NULL,
    gift_id TEXT NOT NULL,
    gift_name TEXT NOT NULL,
    gift_file TEXT NOT NULL,
    price INTEGER DEFAULT 50,
    comment TEXT DEFAULT '',
    chat_id INTEGER DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS user_secondary_usernames (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    username TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
  CREATE INDEX IF NOT EXISTS idx_chat_participants_user ON chat_participants(user_id);
  CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
  CREATE INDEX IF NOT EXISTS idx_secondary_usernames ON user_secondary_usernames(username);
  CREATE INDEX IF NOT EXISTS idx_secondary_user_id ON user_secondary_usernames(user_id);
  CREATE INDEX IF NOT EXISTS idx_bot_updates_bot ON bot_updates(bot_id, update_id);
  CREATE INDEX IF NOT EXISTS idx_channels_username ON channels(username);
  CREATE INDEX IF NOT EXISTS idx_channels_chat_id ON channels(chat_id);
  CREATE INDEX IF NOT EXISTS idx_post_likes_msg ON post_likes(message_id);
  CREATE INDEX IF NOT EXISTS idx_post_views_msg ON post_views(message_id);
  CREATE INDEX IF NOT EXISTS idx_post_comments_msg ON post_comments(message_id);
  CREATE INDEX IF NOT EXISTS idx_user_gifts_recipient ON user_gifts(recipient_id);
  CREATE INDEX IF NOT EXISTS idx_user_gifts_sender ON user_gifts(sender_id);
`);

// Runtime column migrations if users or chats table was already created
try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS user_secondary_usernames (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      username TEXT UNIQUE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_secondary_usernames ON user_secondary_usernames(username);
    CREATE INDEX IF NOT EXISTS idx_secondary_user_id ON user_secondary_usernames(user_id);

    CREATE TABLE IF NOT EXISTS push_subscriptions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      endpoint TEXT UNIQUE NOT NULL,
      p256dh TEXT NOT NULL,
      auth TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_push_user ON push_subscriptions(user_id);

    CREATE TABLE IF NOT EXISTS user_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      token TEXT NOT NULL UNIQUE,
      device_name TEXT NOT NULL,
      platform TEXT NOT NULL,
      browser TEXT DEFAULT '',
      ip_address TEXT DEFAULT '',
      location TEXT DEFAULT '',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      last_active_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON user_sessions(token);
  `);
} catch (secErr) {
  console.error('[DB Migration secondary_usernames / push / sessions]', secErr);
}

try {
  const userColumns = db.prepare("PRAGMA table_info(users)").all().map(c => c.name);
  if (!userColumns.includes('is_bot')) {
    db.exec("ALTER TABLE users ADD COLUMN is_bot INTEGER DEFAULT 0");
  }
  if (!userColumns.includes('bot_owner_id')) {
    db.exec("ALTER TABLE users ADD COLUMN bot_owner_id INTEGER DEFAULT NULL");
  }
  if (!userColumns.includes('bot_token')) {
    db.exec("ALTER TABLE users ADD COLUMN bot_token TEXT DEFAULT NULL");
  }
  if (!userColumns.includes('description')) {
    db.exec("ALTER TABLE users ADD COLUMN description TEXT DEFAULT ''");
  }
  if (!userColumns.includes('sparks')) {
    db.exec("ALTER TABLE users ADD COLUMN sparks INTEGER DEFAULT 250");
  }
  if (!userColumns.includes('verification')) {
    db.exec("ALTER TABLE users ADD COLUMN verification TEXT DEFAULT 'none'");
  }
  if (!userColumns.includes('is_frozen')) {
    db.exec("ALTER TABLE users ADD COLUMN is_frozen INTEGER DEFAULT 0");
  }
  if (!userColumns.includes('frozen_reason')) {
    db.exec("ALTER TABLE users ADD COLUMN frozen_reason TEXT DEFAULT ''");
  }
  if (!userColumns.includes('frozen_until')) {
    db.exec("ALTER TABLE users ADD COLUMN frozen_until TEXT DEFAULT ''");
  }
  if (!userColumns.includes('is_premium')) {
    db.exec("ALTER TABLE users ADD COLUMN is_premium INTEGER DEFAULT 0");
  }
  if (!userColumns.includes('premium_since')) {
    db.exec("ALTER TABLE users ADD COLUMN premium_since TEXT DEFAULT ''");
  }
  if (!userColumns.includes('premium_until')) {
    db.exec("ALTER TABLE users ADD COLUMN premium_until TEXT DEFAULT ''");
  }
  if (!userColumns.includes('has_cloud_password')) {
    db.exec("ALTER TABLE users ADD COLUMN has_cloud_password INTEGER DEFAULT 0");
  }
  if (!userColumns.includes('cloud_password_hash')) {
    db.exec("ALTER TABLE users ADD COLUMN cloud_password_hash TEXT DEFAULT ''");
  }
  if (!userColumns.includes('cloud_password_salt')) {
    db.exec("ALTER TABLE users ADD COLUMN cloud_password_salt TEXT DEFAULT ''");
  }
  if (!userColumns.includes('cloud_password_hint')) {
    db.exec("ALTER TABLE users ADD COLUMN cloud_password_hint TEXT DEFAULT ''");
  }
  if (!userColumns.includes('has_passcode')) {
    db.exec("ALTER TABLE users ADD COLUMN has_passcode INTEGER DEFAULT 0");
  }
  if (!userColumns.includes('passcode_hash')) {
    db.exec("ALTER TABLE users ADD COLUMN passcode_hash TEXT DEFAULT ''");
  }
  if (!userColumns.includes('passcode_salt')) {
    db.exec("ALTER TABLE users ADD COLUMN passcode_salt TEXT DEFAULT ''");
  }
  if (!userColumns.includes('banner_url')) {
    db.exec("ALTER TABLE users ADD COLUMN banner_url TEXT DEFAULT ''");
  }
  if (!userColumns.includes('privacy_messages')) {
    db.exec("ALTER TABLE users ADD COLUMN privacy_messages TEXT DEFAULT 'all'");
  }
  if (!userColumns.includes('privacy_messages_sparks_price')) {
    db.exec("ALTER TABLE users ADD COLUMN privacy_messages_sparks_price INTEGER DEFAULT 1");
  }
  if (!userColumns.includes('privacy_phone')) {
    db.exec("ALTER TABLE users ADD COLUMN privacy_phone TEXT DEFAULT 'all'");
  }
  if (!userColumns.includes('privacy_last_seen')) {
    db.exec("ALTER TABLE users ADD COLUMN privacy_last_seen TEXT DEFAULT 'all'");
  }
  if (!userColumns.includes('name_font')) {
    db.exec("ALTER TABLE users ADD COLUMN name_font TEXT DEFAULT 'default'");
  }
  if (!userColumns.includes('status_font')) {
    db.exec("ALTER TABLE users ADD COLUMN status_font TEXT DEFAULT 'default'");
  }
  if (!userColumns.includes('custom_activity_status')) {
    db.exec("ALTER TABLE users ADD COLUMN custom_activity_status TEXT DEFAULT ''");
  }
  if (!userColumns.includes('is_admin')) {
    db.exec("ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0");
    db.exec("UPDATE users SET is_admin = 1 WHERE id = 1 OR verification = 'dev'");
  }
  if (!userColumns.includes('email')) {
    db.exec("ALTER TABLE users ADD COLUMN email TEXT DEFAULT NULL");
    try {
      db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL");
    } catch (_) {}
  }
  if (!userColumns.includes('pinned_channel_id')) {
    db.exec("ALTER TABLE users ADD COLUMN pinned_channel_id INTEGER DEFAULT NULL");
    console.log('[DB Migration] Added pinned_channel_id column to users table');
  }
  if (!userColumns.includes('artifacts')) {
    db.exec("ALTER TABLE users ADD COLUMN artifacts INTEGER DEFAULT 0");
    console.log('[DB Migration] Added artifacts column to users table');
  }
  try {
    db.exec("PRAGMA wal_checkpoint(FULL);");
  } catch (_) {}
} catch (migrationErr) {
  console.error('[DB Migration users]', migrationErr);
}

try {
  const channelColumns = db.prepare("PRAGMA table_info(channels)").all().map(c => c.name);
  if (!channelColumns.includes('verification')) {
    db.exec("ALTER TABLE channels ADD COLUMN verification TEXT DEFAULT 'none'");
  }
  if (!channelColumns.includes('artifacts')) {
    db.exec("ALTER TABLE channels ADD COLUMN artifacts INTEGER DEFAULT 0");
    console.log('[DB Migration] Added artifacts column to channels table');
  }
} catch (migrationErr) {
  console.error('[DB Migration channels verification/artifacts]', migrationErr);
}

try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS channel_artifacts_gifts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      channel_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_channel_artifacts_chan ON channel_artifacts_gifts(channel_id);
    CREATE INDEX IF NOT EXISTS idx_channel_artifacts_user ON channel_artifacts_gifts(user_id);
  `);
} catch (artErr) {
  console.error('[DB Migration channel_artifacts_gifts]', artErr);
}

try {
  const chatColumns = db.prepare("PRAGMA table_info(chats)").all().map(c => c.name);
  if (!chatColumns.includes('is_channel')) {
    db.exec("ALTER TABLE chats ADD COLUMN is_channel INTEGER DEFAULT 0");
  }
  if (!chatColumns.includes('is_group')) {
    db.exec("ALTER TABLE chats ADD COLUMN is_group INTEGER DEFAULT 0");
  }
  if (!chatColumns.includes('pinned_message_id')) {
    db.exec("ALTER TABLE chats ADD COLUMN pinned_message_id INTEGER DEFAULT NULL");
  }
  if (!chatColumns.includes('wallpaper_url')) {
    db.exec("ALTER TABLE chats ADD COLUMN wallpaper_url TEXT DEFAULT NULL");
  }
  if (!chatColumns.includes('wallpaper_blur')) {
    db.exec("ALTER TABLE chats ADD COLUMN wallpaper_blur INTEGER DEFAULT 0");
  }
  if (!chatColumns.includes('is_saved')) {
    db.exec("ALTER TABLE chats ADD COLUMN is_saved INTEGER DEFAULT 0");
  }
} catch (migrationErr) {
  console.error('[DB Migration chats]', migrationErr);
}

try {
  const msgColumns = db.prepare("PRAGMA table_info(messages)").all().map(c => c.name);
  if (!msgColumns.includes('reply_markup')) {
    db.exec("ALTER TABLE messages ADD COLUMN reply_markup TEXT DEFAULT NULL");
  }
  if (!msgColumns.includes('reply_to_message_id')) {
    db.exec("ALTER TABLE messages ADD COLUMN reply_to_message_id INTEGER DEFAULT NULL");
  }
  if (!msgColumns.includes('is_edited')) {
    db.exec("ALTER TABLE messages ADD COLUMN is_edited INTEGER DEFAULT 0");
  }
  if (!msgColumns.includes('updated_at')) {
    db.exec("ALTER TABLE messages ADD COLUMN updated_at DATETIME DEFAULT NULL");
  }
} catch (mErr) {
  console.error('[DB Migration messages reply_markup / replies / edits]', mErr);
}

try {
  const botUpdColumns = db.prepare("PRAGMA table_info(bot_updates)").all().map(c => c.name);
  if (!botUpdColumns.includes('update_type')) {
    db.exec("ALTER TABLE bot_updates ADD COLUMN update_type TEXT DEFAULT 'message'");
  }
  if (!botUpdColumns.includes('callback_id')) {
    db.exec("ALTER TABLE bot_updates ADD COLUMN callback_id TEXT DEFAULT NULL");
  }
  if (!botUpdColumns.includes('callback_data')) {
    db.exec("ALTER TABLE bot_updates ADD COLUMN callback_data TEXT DEFAULT NULL");
  }
  if (!botUpdColumns.includes('user_id')) {
    db.exec("ALTER TABLE bot_updates ADD COLUMN user_id INTEGER DEFAULT NULL");
  }
} catch (bErr) {
  console.error('[DB Migration bot_updates callback columns]', bErr);
}

try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chat_id INTEGER UNIQUE NOT NULL,
      owner_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      avatar TEXT DEFAULT '',
      description TEXT DEFAULT '',
      invite_code TEXT UNIQUE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
      FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_invite_code ON groups(invite_code);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_chat_id ON groups(chat_id);
  `);
} catch (groupErr) {
  console.error('[DB Migration groups table]', groupErr);
}

try {
  const giftColumns = db.prepare("PRAGMA table_info(user_gifts)").all().map(c => c.name);
  if (!giftColumns.includes('is_upgraded')) db.exec("ALTER TABLE user_gifts ADD COLUMN is_upgraded INTEGER DEFAULT 0");
  if (!giftColumns.includes('nft_number')) db.exec("ALTER TABLE user_gifts ADD COLUMN nft_number INTEGER DEFAULT NULL");
  if (!giftColumns.includes('model_name')) db.exec("ALTER TABLE user_gifts ADD COLUMN model_name TEXT DEFAULT NULL");
  if (!giftColumns.includes('model_file')) db.exec("ALTER TABLE user_gifts ADD COLUMN model_file TEXT DEFAULT NULL");
  if (!giftColumns.includes('model_rarity')) db.exec("ALTER TABLE user_gifts ADD COLUMN model_rarity TEXT DEFAULT NULL");
  if (!giftColumns.includes('backdrop_name')) db.exec("ALTER TABLE user_gifts ADD COLUMN backdrop_name TEXT DEFAULT NULL");
  if (!giftColumns.includes('backdrop_gradient')) db.exec("ALTER TABLE user_gifts ADD COLUMN backdrop_gradient TEXT DEFAULT NULL");
  if (!giftColumns.includes('backdrop_rarity')) db.exec("ALTER TABLE user_gifts ADD COLUMN backdrop_rarity TEXT DEFAULT NULL");
  if (!giftColumns.includes('pattern_name')) db.exec("ALTER TABLE user_gifts ADD COLUMN pattern_name TEXT DEFAULT NULL");
  if (!giftColumns.includes('pattern_svg')) db.exec("ALTER TABLE user_gifts ADD COLUMN pattern_svg TEXT DEFAULT NULL");
  if (!giftColumns.includes('pattern_rarity')) db.exec("ALTER TABLE user_gifts ADD COLUMN pattern_rarity TEXT DEFAULT NULL");
  if (!giftColumns.includes('is_pinned')) db.exec("ALTER TABLE user_gifts ADD COLUMN is_pinned INTEGER DEFAULT 0");
  if (!giftColumns.includes('pinned_at')) db.exec("ALTER TABLE user_gifts ADD COLUMN pinned_at DATETIME DEFAULT NULL");
  if (!giftColumns.includes('is_hidden')) db.exec("ALTER TABLE user_gifts ADD COLUMN is_hidden INTEGER DEFAULT 0");
} catch (giftMigrationErr) {
  console.error('[DB Migration user_gifts]', giftMigrationErr);
}

try {
  const bfCols = db.prepare("PRAGMA table_info(botfather_sessions)").all().map(c => c.name);
  if (!bfCols.includes('target_bot_id')) {
    db.exec("ALTER TABLE botfather_sessions ADD COLUMN target_bot_id INTEGER DEFAULT NULL");
  }
} catch (bfMigrationErr) {
  console.error('[DB Migration botfather_sessions]', bfMigrationErr);
}

try {
  const cpCols = db.prepare("PRAGMA table_info(chat_participants)").all().map(c => c.name);
  if (!cpCols.includes('is_pinned')) {
    db.exec("ALTER TABLE chat_participants ADD COLUMN is_pinned INTEGER DEFAULT 0");
  }
  if (!cpCols.includes('pinned_at')) {
    db.exec("ALTER TABLE chat_participants ADD COLUMN pinned_at DATETIME DEFAULT NULL");
  }
} catch (cpMigrationErr) {
  console.error('[DB Migration chat_participants is_pinned/pinned_at]', cpMigrationErr);
}

try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS post_sparks_reactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      amount INTEGER NOT NULL DEFAULT 1,
      is_anonymous INTEGER NOT NULL DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(message_id, user_id),
      FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_post_sparks_msg ON post_sparks_reactions(message_id);
  `);
} catch (sparksTableErr) {
  console.error('[DB Migration post_sparks_reactions]', sparksTableErr);
}

try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS message_reactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      emoji TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(message_id, user_id),
      FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_msg_reactions_msg ON message_reactions(message_id);
  `);
} catch (reactionsTableErr) {
  console.error('[DB Migration message_reactions]', reactionsTableErr);
}

// Seed official @botfather bot user if not present, and update avatar to latest official image
try {
  const botFather = db.prepare("SELECT id FROM users WHERE LOWER(username) = 'botfather'").get();
  if (!botFather) {
    db.prepare(`
      INSERT INTO users (phone, first_name, last_name, username, avatar, profile_completed, is_bot, description, verification)
      VALUES (?, ?, ?, ?, ?, 1, 1, ?, 'dev')
    `).run('+00000000000', 'BotFather', '', 'botfather', '/uploads/botfather.jpg', 'Official Portal Bot for creating and managing bots');
    console.log('[DB] BotFather seeded successfully');
  } else {
    db.prepare("UPDATE users SET avatar = '/uploads/botfather.jpg' WHERE LOWER(username) = 'botfather'").run();
    console.log('[DB] BotFather avatar updated to /uploads/botfather.jpg');
  }

  // Seed default verification badges for official Portal developer and verified accounts
  db.prepare(`
    UPDATE users 
    SET verification = 'dev' 
    WHERE LOWER(username) IN ('portal11', 'unix', 'artem', 'botfather') 
      AND (verification IS NULL OR verification = 'none' OR verification = '')
  `).run();

  db.prepare(`
    UPDATE users 
    SET verification = 'verified' 
    WHERE LOWER(username) IN ('telegram', 'elena') 
      AND (verification IS NULL OR verification = 'none' OR verification = '')
  `).run();
} catch (seedErr) {
  console.error('[DB Seed]', seedErr);
}

export const database = {
  getUserByPhone(phone) {
    if (!phone) return null;
    const stmt = db.prepare('SELECT * FROM users WHERE phone = ? OR email = ?');
    return stmt.get(phone, phone);
  },

  getUserByEmail(email) {
    if (!email) return null;
    const clean = email.trim().toLowerCase();
    const stmt = db.prepare('SELECT * FROM users WHERE LOWER(email) = ? OR LOWER(phone) = ?');
    return stmt.get(clean, clean);
  },

  createUserWithEmail(email, token) {
    const clean = email.trim().toLowerCase();
    const stmt = db.prepare('INSERT INTO users (email, phone, token, sparks) VALUES (?, NULL, ?, 250)');
    const result = stmt.run(clean, token);
    return this.getUserById(Number(result.lastInsertRowid));
  },

  // Persistent Auth Codes (Survives server restarts)
  saveAuthCode(identifier, code, expiresAt, sentAt) {
    const clean = identifier.trim().toLowerCase();
    db.prepare(`
      INSERT INTO auth_codes (identifier, code, expires_at, attempts, sent_at)
      VALUES (?, ?, ?, 0, ?)
      ON CONFLICT(identifier) DO UPDATE SET
        code = excluded.code,
        expires_at = excluded.expires_at,
        attempts = 0,
        sent_at = excluded.sent_at
    `).run(clean, code, expiresAt, sentAt);
  },

  getAuthCode(identifier) {
    const clean = identifier.trim().toLowerCase();
    return db.prepare('SELECT * FROM auth_codes WHERE identifier = ?').get(clean);
  },

  incrementAuthCodeAttempts(identifier) {
    const clean = identifier.trim().toLowerCase();
    db.prepare('UPDATE auth_codes SET attempts = attempts + 1 WHERE identifier = ?').run(clean);
  },

  deleteAuthCode(identifier) {
    const clean = identifier.trim().toLowerCase();
    db.prepare('DELETE FROM auth_codes WHERE identifier = ?').run(clean);
  },

  cleanupExpiredAuthCodes() {
    db.prepare('DELETE FROM auth_codes WHERE expires_at < ?').run(Date.now());
  },

  getUserByToken(token) {
    if (!token) return null;

    // 1. Check user_sessions table first
    try {
      const sessionStmt = db.prepare('SELECT id, user_id FROM user_sessions WHERE token = ?');
      const session = sessionStmt.get(token);
      if (session) {
        db.prepare("UPDATE user_sessions SET last_active_at = CURRENT_TIMESTAMP WHERE id = ?").run(session.id);
        const user = this.getUserById(session.user_id);
        if (user) {
          user.token = token;
          return user;
        }
      }
    } catch (_) {}

    // 2. Legacy fallback to users.token
    const stmt = db.prepare('SELECT * FROM users WHERE token = ?');
    const legacyUser = stmt.get(token);
    if (legacyUser) {
      try {
        db.prepare(`
          INSERT OR IGNORE INTO user_sessions (user_id, token, device_name, platform, browser, ip_address, location, last_active_at)
          VALUES (?, ?, 'Portal Web Desktop', 'Windows 11', 'Google Chrome', '178.62.204.15', 'Москва, Россия', CURRENT_TIMESTAMP)
        `).run(legacyUser.id, token);
      } catch (_) {}
    }
    return legacyUser;
  },

  createSession(userId, token, { deviceName, platform, browser, ipAddress, location } = {}) {
    if (!userId || !token) return null;
    try {
      const stmt = db.prepare(`
        INSERT INTO user_sessions (user_id, token, device_name, platform, browser, ip_address, location, created_at, last_active_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `);
      const res = stmt.run(
        userId,
        token,
        deviceName || 'Portal Web Desktop',
        platform || 'Windows 11',
        browser || 'Google Chrome',
        ipAddress || '178.62.204.15',
        location || 'Москва, Россия'
      );
      return res.lastInsertRowid;
    } catch (err) {
      console.error('[DB] createSession error:', err);
      return null;
    }
  },

  getUserSessions(userId, currentToken = '') {
    if (!userId) return [];

    // Check if user has any sessions in user_sessions
    try {
      const countRes = db.prepare('SELECT COUNT(*) as cnt FROM user_sessions WHERE user_id = ?').get(userId);
      if (!countRes || countRes.cnt === 0) {
        // Automatically seed current session and other realistic active device sessions
        const u = this.getUserById(userId);
        const currentTok = currentToken || u?.token || crypto.randomBytes(32).toString('hex');
        
        this.createSession(userId, currentTok, {
          deviceName: 'Portal Web Desktop',
          platform: 'Windows 11',
          browser: 'Google Chrome',
          ipAddress: '178.62.204.15',
          location: 'Москва, Россия'
        });

        // Additional active session: iPhone
        const iosTok = crypto.randomBytes(32).toString('hex');
        this.createSession(userId, iosTok, {
          deviceName: 'iPhone 15 Pro',
          platform: 'iOS 18.2',
          browser: 'Portal Mobile App',
          ipAddress: '85.140.2.89',
          location: 'Санкт-Петербург, Россия'
        });

        // Additional active session: MacBook
        const macTok = crypto.randomBytes(32).toString('hex');
        this.createSession(userId, macTok, {
          deviceName: 'MacBook Pro 16"',
          platform: 'macOS Sequoia',
          browser: 'Safari 18.1',
          ipAddress: '194.58.112.44',
          location: 'Алматы, Казахстан'
        });
      }
    } catch (seedErr) {
      console.error('[DB] session seed error:', seedErr);
    }

    try {
      const rows = db.prepare(`
        SELECT id, user_id, token, device_name, platform, browser, ip_address, location, created_at, last_active_at
        FROM user_sessions
        WHERE user_id = ?
        ORDER BY (CASE WHEN token = ? THEN 0 ELSE 1 END), datetime(last_active_at) DESC
      `).all(userId, currentToken || '');

      return rows.map(r => ({
        id: r.id,
        device_name: r.device_name,
        platform: r.platform,
        browser: r.browser,
        ip_address: r.ip_address,
        location: r.location,
        created_at: r.created_at,
        last_active_at: r.last_active_at,
        is_current: Boolean(currentToken && r.token === currentToken)
      }));
    } catch (err) {
      console.error('[DB] getUserSessions error:', err);
      return [];
    }
  },

  terminateSession(userId, sessionId, currentToken = '') {
    if (!userId || !sessionId) return null;
    try {
      const session = db.prepare('SELECT * FROM user_sessions WHERE id = ? AND user_id = ?').get(sessionId, userId);
      if (!session) return null;
      db.prepare('DELETE FROM user_sessions WHERE id = ? AND user_id = ?').run(sessionId, userId);
      return session;
    } catch (err) {
      console.error('[DB] terminateSession error:', err);
      return null;
    }
  },

  terminateAllOtherSessions(userId, currentToken = '') {
    if (!userId || !currentToken) return 0;
    try {
      const res = db.prepare('DELETE FROM user_sessions WHERE user_id = ? AND token != ?').run(userId, currentToken);
      return res.changes;
    } catch (err) {
      console.error('[DB] terminateAllOtherSessions error:', err);
      return 0;
    }
  },

  getUserSecondaryUsernames(userId) {
    if (!userId) return [];
    try {
      const rows = db.prepare('SELECT username FROM user_secondary_usernames WHERE user_id = ? ORDER BY id ASC').all(userId);
      return rows.map(r => r.username);
    } catch (e) {
      return [];
    }
  },

  addSecondaryUsername(userId, username) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    if (!cleanUsername) throw new Error('Некорректный username');
    if (!this.isUsernameAvailable(cleanUsername)) {
      throw new Error(`Username @${cleanUsername} уже занят`);
    }
    db.prepare('INSERT INTO user_secondary_usernames (user_id, username) VALUES (?, ?)').run(userId, cleanUsername);
    return this.getUserById(userId);
  },

  removeSecondaryUsername(userId, username) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    db.prepare('DELETE FROM user_secondary_usernames WHERE user_id = ? AND LOWER(username) = ?').run(userId, cleanUsername);
    return this.getUserById(userId);
  },

  updateUserLastSeen(userId, lastSeenDate = null) {
    if (!userId) return;
    const ts = lastSeenDate || new Date().toISOString();
    try {
      db.prepare('UPDATE users SET last_seen = ? WHERE id = ?').run(ts, userId);
    } catch (e) {
      console.error('[DB] updateUserLastSeen error:', e);
    }
  },

  getUserContactPartnerIds(userId) {
    if (!userId) return [];
    try {
      const rows = db.prepare(`
        SELECT DISTINCT other_cp.user_id
        FROM chat_participants my_cp
        JOIN chats c ON c.id = my_cp.chat_id AND COALESCE(c.is_channel, 0) = 0 AND COALESCE(c.is_group, 0) = 0
        JOIN chat_participants other_cp ON other_cp.chat_id = c.id AND other_cp.user_id != my_cp.user_id
        WHERE my_cp.user_id = ?
      `).all(userId);
      return rows.map(r => r.user_id);
    } catch (e) {
      console.error('[DB] getUserContactPartnerIds error:', e);
      return [];
    }
  },

  getUserById(id) {
    const stmt = db.prepare("SELECT id, email, CASE WHEN is_bot = 1 THEN NULL ELSE phone END as phone, first_name, last_name, username, avatar, profile_completed, created_at, last_seen, is_bot, bot_owner_id, bot_token, description, COALESCE(sparks, 250) as sparks, COALESCE(artifacts, 0) as artifacts, COALESCE(verification, 'none') as verification, COALESCE(is_frozen, 0) as is_frozen, COALESCE(frozen_reason, '') as frozen_reason, COALESCE(frozen_until, '') as frozen_until, COALESCE(is_premium, 0) as is_premium, COALESCE(premium_since, '') as premium_since, COALESCE(premium_until, '') as premium_until, COALESCE(has_cloud_password, 0) as has_cloud_password, COALESCE(cloud_password_hint, '') as cloud_password_hint, COALESCE(has_passcode, 0) as has_passcode, COALESCE(banner_url, '') as banner_url, pinned_channel_id, COALESCE(privacy_messages, 'all') as privacy_messages, COALESCE(privacy_messages_sparks_price, 1) as privacy_messages_sparks_price, COALESCE(privacy_phone, 'all') as privacy_phone, COALESCE(privacy_last_seen, 'all') as privacy_last_seen, COALESCE(name_font, 'default') as name_font, COALESCE(status_font, 'default') as status_font, COALESCE(custom_activity_status, '') as custom_activity_status, COALESCE(is_admin, 0) as is_admin FROM users WHERE id = ?");
    const user = stmt.get(id);
    if (!user) return null;
    user.secondary_usernames = this.getUserSecondaryUsernames(id);
    return user;
  },

  updateUserCustomization(userId, { name_font, status_font, custom_activity_status }) {
    const currentUser = this.getUserById(userId);
    const validNameFont = name_font !== undefined ? name_font : (currentUser?.name_font || 'default');
    const validStatusFont = status_font !== undefined ? status_font : (currentUser?.status_font || 'default');
    const validActivityStatus = custom_activity_status !== undefined ? String(custom_activity_status).trim().slice(0, 60) : (currentUser?.custom_activity_status || '');

    db.prepare(`
      UPDATE users 
      SET name_font = ?, status_font = ?, custom_activity_status = ? 
      WHERE id = ?
    `).run(validNameFont, validStatusFont, validActivityStatus, userId);
    return this.getUserById(userId);
  },

  updateUserPrivacy(userId, { privacy_messages, privacy_messages_sparks_price, privacy_phone, privacy_last_seen }) {
    const validMessages = ['all', 'contacts', 'nobody', 'sparks'];
    const validPhone = ['all', 'contacts', 'nobody'];
    const validLastSeen = ['all', 'contacts', 'nobody'];
    const pMessages = validMessages.includes(privacy_messages) ? privacy_messages : 'all';
    const pPrice = Math.max(1, Math.min(10000, Number(privacy_messages_sparks_price) || 1));
    const pPhone = validPhone.includes(privacy_phone) ? privacy_phone : 'all';
    const pLastSeen = validLastSeen.includes(privacy_last_seen) ? privacy_last_seen : 'all';

    db.prepare(`
      UPDATE users 
      SET privacy_messages = ?, privacy_messages_sparks_price = ?, privacy_phone = ?, privacy_last_seen = ?
      WHERE id = ?
    `).run(pMessages, pPrice, pPhone, pLastSeen, userId);

    return this.getUserById(userId);
  },

  transferSparks(fromUserId, toUserId, amount) {
    const amt = Math.max(1, Math.floor(Number(amount) || 1));
    const deduct = db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) - ? WHERE id = ?');
    const add = db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) + ? WHERE id = ?');
    const tx = db.transaction((from, to, a) => {
      deduct.run(a, from);
      add.run(a, to);
    });
    tx(fromUserId, toUserId, amt);
    const updatedSender = db.prepare('SELECT sparks FROM users WHERE id = ?').get(fromUserId);
    const updatedRecipient = db.prepare('SELECT sparks FROM users WHERE id = ?').get(toUserId);
    return {
      senderSparks: Number(updatedSender?.sparks ?? 0),
      recipientSparks: Number(updatedRecipient?.sparks ?? 0)
    };
  },

  setCloudPassword(userId, password, hint = '') {
    if (!password || typeof password !== 'string' || password.length < 4) {
      throw new Error('Пароль должен содержать минимум 4 символа');
    }
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(password, salt, 64).toString('hex');
    const cleanHint = (hint || '').trim().slice(0, 100);

    db.prepare(`
      UPDATE users 
      SET has_cloud_password = 1, cloud_password_hash = ?, cloud_password_salt = ?, cloud_password_hint = ?
      WHERE id = ?
    `).run(hash, salt, cleanHint, userId);

    return this.getUserById(userId);
  },

  verifyCloudPassword(userId, password) {
    if (!userId || !password) return false;
    const userRow = db.prepare('SELECT cloud_password_hash, cloud_password_salt, has_cloud_password FROM users WHERE id = ?').get(userId);
    if (!userRow || !userRow.has_cloud_password || !userRow.cloud_password_hash || !userRow.cloud_password_salt) {
      return false;
    }
    try {
      const calculatedHash = crypto.scryptSync(password, userRow.cloud_password_salt, 64).toString('hex');
      return crypto.timingSafeEqual(Buffer.from(userRow.cloud_password_hash, 'hex'), Buffer.from(calculatedHash, 'hex'));
    } catch (err) {
      console.error('[DB] verifyCloudPassword error:', err);
      return false;
    }
  },

  removeCloudPassword(userId, currentPassword) {
    const isCorrect = this.verifyCloudPassword(userId, currentPassword);
    if (!isCorrect) {
      throw new Error('Неверный текущий облачный пароль');
    }
    db.prepare(`
      UPDATE users 
      SET has_cloud_password = 0, cloud_password_hash = '', cloud_password_salt = '', cloud_password_hint = ''
      WHERE id = ?
    `).run(userId);
    return this.getUserById(userId);
  },

  changeCloudPassword(userId, currentPassword, newPassword, newHint = '') {
    const isCorrect = this.verifyCloudPassword(userId, currentPassword);
    if (!isCorrect) {
      throw new Error('Неверный текущий облачный пароль');
    }
    return this.setCloudPassword(userId, newPassword, newHint);
  },

  setPasscode(userId, passcode) {
    if (!passcode || typeof passcode !== 'string' || passcode.trim().length < 4) {
      throw new Error('Код-пароль должен содержать минимум 4 символа');
    }
    const cleanPasscode = passcode.trim();
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(cleanPasscode, salt, 64).toString('hex');

    db.prepare(`
      UPDATE users 
      SET has_passcode = 1, passcode_hash = ?, passcode_salt = ?
      WHERE id = ?
    `).run(hash, salt, userId);

    return this.getUserById(userId);
  },

  verifyPasscode(userId, passcode) {
    if (!userId || !passcode) return false;
    const userRow = db.prepare('SELECT passcode_hash, passcode_salt, has_passcode FROM users WHERE id = ?').get(userId);
    if (!userRow || !userRow.has_passcode || !userRow.passcode_hash || !userRow.passcode_salt) {
      return false;
    }
    try {
      const calculatedHash = crypto.scryptSync(String(passcode).trim(), userRow.passcode_salt, 64).toString('hex');
      return crypto.timingSafeEqual(Buffer.from(userRow.passcode_hash, 'hex'), Buffer.from(calculatedHash, 'hex'));
    } catch (err) {
      console.error('[DB] verifyPasscode error:', err);
      return false;
    }
  },

  removePasscode(userId, currentPasscode) {
    const isCorrect = this.verifyPasscode(userId, currentPasscode);
    if (!isCorrect) {
      throw new Error('Неверный текущий код-пароль');
    }
    db.prepare(`
      UPDATE users 
      SET has_passcode = 0, passcode_hash = '', passcode_salt = ''
      WHERE id = ?
    `).run(userId);
    return this.getUserById(userId);
  },

  changePasscode(userId, currentPasscode, newPasscode) {
    const isCorrect = this.verifyPasscode(userId, currentPasscode);
    if (!isCorrect) {
      throw new Error('Неверный текущий код-пароль');
    }
    return this.setPasscode(userId, newPasscode);
  },

  subscribePremium(userId, cost = 1500) {
    const user = this.getUserById(userId);
    if (!user) {
      throw new Error('Пользователь не найден');
    }
    const currentSparks = Number(user.sparks ?? 0);
    if (currentSparks < cost) {
      throw new Error(`Недостаточно Sparks для активации Portal Premium. Требуется ${cost.toLocaleString('ru-RU')} Sparks, у вас на балансе: ${currentSparks.toLocaleString('ru-RU')} Sparks.`);
    }

    const now = new Date();
    let untilDate = new Date();
    // If user already has an active premium subscription, extend from existing expiration
    if (user.is_premium && user.premium_until) {
      const currentUntil = new Date(user.premium_until);
      if (currentUntil > now) {
        untilDate = currentUntil;
      }
    }
    untilDate.setDate(untilDate.getDate() + 30);

    const premiumSince = user.premium_since && user.is_premium ? user.premium_since : now.toISOString();
    const premiumUntil = untilDate.toISOString();

    // Deduct sparks
    db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) - ? WHERE id = ?').run(cost, userId);
    // Activate premium and grant 3 artifacts
    db.prepare('UPDATE users SET is_premium = 1, premium_since = ?, premium_until = ?, artifacts = COALESCE(artifacts, 0) + 3 WHERE id = ?').run(
      premiumSince,
      premiumUntil,
      userId
    );

    return this.getUserById(userId);
  },

  setUserPremium(userId, isPremium, durationDays = 30) {
    if (isPremium) {
      const now = new Date();
      const untilDate = new Date();
      untilDate.setDate(untilDate.getDate() + durationDays);
      db.prepare('UPDATE users SET is_premium = 1, premium_since = ?, premium_until = ?, artifacts = COALESCE(artifacts, 0) + 3 WHERE id = ?').run(
        now.toISOString(),
        untilDate.toISOString(),
        userId
      );
    } else {
      db.prepare('UPDATE users SET is_premium = 0, premium_until = ? WHERE id = ?').run(
        '',
        userId
      );
    }
    return this.getUserById(userId);
  },

  setUserFrozen(userId, isFrozen, reason = '', until = '') {
    db.prepare('UPDATE users SET is_frozen = ?, frozen_reason = ?, frozen_until = ? WHERE id = ?').run(isFrozen ? 1 : 0, reason, until, userId);
    return this.getUserById(userId);
  },

  setUserVerification(userId, verification) {
    const valid = ['dev', 'verified', 'artist', 'none'].includes(verification) ? verification : 'none';
    db.prepare('UPDATE users SET verification = ? WHERE id = ?').run(valid, userId);
    try {
      db.exec("PRAGMA wal_checkpoint(FULL);");
    } catch (_) {}
    return this.getUserById(userId);
  },

  setChannelVerification(channelId, verification) {
    const valid = ['dev', 'verified', 'artist', 'none'].includes(verification) ? verification : 'none';
    db.prepare('UPDATE channels SET verification = ? WHERE id = ?').run(valid, channelId);
    try {
      db.exec("PRAGMA wal_checkpoint(FULL);");
    } catch (_) {}
  },

  addSparks(userId, amount) {
    db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) + ? WHERE id = ?').run(amount, userId);
    return this.getUserById(userId);
  },

  adminSetUserSparks(userId, action, amount) {
    const val = Math.max(0, Math.floor(Number(amount) || 0));
    if (action === 'set') {
      db.prepare('UPDATE users SET sparks = ? WHERE id = ?').run(val, userId);
    } else if (action === 'deduct') {
      db.prepare('UPDATE users SET sparks = MAX(0, COALESCE(sparks, 250) - ?) WHERE id = ?').run(val, userId);
    } else {
      db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) + ? WHERE id = ?').run(val, userId);
    }
    return this.getUserById(userId);
  },

  adminSetUserPremium(userId, isPremium, durationMonths = 1, isLifetime = false) {
    if (isPremium) {
      const now = new Date();
      const until = isLifetime 
        ? '2099-12-31T23:59:59.000Z'
        : new Date(now.getTime() + Number(durationMonths || 1) * 30 * 86400000).toISOString();
      db.prepare('UPDATE users SET is_premium = 1, premium_since = ?, premium_until = ? WHERE id = ?').run(now.toISOString(), until, userId);
    } else {
      db.prepare('UPDATE users SET is_premium = 0, premium_since = \'\', premium_until = \'\' WHERE id = ?').run(userId);
    }
    return this.getUserById(userId);
  },

  getAdminStats() {
    const totalUsers = db.prepare('SELECT COUNT(*) as count FROM users WHERE COALESCE(is_bot, 0) = 0').get()?.count || 0;
    const premiumUsers = db.prepare('SELECT COUNT(*) as count FROM users WHERE is_premium = 1').get()?.count || 0;
    const frozenUsers = db.prepare('SELECT COUNT(*) as count FROM users WHERE is_frozen = 1').get()?.count || 0;
    const totalMessages = db.prepare('SELECT COUNT(*) as count FROM messages').get()?.count || 0;
    const totalChats = db.prepare('SELECT COUNT(*) as count FROM chats').get()?.count || 0;
    return {
      totalUsers,
      premiumUsers,
      frozenUsers,
      totalMessages,
      totalChats
    };
  },

  getAdminUsersList({ query = '', filter = 'all', limit = 50, offset = 0 }) {
    const cleanQ = (query || '').trim().toLowerCase();
    const cleanFilter = filter || 'all';
    
    let whereClause = "1=1";
    const params = [];

    if (cleanFilter === 'frozen') {
      whereClause += " AND is_frozen = 1";
    } else if (cleanFilter === 'premium') {
      whereClause += " AND is_premium = 1";
    } else if (cleanFilter === 'verified') {
      whereClause += " AND verification IN ('dev', 'verified')";
    } else if (cleanFilter === 'bots') {
      whereClause += " AND is_bot = 1";
    }

    if (cleanQ) {
      whereClause += " AND (LOWER(COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')) LIKE ? OR LOWER(COALESCE(username, '')) LIKE ? OR COALESCE(phone, '') LIKE ? OR CAST(id AS TEXT) = ?)";
      params.push(`%${cleanQ}%`, `%${cleanQ}%`, `%${cleanQ}%`, cleanQ);
    }

    const totalRow = db.prepare(`SELECT COUNT(*) as count FROM users WHERE ${whereClause}`).get(...params);
    const total = totalRow?.count || 0;

    const listParams = [...params, Number(limit) || 50, Number(offset) || 0];
    const users = db.prepare(`
      SELECT id, CASE WHEN is_bot = 1 THEN NULL ELSE phone END as phone,
             first_name, last_name, username, avatar, created_at, last_seen, is_bot,
             COALESCE(sparks, 250) as sparks,
             COALESCE(verification, 'none') as verification,
             COALESCE(is_frozen, 0) as is_frozen,
             COALESCE(frozen_reason, '') as frozen_reason,
             COALESCE(frozen_until, '') as frozen_until,
             COALESCE(is_premium, 0) as is_premium,
             COALESCE(premium_since, '') as premium_since,
             COALESCE(premium_until, '') as premium_until,
             COALESCE(is_admin, 0) as is_admin
      FROM users
      WHERE ${whereClause}
      ORDER BY id ASC
      LIMIT ? OFFSET ?
    `).all(...listParams);

    return { users, total };
  },

  createUser(phone, token) {
    const stmt = db.prepare('INSERT INTO users (phone, token, sparks) VALUES (?, ?, 250)');
    const result = stmt.run(phone, token);
    return this.getUserById(Number(result.lastInsertRowid));
  },

  updateToken(userId, token) {
    const stmt = db.prepare('UPDATE users SET token = ? WHERE id = ?');
    stmt.run(token, userId);
  },

  updateUserProfile(userId, { firstName, lastName, username, avatar, description, pinnedChannelId }) {
    const cleanUsername = username ? username.trim().toLowerCase().replace(/^@+/, '') : null;
    if (pinnedChannelId !== undefined) {
      const validPinnedId = (pinnedChannelId !== null && pinnedChannelId !== '' && pinnedChannelId !== 0 && pinnedChannelId !== 'null')
        ? Number(pinnedChannelId)
        : null;
      const stmt = db.prepare(`
        UPDATE users 
        SET first_name = ?, last_name = ?, username = ?, avatar = ?, description = COALESCE(?, description), pinned_channel_id = ?, profile_completed = 1, last_seen = CURRENT_TIMESTAMP
        WHERE id = ?
      `);
      stmt.run(firstName.trim(), lastName.trim(), cleanUsername, avatar || '', description !== undefined ? description.trim() : null, validPinnedId, userId);
    } else {
      const stmt = db.prepare(`
        UPDATE users 
        SET first_name = ?, last_name = ?, username = ?, avatar = ?, description = COALESCE(?, description), profile_completed = 1, last_seen = CURRENT_TIMESTAMP
        WHERE id = ?
      `);
      stmt.run(firstName.trim(), lastName.trim(), cleanUsername, avatar || '', description !== undefined ? description.trim() : null, userId);
    }
    return this.getUserById(userId);
  },

  updateUserPinnedChannel(userId, channelId) {
    const validId = (channelId !== null && channelId !== undefined && channelId !== '' && channelId !== 0 && channelId !== 'null') 
      ? Number(channelId) 
      : null;
    db.prepare('UPDATE users SET pinned_channel_id = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ?').run(validId, userId);
    return this.getUserById(userId);
  },

  updateUserAvatar(userId, avatarUrl) {
    db.prepare('UPDATE users SET avatar = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ?').run(avatarUrl || '', userId);
    return this.getUserById(userId);
  },

  updateUserBanner(userId, bannerUrl) {
    const user = this.getUserById(userId);
    if (!user) throw new Error('Пользователь не найден');
    if (!user.is_premium) {
      throw new Error('Установка баннера доступна только с подпиской Portal Premium');
    }
    db.prepare('UPDATE users SET banner_url = ? WHERE id = ?').run(bannerUrl ? bannerUrl.trim() : '', userId);
    return this.getUserById(userId);
  },

  isUsernameAvailable(username, excludeUserId = null, excludeChannelId = null) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    if (!cleanUsername) return false;
    
    // Check primary usernames in users table
    let userRow;
    if (excludeUserId) {
      userRow = db.prepare('SELECT id FROM users WHERE LOWER(username) = ? AND id != ?').get(cleanUsername, excludeUserId);
    } else {
      userRow = db.prepare('SELECT id FROM users WHERE LOWER(username) = ?').get(cleanUsername);
    }
    if (userRow) return false;

    // Check secondary usernames table
    let secondaryRow;
    if (excludeUserId) {
      secondaryRow = db.prepare('SELECT id FROM user_secondary_usernames WHERE LOWER(username) = ? AND user_id != ?').get(cleanUsername, excludeUserId);
    } else {
      secondaryRow = db.prepare('SELECT id FROM user_secondary_usernames WHERE LOWER(username) = ?').get(cleanUsername);
    }
    if (secondaryRow) return false;

    // Check channels table
    let channelRow;
    if (excludeChannelId) {
      channelRow = db.prepare('SELECT id FROM channels WHERE LOWER(username) = ? AND id != ?').get(cleanUsername, excludeChannelId);
    } else {
      channelRow = db.prepare('SELECT id FROM channels WHERE LOWER(username) = ?').get(cleanUsername);
    }
    if (channelRow) return false;

    return true;
  },

  searchUsers(query, currentUserId) {
    const cleanQuery = (query || '').trim().toLowerCase().replace(/^@+/, '');
    if (!cleanQuery) return [];

    const safeUserId = (currentUserId !== undefined && currentUserId !== null) ? Number(currentUserId) : null;
    const likePattern = `%${cleanQuery}%`;

    // 1. Search channels
    const channelStmt = db.prepare(`
      SELECT 
        ch.chat_id as id,
        ch.chat_id as chat_id,
        ch.title as first_name,
        '' as last_name,
        ch.username,
        ch.avatar,
        0 as is_bot,
        1 as is_channel,
        ch.owner_id,
        ch.description,
        COALESCE(ch.verification, 'none') as verification,
        0 as is_premium,
        NULL as pinned_channel_id,
        (SELECT COUNT(*) FROM chat_participants WHERE chat_id = ch.chat_id) as subscribers_count,
        EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = ch.chat_id AND user_id = ?) as is_subscribed,
        '[]' as secondary_usernames_json
      FROM channels ch
      WHERE LOWER(COALESCE(ch.username, '')) LIKE ? OR LOWER(COALESCE(ch.title, '')) LIKE ? OR LOWER(COALESCE(ch.description, '')) LIKE ?
      LIMIT 15
    `);
    const channels = channelStmt.all(safeUserId, likePattern, likePattern, likePattern).map(ch => ({
      ...ch,
      secondary_usernames: []
    }));

    // 2. Search groups
    const groupStmt = db.prepare(`
      SELECT 
        g.chat_id as id,
        g.chat_id as chat_id,
        g.title as first_name,
        '' as last_name,
        g.invite_code as username,
        g.avatar,
        0 as is_bot,
        0 as is_channel,
        1 as is_group,
        g.invite_code,
        g.owner_id,
        g.description,
        'none' as verification,
        0 as is_premium,
        NULL as pinned_channel_id,
        (SELECT COUNT(*) FROM chat_participants WHERE chat_id = g.chat_id) as subscribers_count,
        (SELECT COUNT(*) FROM chat_participants WHERE chat_id = g.chat_id) as members_count,
        EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = g.chat_id AND user_id = ?) as is_subscribed,
        '[]' as secondary_usernames_json
      FROM groups g
      WHERE LOWER(COALESCE(g.title, '')) LIKE ? OR LOWER(COALESCE(g.description, '')) LIKE ? OR LOWER(COALESCE(g.invite_code, '')) LIKE ?
      LIMIT 15
    `);
    const groups = groupStmt.all(safeUserId, likePattern, likePattern, likePattern).map(g => ({
      ...g,
      secondary_usernames: []
    }));

    // 3. Search users & bots (by primary username, secondary usernames, first/last name, or description)
    const userStmt = db.prepare(`
      SELECT 
        u.id, 
        u.first_name, 
        u.last_name, 
        u.username, 
        u.avatar, 
        u.last_seen,
        u.is_bot, 
        0 as is_channel, 
        u.description,
        COALESCE(u.verification, 'none') as verification,
        COALESCE(u.is_premium, 0) as is_premium,
        COALESCE(u.banner_url, '') as banner_url,
        u.pinned_channel_id as pinned_channel_id,
        COALESCE(u.name_font, 'default') as name_font,
        COALESCE(u.status_font, 'default') as status_font,
        COALESCE(u.custom_activity_status, '') as custom_activity_status,
        (
          SELECT json_group_array(s.username) 
          FROM user_secondary_usernames s 
          WHERE s.user_id = u.id
        ) as secondary_usernames_json
      FROM users u
      WHERE (u.id != COALESCE(?, -1)) AND (COALESCE(u.profile_completed, 0) = 1 OR COALESCE(u.is_bot, 0) = 1) AND (
        LOWER(COALESCE(u.username, '')) LIKE ? OR 
        LOWER(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) LIKE ? OR
        LOWER(COALESCE(u.description, '')) LIKE ? OR
        EXISTS (
          SELECT 1 FROM user_secondary_usernames su 
          WHERE su.user_id = u.id AND LOWER(su.username) LIKE ?
        )
      )
      LIMIT 25
    `);
    const users = userStmt.all(safeUserId, likePattern, likePattern, likePattern, likePattern).map(u => {
      let secondary_usernames = [];
      try {
        secondary_usernames = JSON.parse(u.secondary_usernames_json || '[]') || [];
      } catch (e) {
        secondary_usernames = [];
      }
      return {
        ...u,
        secondary_usernames
      };
    });

    return [...channels, ...groups, ...users];
  },

  getOrCreateDirectChat(user1Id, user2Id) {
    // Check if a direct chat between these two users already exists
    const findChatStmt = db.prepare(`
      SELECT cp1.chat_id 
      FROM chat_participants cp1
      JOIN chat_participants cp2 ON cp1.chat_id = cp2.chat_id
      JOIN chats c ON c.id = cp1.chat_id
      WHERE cp1.user_id = ? AND cp2.user_id = ? AND COALESCE(c.is_channel, 0) = 0 AND COALESCE(c.is_group, 0) = 0
      LIMIT 1
    `);
    const existing = findChatStmt.get(user1Id, user2Id);
    if (existing) {
      return existing.chat_id;
    }

    // Create new chat
    const insertChatStmt = db.prepare('INSERT INTO chats (is_channel, created_at, updated_at) VALUES (0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)');
    const chatResult = insertChatStmt.run();
    const chatId = Number(chatResult.lastInsertRowid);

    const insertPartStmt = db.prepare('INSERT INTO chat_participants (chat_id, user_id) VALUES (?, ?)');
    insertPartStmt.run(chatId, user1Id);
    insertPartStmt.run(chatId, user2Id);

    return chatId;
  },

  getOrCreateSavedChat(userId) {
    if (!userId) return null;
    try {
      const existing = db.prepare(`
        SELECT c.id FROM chats c
        JOIN chat_participants cp ON cp.chat_id = c.id
        WHERE cp.user_id = ? AND c.is_saved = 1
        LIMIT 1
      `).get(userId);

      if (existing) {
        return existing.id;
      }

      const insertChatStmt = db.prepare('INSERT INTO chats (is_saved, is_channel, is_group, created_at, updated_at) VALUES (1, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)');
      const chatResult = insertChatStmt.run();
      const chatId = Number(chatResult.lastInsertRowid);

      db.prepare('INSERT OR IGNORE INTO chat_participants (chat_id, user_id) VALUES (?, ?)').run(chatId, userId);
      return chatId;
    } catch (savedErr) {
      console.warn('[DB] getOrCreateSavedChat error:', savedErr);
      return null;
    }
  },

  getUserChats(userId) {
    if (!userId) return [];
    try {
      this.getOrCreateSavedChat(userId);
    } catch (_) {}
    // Get all direct chats, channels, groups, and saved chat where userId is a participant, along with details and unread count
    const stmt = db.prepare(`
      SELECT * FROM (
        SELECT 
          c.id as chat_id,
          c.updated_at,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          COALESCE(my_cp.is_pinned, 0) as is_pinned,
          my_cp.pinned_at as pinned_at,
          u.id as participant_id,
          u.first_name,
          u.last_name,
          u.username,
          u.avatar,
          CASE WHEN u.is_bot = 1 THEN NULL ELSE u.phone END as phone,
          u.last_seen,
          u.is_bot,
          0 as is_channel,
          0 as is_group,
          0 as is_saved,
          NULL as invite_code,
          NULL as owner_id,
          0 as subscribers_count,
          0 as members_count,
          1 as is_subscribed,
          u.description,
          COALESCE(u.verification, 'none') as verification,
          COALESCE(u.is_premium, 0) as is_premium,
          COALESCE(u.banner_url, '') as banner_url,
          0 as artifacts,
          u.pinned_channel_id as pinned_channel_id,
          COALESCE(u.privacy_messages, 'all') as privacy_messages,
          COALESCE(u.privacy_messages_sparks_price, 1) as privacy_messages_sparks_price,
          COALESCE(u.privacy_phone, 'all') as privacy_phone,
          COALESCE(u.privacy_last_seen, 'all') as privacy_last_seen,
          COALESCE(u.name_font, 'default') as name_font,
          COALESCE(u.status_font, 'default') as status_font,
          COALESCE(u.custom_activity_status, '') as custom_activity_status,
          (
            SELECT json_group_array(s.username) 
            FROM user_secondary_usernames s 
            WHERE s.user_id = u.id
          ) as secondary_usernames_json,
          m.id as last_message_id,
          m.text as last_message_text,
          m.created_at as last_message_time,
          m.sender_id as last_message_sender_id,
          (
            SELECT COUNT(*) 
            FROM messages unread_m 
            WHERE unread_m.chat_id = c.id 
              AND unread_m.sender_id != my_cp.user_id 
              AND unread_m.is_read = 0
          ) as unread_count
        FROM chat_participants my_cp
        JOIN chats c ON c.id = my_cp.chat_id AND COALESCE(c.is_channel, 0) = 0 AND COALESCE(c.is_group, 0) = 0 AND COALESCE(c.is_saved, 0) = 0
        JOIN chat_participants other_cp ON other_cp.chat_id = c.id AND other_cp.user_id != my_cp.user_id
        JOIN users u ON u.id = other_cp.user_id
        LEFT JOIN messages m ON m.id = (
          SELECT id FROM messages 
          WHERE chat_id = c.id 
          ORDER BY id DESC LIMIT 1
        )
        WHERE my_cp.user_id = ?

        UNION ALL

        SELECT 
          c.id as chat_id,
          c.updated_at,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          COALESCE(my_cp.is_pinned, 0) as is_pinned,
          my_cp.pinned_at as pinned_at,
          ch.owner_id as participant_id,
          ch.title as first_name,
          '' as last_name,
          ch.username,
          ch.avatar,
          NULL as phone,
          c.updated_at as last_seen,
          0 as is_bot,
          1 as is_channel,
          0 as is_group,
          0 as is_saved,
          NULL as invite_code,
          ch.owner_id,
          (SELECT COUNT(*) FROM chat_participants WHERE chat_id = c.id) as subscribers_count,
          0 as members_count,
          1 as is_subscribed,
          ch.description,
          COALESCE(ch.verification, 'none') as verification,
          0 as is_premium,
          '' as banner_url,
          COALESCE(ch.artifacts, 0) as artifacts,
          NULL as pinned_channel_id,
          'all' as privacy_messages,
          0 as privacy_messages_sparks_price,
          'all' as privacy_phone,
          'all' as privacy_last_seen,
          'default' as name_font,
          'default' as status_font,
          '' as custom_activity_status,
          '[]' as secondary_usernames_json,
          m.id as last_message_id,
          m.text as last_message_text,
          m.created_at as last_message_time,
          m.sender_id as last_message_sender_id,
          (
            SELECT COUNT(*) 
            FROM messages unread_m 
            WHERE unread_m.chat_id = c.id 
              AND unread_m.sender_id != my_cp.user_id 
              AND unread_m.is_read = 0
          ) as unread_count
        FROM chat_participants my_cp
        JOIN chats c ON c.id = my_cp.chat_id AND c.is_channel = 1
        JOIN channels ch ON ch.chat_id = c.id
        LEFT JOIN messages m ON m.id = (
          SELECT id FROM messages 
          WHERE chat_id = c.id 
          ORDER BY id DESC LIMIT 1
        )
        WHERE my_cp.user_id = ?

        UNION ALL

        SELECT 
          c.id as chat_id,
          c.updated_at,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          COALESCE(my_cp.is_pinned, 0) as is_pinned,
          my_cp.pinned_at as pinned_at,
          g.owner_id as participant_id,
          g.title as first_name,
          '' as last_name,
          g.invite_code as username,
          g.avatar,
          NULL as phone,
          c.updated_at as last_seen,
          0 as is_bot,
          0 as is_channel,
          1 as is_group,
          0 as is_saved,
          g.invite_code,
          g.owner_id,
          0 as subscribers_count,
          (SELECT COUNT(*) FROM chat_participants WHERE chat_id = c.id) as members_count,
          1 as is_subscribed,
          g.description,
          'none' as verification,
          0 as is_premium,
          '' as banner_url,
          0 as artifacts,
          NULL as pinned_channel_id,
          'all' as privacy_messages,
          0 as privacy_messages_sparks_price,
          'all' as privacy_phone,
          'all' as privacy_last_seen,
          'default' as name_font,
          'default' as status_font,
          '' as custom_activity_status,
          '[]' as secondary_usernames_json,
          m.id as last_message_id,
          m.text as last_message_text,
          m.created_at as last_message_time,
          m.sender_id as last_message_sender_id,
          (
            SELECT COUNT(*) 
            FROM messages unread_m 
            WHERE unread_m.chat_id = c.id 
              AND unread_m.sender_id != my_cp.user_id 
              AND unread_m.is_read = 0
          ) as unread_count
        FROM chat_participants my_cp
        JOIN chats c ON c.id = my_cp.chat_id AND c.is_group = 1
        JOIN groups g ON g.chat_id = c.id
        LEFT JOIN messages m ON m.id = (
          SELECT id FROM messages 
          WHERE chat_id = c.id 
          ORDER BY id DESC LIMIT 1
        )
        WHERE my_cp.user_id = ?

        UNION ALL

        SELECT 
          c.id as chat_id,
          c.updated_at,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          COALESCE(my_cp.is_pinned, 0) as is_pinned,
          my_cp.pinned_at as pinned_at,
          my_cp.user_id as participant_id,
          'Избранное' as first_name,
          '' as last_name,
          'saved' as username,
          '' as avatar,
          NULL as phone,
          c.updated_at as last_seen,
          0 as is_bot,
          0 as is_channel,
          0 as is_group,
          1 as is_saved,
          NULL as invite_code,
          my_cp.user_id as owner_id,
          0 as subscribers_count,
          0 as members_count,
          1 as is_subscribed,
          'Ваши личные сообщения и заметки' as description,
          'none' as verification,
          0 as is_premium,
          '' as banner_url,
          0 as artifacts,
          NULL as pinned_channel_id,
          'all' as privacy_messages,
          0 as privacy_messages_sparks_price,
          'all' as privacy_phone,
          'all' as privacy_last_seen,
          'default' as name_font,
          'default' as status_font,
          '' as custom_activity_status,
          '[]' as secondary_usernames_json,
          m.id as last_message_id,
          m.text as last_message_text,
          m.created_at as last_message_time,
          m.sender_id as last_message_sender_id,
          0 as unread_count
        FROM chat_participants my_cp
        JOIN chats c ON c.id = my_cp.chat_id AND c.is_saved = 1
        LEFT JOIN messages m ON m.id = (
          SELECT id FROM messages 
          WHERE chat_id = c.id 
          ORDER BY id DESC LIMIT 1
        )
        WHERE my_cp.user_id = ?
      )
      ORDER BY 
        is_pinned DESC,
        CASE WHEN is_pinned = 1 THEN pinned_at END DESC,
        COALESCE(last_message_time, updated_at) DESC
    `);
    return stmt.all(userId, userId, userId, userId).map(chat => {
      let secondary_usernames = [];
      try {
        secondary_usernames = JSON.parse(chat.secondary_usernames_json || '[]') || [];
      } catch (e) {
        secondary_usernames = [];
      }
      const item = {
        ...chat,
        id: chat.chat_id,
        secondary_usernames
      };

      if (!item.is_channel && !item.is_group && !item.is_bot && item.participant_id) {
        // Enforce privacy_last_seen
        let canSeeActivity = true;
        if (item.privacy_last_seen === 'nobody') {
          canSeeActivity = false;
        } else if (item.privacy_last_seen === 'contacts') {
          const partnerContacts = this.getUserContactPartnerIds(item.participant_id);
          if (!partnerContacts.includes(userId)) {
            canSeeActivity = false;
          }
        }
        if (!canSeeActivity) {
          item.is_online = 0;
          item.last_seen = null;
          item.is_activity_hidden = 1;
        }

        // Enforce privacy_phone
        if (item.privacy_phone === 'nobody') {
          item.phone = null;
        } else if (item.privacy_phone === 'contacts') {
          const partnerContacts = this.getUserContactPartnerIds(item.participant_id);
          if (!partnerContacts.includes(userId)) {
            item.phone = null;
          }
        }
        // Enforce can_send_messages
        if (item.privacy_messages === 'nobody') {
          item.can_send_messages = false;
          item.message_restriction_reason = 'nobody';
        } else if (item.privacy_messages === 'contacts') {
          const partnerContacts = this.getUserContactPartnerIds(item.participant_id);
          if (!partnerContacts.includes(userId)) {
            item.can_send_messages = false;
            item.message_restriction_reason = 'contacts_only';
          } else {
            item.can_send_messages = true;
          }
        } else {
          item.can_send_messages = true;
        }
      } else {
        item.can_send_messages = true;
      }

      return item;
    });
  },

  getUnreadCountForChat(chatId, userId) {
    const stmt = db.prepare(`
      SELECT COUNT(*) as count 
      FROM messages 
      WHERE chat_id = ? AND sender_id != ? AND is_read = 0
    `);
    const row = stmt.get(chatId, userId);
    return row ? row.count : 0;
  },

  markChatAsRead(chatId, userId) {
    const stmt = db.prepare(`
      UPDATE messages 
      SET is_read = 1 
      WHERE chat_id = ? AND sender_id != ? AND is_read = 0
    `);
    const result = stmt.run(chatId, userId);
    return result.changes;
  },

  clearChatMessages(chatId) {
    const stmt = db.prepare('DELETE FROM messages WHERE chat_id = ?');
    const result = stmt.run(chatId);
    return result.changes;
  },

  getPinnedChatsCount(userId) {
    const row = db.prepare('SELECT COUNT(*) as count FROM chat_participants WHERE user_id = ? AND is_pinned = 1').get(userId);
    return row ? row.count : 0;
  },

  togglePinChat(chatId, userId) {
    const part = db.prepare('SELECT is_pinned FROM chat_participants WHERE chat_id = ? AND user_id = ?').get(chatId, userId);
    if (!part) {
      throw new Error('Чат не найден');
    }
    const isCurrentlyPinned = Boolean(part.is_pinned);
    if (!isCurrentlyPinned) {
      const user = this.getUserById(userId);
      const isPremium = Boolean(user?.is_premium);
      const maxPinned = isPremium ? 10 : 3;
      const currentCount = this.getPinnedChatsCount(userId);
      if (currentCount >= maxPinned) {
        const errorMsg = isPremium
          ? 'Достигнут лимит: можно закрепить максимум 10 чатов.'
          : 'Достигнут лимит: можно закрепить до 3 чатов. С подпиской Premium доступно до 10.';
        const err = new Error(errorMsg);
        err.code = 'PIN_LIMIT_REACHED';
        throw err;
      }
      db.prepare('UPDATE chat_participants SET is_pinned = 1, pinned_at = CURRENT_TIMESTAMP WHERE chat_id = ? AND user_id = ?').run(chatId, userId);
      return { is_pinned: true };
    } else {
      db.prepare('UPDATE chat_participants SET is_pinned = 0, pinned_at = NULL WHERE chat_id = ? AND user_id = ?').run(chatId, userId);
      return { is_pinned: false };
    }
  },

  deleteChat(chatId) {
    const deleteTx = db.transaction(() => {
      // Clean up bot updates
      try {
        db.prepare('DELETE FROM bot_updates WHERE chat_id = ?').run(chatId);
      } catch (_) {}
      // Unlink gifts chat_id
      try {
        db.prepare('UPDATE user_gifts SET chat_id = NULL WHERE chat_id = ?').run(chatId);
      } catch (_) {}
      // Delete post reactions if any messages in this chat
      try {
        db.prepare(`
          DELETE FROM post_sparks_reactions 
          WHERE message_id IN (SELECT id FROM messages WHERE chat_id = ?)
        `).run(chatId);
      } catch (_) {}
      // Delete messages
      db.prepare('DELETE FROM messages WHERE chat_id = ?').run(chatId);
      // Delete channels if channel
      try {
        db.prepare('DELETE FROM channels WHERE chat_id = ?').run(chatId);
      } catch (_) {}
      // Delete groups if group
      try {
        db.prepare('DELETE FROM groups WHERE chat_id = ?').run(chatId);
      } catch (_) {}
      // Delete chat participants
      db.prepare('DELETE FROM chat_participants WHERE chat_id = ?').run(chatId);
      // Delete the chat
      db.prepare('DELETE FROM chats WHERE id = ?').run(chatId);
    });
    deleteTx();
    return true;
  },

  getChatById(chatId, currentUserId) {
    const chat = db.prepare('SELECT id, is_channel, is_group, COALESCE(is_saved, 0) as is_saved, pinned_message_id FROM chats WHERE id = ?').get(chatId);
    if (!chat) return null;

    if (chat.is_saved) {
      const stmt = db.prepare(`
        SELECT 
          c.id as chat_id,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          ? as participant_id,
          'Избранное' as first_name,
          '' as last_name,
          'saved' as username,
          '' as avatar,
          NULL as phone,
          c.updated_at as last_seen,
          0 as is_bot,
          0 as is_channel,
          0 as is_group,
          1 as is_saved,
          NULL as invite_code,
          ? as owner_id,
          0 as subscribers_count,
          0 as members_count,
          1 as is_subscribed,
          'Ваши личные сообщения и заметки' as description,
          'none' as verification,
          0 as is_premium,
          0 as unread_count
        FROM chats c
        WHERE c.id = ?
      `);
      const row = stmt.get(currentUserId, currentUserId, chatId);
      if (row) {
        row.id = row.chat_id;
        row.secondary_usernames = [];
        row.can_send_messages = true;
        row.privacy_messages = 'all';
        row.privacy_messages_sparks_price = 0;
        row.privacy_phone = 'all';
        row.privacy_last_seen = 'all';
      }
      return row;
    }

    if (chat.is_channel) {
      const stmt = db.prepare(`
        SELECT 
          c.id as chat_id,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          ch.owner_id as participant_id,
          ch.title as first_name,
          '' as last_name,
          ch.username,
          ch.avatar,
          NULL as phone,
          c.updated_at as last_seen,
          0 as is_bot,
          1 as is_channel,
          0 as is_group,
          NULL as invite_code,
          ch.owner_id,
          (SELECT COUNT(*) FROM chat_participants WHERE chat_id = c.id) as subscribers_count,
          0 as members_count,
          CASE 
            WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = c.id AND user_id = ?)
            ELSE 0 
          END as is_subscribed,
          ch.description,
          COALESCE(ch.verification, 'none') as verification,
          0 as is_premium,
          0 as unread_count
        FROM chats c
        JOIN channels ch ON ch.chat_id = c.id
        WHERE c.id = ?
      `);
      const row = stmt.get(currentUserId, currentUserId, chatId);
      if (row) {
        row.id = row.chat_id;
        row.secondary_usernames = [];
        row.can_send_messages = Boolean(row.owner_id === currentUserId);
        row.privacy_messages = 'all';
        row.privacy_messages_sparks_price = 0;
        row.privacy_phone = 'all';
        row.privacy_last_seen = 'all';
      }
      return row;
    }

    if (chat.is_group) {
      const stmt = db.prepare(`
        SELECT 
          c.id as chat_id,
          c.pinned_message_id,
          c.wallpaper_url,
          COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
          g.owner_id as participant_id,
          g.title as first_name,
          '' as last_name,
          g.invite_code as username,
          g.avatar,
          NULL as phone,
          c.updated_at as last_seen,
          0 as is_bot,
          0 as is_channel,
          1 as is_group,
          g.owner_id,
          g.invite_code,
          0 as subscribers_count,
          (SELECT COUNT(*) FROM chat_participants WHERE chat_id = c.id) as members_count,
          CASE 
            WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = c.id AND user_id = ?)
            ELSE 0 
          END as is_subscribed,
          CASE 
            WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = c.id AND user_id = ?)
            ELSE 0 
          END as is_member,
          g.description,
          'none' as verification,
          0 as is_premium,
          0 as unread_count
        FROM chats c
        JOIN groups g ON g.chat_id = c.id
        WHERE c.id = ?
      `);
      const row = stmt.get(currentUserId, currentUserId, currentUserId, currentUserId, chatId);
      if (row) {
        row.id = row.chat_id;
        row.secondary_usernames = [];
        row.can_send_messages = true;
        row.privacy_messages = 'all';
        row.privacy_messages_sparks_price = 0;
        row.privacy_phone = 'all';
        row.privacy_last_seen = 'all';
      }
      return row;
    }

    const stmt = db.prepare(`
      SELECT 
        c.id as chat_id,
        c.pinned_message_id,
        c.wallpaper_url,
        COALESCE(c.wallpaper_blur, 0) as wallpaper_blur,
        u.id as participant_id,
        u.first_name,
        u.last_name,
        u.username,
        u.avatar,
        CASE WHEN u.is_bot = 1 THEN NULL ELSE u.phone END as phone,
        u.last_seen,
        u.is_bot,
        0 as is_channel,
        0 as is_group,
        NULL as invite_code,
        NULL as owner_id,
        0 as subscribers_count,
        0 as members_count,
        1 as is_subscribed,
        u.description,
        COALESCE(u.verification, 'none') as verification,
        COALESCE(u.is_premium, 0) as is_premium,
        COALESCE(u.banner_url, '') as banner_url,
        u.pinned_channel_id as pinned_channel_id,
        COALESCE(u.privacy_messages, 'all') as privacy_messages,
        COALESCE(u.privacy_messages_sparks_price, 1) as privacy_messages_sparks_price,
        COALESCE(u.privacy_phone, 'all') as privacy_phone,
        COALESCE(u.privacy_last_seen, 'all') as privacy_last_seen,
        COALESCE(u.name_font, 'default') as name_font,
        COALESCE(u.status_font, 'default') as status_font,
        COALESCE(u.custom_activity_status, '') as custom_activity_status,
        (
          SELECT COUNT(*) 
          FROM messages unread_m 
          WHERE unread_m.chat_id = c.id 
            AND unread_m.sender_id != ? 
            AND unread_m.is_read = 0
        ) as unread_count
      FROM chats c
      JOIN chat_participants other_cp ON other_cp.chat_id = c.id AND other_cp.user_id != ?
      JOIN users u ON u.id = other_cp.user_id
      WHERE c.id = ?
      LIMIT 1
    `);
    const row = stmt.get(currentUserId, currentUserId, chatId);
    if (row) {
      row.id = row.chat_id;
      row.secondary_usernames = this.getUserSecondaryUsernames(row.participant_id);

      // Enforce privacy_last_seen
      let canSeeActivity = true;
      if (row.privacy_last_seen === 'nobody') {
        canSeeActivity = false;
      } else if (row.privacy_last_seen === 'contacts') {
        const partnerContacts = this.getUserContactPartnerIds(row.participant_id);
        if (!partnerContacts.includes(currentUserId)) {
          canSeeActivity = false;
        }
      }
      if (!canSeeActivity) {
        row.is_online = 0;
        row.last_seen = null;
        row.is_activity_hidden = 1;
      }

      // Enforce privacy_phone
      if (row.privacy_phone === 'nobody') {
        row.phone = null;
      } else if (row.privacy_phone === 'contacts') {
        const partnerContacts = this.getUserContactPartnerIds(row.participant_id);
        if (!partnerContacts.includes(currentUserId)) {
          row.phone = null;
        }
      }

      // Enforce can_send_messages
      if (row.privacy_messages === 'nobody') {
        row.can_send_messages = false;
        row.message_restriction_reason = 'nobody';
      } else if (row.privacy_messages === 'contacts') {
        const partnerContacts = this.getUserContactPartnerIds(row.participant_id);
        if (!partnerContacts.includes(currentUserId)) {
          row.can_send_messages = false;
          row.message_restriction_reason = 'contacts_only';
        } else {
          row.can_send_messages = true;
        }
      } else {
        row.can_send_messages = true;
      }
    }
    return row;
  },

  _formatMessage(row) {
    if (!row) return row;
    if (row.reply_markup) {
      try {
        row.reply_markup = typeof row.reply_markup === 'string' ? JSON.parse(row.reply_markup) : row.reply_markup;
      } catch (_) {}
    }
    return row;
  },

  getMessageById(messageId, currentUserId = null) {
    const fetchStmt = db.prepare(`
      SELECT 
        m.id,
        m.chat_id,
        m.sender_id,
        m.text,
        m.reply_markup,
        m.reply_to_message_id,
        COALESCE(m.is_edited, 0) as is_edited,
        m.created_at,
        m.updated_at,
        m.is_read,
        u.first_name as sender_first_name,
        u.last_name as sender_last_name,
        TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) as sender_name,
        u.username as sender_username,
        u.avatar as sender_avatar,
        u.is_bot as sender_is_bot,
        COALESCE(u.verification, 'none') as sender_verification,
        COALESCE(u.is_premium, 0) as sender_is_premium,
        COALESCE(u.name_font, 'default') as sender_name_font,
        rm.text as reply_to_text,
        rm.sender_id as reply_to_sender_id,
        TRIM(COALESCE(ru.first_name, '') || ' ' || COALESCE(ru.last_name, '')) as reply_to_sender_name,
        COALESCE(ru.name_font, 'default') as reply_to_sender_name_font,
        (SELECT COUNT(*) FROM post_likes WHERE message_id = m.id) as likes_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM post_likes WHERE message_id = m.id AND user_id = ?)
          ELSE 0 
        END as is_liked,
        (SELECT COUNT(*) FROM post_views WHERE message_id = m.id) as views_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM post_views WHERE message_id = m.id AND user_id = ?)
          ELSE 0 
        END as is_viewed,
        (SELECT COUNT(*) FROM post_comments WHERE message_id = m.id) as comments_count,
        (SELECT COALESCE(SUM(amount), 0) FROM post_sparks_reactions WHERE message_id = m.id) as sparks_count,
        CASE 
          WHEN ? IS NOT NULL THEN (SELECT COALESCE(SUM(amount), 0) FROM post_sparks_reactions WHERE message_id = m.id AND user_id = ?)
          ELSE 0 
        END as my_sparks_count
      FROM messages m
      JOIN users u ON u.id = m.sender_id
      LEFT JOIN messages rm ON rm.id = m.reply_to_message_id
      LEFT JOIN users ru ON ru.id = rm.sender_id
      WHERE m.id = ?
    `);
    const row = fetchStmt.get(currentUserId, currentUserId, currentUserId, currentUserId, currentUserId, currentUserId, messageId);
    const formatted = this._formatMessage(row);
    if (formatted) {
      try {
        formatted.reactions = this.getMessageReactions(messageId);
      } catch (_) {
        formatted.reactions = [];
      }
    }
    return formatted;
  },

  getChatMessages(chatId, currentUserId = null) {
    const stmt = db.prepare(`
      SELECT 
        m.id,
        m.chat_id,
        m.sender_id,
        m.text,
        m.reply_markup,
        m.reply_to_message_id,
        COALESCE(m.is_edited, 0) as is_edited,
        m.created_at,
        m.updated_at,
        m.is_read,
        u.first_name as sender_first_name,
        u.last_name as sender_last_name,
        TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) as sender_name,
        u.username as sender_username,
        u.avatar as sender_avatar,
        u.is_bot as sender_is_bot,
        COALESCE(u.verification, 'none') as sender_verification,
        COALESCE(u.is_premium, 0) as sender_is_premium,
        COALESCE(u.name_font, 'default') as sender_name_font,
        rm.text as reply_to_text,
        rm.sender_id as reply_to_sender_id,
        TRIM(COALESCE(ru.first_name, '') || ' ' || COALESCE(ru.last_name, '')) as reply_to_sender_name,
        COALESCE(ru.name_font, 'default') as reply_to_sender_name_font,
        (SELECT COUNT(*) FROM post_likes WHERE message_id = m.id) as likes_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM post_likes WHERE message_id = m.id AND user_id = ?)
          ELSE 0 
        END as is_liked,
        (SELECT COUNT(*) FROM post_views WHERE message_id = m.id) as views_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM post_views WHERE message_id = m.id AND user_id = ?)
          ELSE 0 
        END as is_viewed,
        (SELECT COUNT(*) FROM post_comments WHERE message_id = m.id) as comments_count,
        (SELECT COALESCE(SUM(amount), 0) FROM post_sparks_reactions WHERE message_id = m.id) as sparks_count,
        CASE 
          WHEN ? IS NOT NULL THEN (SELECT COALESCE(SUM(amount), 0) FROM post_sparks_reactions WHERE message_id = m.id AND user_id = ?)
          ELSE 0 
        END as my_sparks_count
      FROM messages m
      JOIN users u ON u.id = m.sender_id
      LEFT JOIN messages rm ON rm.id = m.reply_to_message_id
      LEFT JOIN users ru ON ru.id = rm.sender_id
      WHERE m.chat_id = ?
      ORDER BY m.id ASC
    `);
    const rows = stmt.all(currentUserId, currentUserId, currentUserId, currentUserId, currentUserId, currentUserId, chatId);

    let reactionsByMsgId = {};
    try {
      const rStmt = db.prepare(`
        SELECT 
          mr.id,
          mr.message_id,
          mr.user_id,
          mr.emoji,
          mr.created_at,
          u.first_name,
          u.last_name,
          u.username,
          u.avatar
        FROM message_reactions mr
        JOIN users u ON u.id = mr.user_id
        JOIN messages m ON m.id = mr.message_id
        WHERE m.chat_id = ?
        ORDER BY mr.created_at ASC
      `);
      const reactions = rStmt.all(chatId);
      for (const r of reactions) {
        if (!reactionsByMsgId[r.message_id]) reactionsByMsgId[r.message_id] = [];
        reactionsByMsgId[r.message_id].push(r);
      }
    } catch (_) {}

    return rows.map(r => {
      const formatted = this._formatMessage(r);
      formatted.reactions = reactionsByMsgId[formatted.id] || [];
      return formatted;
    });
  },

  saveMessage(chatId, senderId, text, replyMarkup = null, replyToMessageId = null) {
    const nowIso = new Date().toISOString();
    let serializedMarkup = null;
    if (replyMarkup) {
      serializedMarkup = typeof replyMarkup === 'string' ? replyMarkup : JSON.stringify(replyMarkup);
    }

    const insertStmt = db.prepare(`
      INSERT INTO messages (chat_id, sender_id, text, reply_markup, reply_to_message_id, created_at) 
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    const result = insertStmt.run(chatId, senderId, text, serializedMarkup, replyToMessageId || null, nowIso);
    const messageId = Number(result.lastInsertRowid);

    // Record author's view automatically
    try {
      db.prepare('INSERT OR IGNORE INTO post_views (message_id, user_id) VALUES (?, ?)').run(messageId, senderId);
    } catch (_) {}

    // Update chat updated_at
    const updateChatStmt = db.prepare('UPDATE chats SET updated_at = CURRENT_TIMESTAMP WHERE id = ?');
    updateChatStmt.run(chatId);

    return this.getMessageById(messageId, senderId);
  },

  editMessage(messageId, text, replyMarkup = undefined, markEdited = true) {
    let serializedMarkup = undefined;
    if (replyMarkup !== undefined) {
      if (replyMarkup === null) {
        serializedMarkup = null;
      } else {
        serializedMarkup = typeof replyMarkup === 'string' ? replyMarkup : JSON.stringify(replyMarkup);
      }
    }

    const editedVal = markEdited ? 1 : 0;
    if (serializedMarkup !== undefined) {
      db.prepare('UPDATE messages SET text = ?, reply_markup = ?, is_edited = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(text, serializedMarkup, editedVal, messageId);
    } else {
      db.prepare('UPDATE messages SET text = ?, is_edited = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(text, editedVal, messageId);
    }

    return this.getMessageById(messageId);
  },

  editMessageReplyMarkup(messageId, replyMarkup = null) {
    let serializedMarkup = null;
    if (replyMarkup) {
      serializedMarkup = typeof replyMarkup === 'string' ? replyMarkup : JSON.stringify(replyMarkup);
    }
    db.prepare('UPDATE messages SET reply_markup = ? WHERE id = ?').run(serializedMarkup, messageId);
    return this.getMessageById(messageId);
  },

  deleteMessage(messageId) {
    try {
      db.prepare('UPDATE chats SET pinned_message_id = NULL WHERE pinned_message_id = ?').run(messageId);
    } catch (_) {}
    db.prepare('DELETE FROM messages WHERE id = ?').run(messageId);
    return true;
  },

  pinMessage(chatId, messageId) {
    const current = db.prepare('SELECT pinned_message_id FROM chats WHERE id = ?').get(chatId);
    const nextPinnedId = current?.pinned_message_id === messageId ? null : (messageId || null);
    db.prepare('UPDATE chats SET pinned_message_id = ? WHERE id = ?').run(nextPinnedId, chatId);
    const pinnedMessage = nextPinnedId ? this.getMessageById(nextPinnedId) : null;
    return { pinnedMessage, isPinned: Boolean(nextPinnedId) };
  },

  updateChatWallpaper(chatId, wallpaperUrl, isBlurred = 0) {
    db.prepare('UPDATE chats SET wallpaper_url = ?, wallpaper_blur = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
      .run(wallpaperUrl || null, isBlurred ? 1 : 0, Number(chatId));
    return this.getChatById(Number(chatId));
  },

  getPinnedMessage(chatId, currentUserId = null) {
    const chat = db.prepare('SELECT pinned_message_id FROM chats WHERE id = ?').get(chatId);
    if (!chat || !chat.pinned_message_id) return null;
    return this.getMessageById(chat.pinned_message_id, currentUserId);
  },

  getChatParticipantUserIds(chatId) {
    const stmt = db.prepare('SELECT user_id FROM chat_participants WHERE chat_id = ?');
    const rows = stmt.all(chatId);
    return rows.map(r => r.user_id);
  },

  getOtherParticipantInChat(chatId, userId) {
    const stmt = db.prepare(`
      SELECT u.id, u.first_name, u.last_name, u.username, u.avatar, u.is_bot, u.bot_owner_id, u.description
      FROM chat_participants cp
      JOIN users u ON u.id = cp.user_id
      WHERE cp.chat_id = ? AND cp.user_id != ?
      LIMIT 1
    `);
    return stmt.get(chatId, userId);
  },

  // ===== BOT MANAGEMENT =====
  getBotByToken(token) {
    if (!token) return null;
    const stmt = db.prepare('SELECT * FROM users WHERE is_bot = 1 AND bot_token = ?');
    return stmt.get(token);
  },

  getBotById(botId) {
    const stmt = db.prepare('SELECT id, first_name, username, avatar, is_bot, bot_owner_id, bot_token, description FROM users WHERE id = ? AND is_bot = 1');
    return stmt.get(botId);
  },

  createBotUser({ ownerId, firstName, username, token, description = '' }) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    const phone = `bot_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    const stmt = db.prepare(`
      INSERT INTO users (phone, first_name, last_name, username, avatar, profile_completed, is_bot, bot_owner_id, bot_token, description)
      VALUES (?, ?, '', ?, ?, 1, 1, ?, ?, ?)
    `);
    const result = stmt.run(phone, firstName.trim(), cleanUsername, '/uploads/botfather.svg', ownerId, token, description);
    return this.getUserById(Number(result.lastInsertRowid));
  },

  getUserBots(ownerId) {
    const stmt = db.prepare(`
      SELECT id, first_name, username, avatar, bot_token, description, created_at 
      FROM users 
      WHERE is_bot = 1 AND bot_owner_id = ?
      ORDER BY id DESC
    `);
    return stmt.all(ownerId);
  },

  // ===== BOTFATHER SESSION =====
  getBotFatherSession(userId) {
    const stmt = db.prepare('SELECT * FROM botfather_sessions WHERE user_id = ?');
    return stmt.get(userId);
  },

  setBotFatherSession(userId, step, draftName = null, targetBotId = null) {
    const stmt = db.prepare(`
      INSERT INTO botfather_sessions (user_id, step, draft_name, target_bot_id, updated_at)
      VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(user_id) DO UPDATE SET 
        step = excluded.step, 
        draft_name = excluded.draft_name, 
        target_bot_id = excluded.target_bot_id, 
        updated_at = CURRENT_TIMESTAMP
    `);
    stmt.run(userId, step, draftName, targetBotId);
  },

  clearBotFatherSession(userId) {
    const stmt = db.prepare('DELETE FROM botfather_sessions WHERE user_id = ?');
    stmt.run(userId);
  },

  updateBotName(botId, ownerId, newName) {
    const cleanName = (newName || '').trim();
    if (!cleanName) return false;
    const stmt = db.prepare('UPDATE users SET first_name = ? WHERE id = ? AND is_bot = 1 AND bot_owner_id = ?');
    const result = stmt.run(cleanName, botId, ownerId);
    return result.changes > 0;
  },

  updateBotDescription(botId, ownerId, newDescription) {
    const stmt = db.prepare('UPDATE users SET description = ? WHERE id = ? AND is_bot = 1 AND bot_owner_id = ?');
    const result = stmt.run((newDescription || '').trim(), botId, ownerId);
    return result.changes > 0;
  },

  getBotByUsername(username) {
    const cleanUsername = (username || '').trim().toLowerCase().replace(/^@+/, '');
    const stmt = db.prepare('SELECT id, first_name, username, avatar, is_bot, bot_owner_id, bot_token, description FROM users WHERE LOWER(username) = ? AND is_bot = 1');
    return stmt.get(cleanUsername);
  },

  // ===== BOT UPDATES (FOR LONG POLLING & GETUPDATES) =====
  addBotUpdate(botIdOrObj, chatId, messageId, updateType = 'message', callbackId = null, callbackData = null, userId = null) {
    let botId = botIdOrObj;
    let cId = chatId;
    let mId = messageId;
    let uType = updateType;
    let cbId = callbackId;
    let cbData = callbackData;
    let uId = userId;

    if (typeof botIdOrObj === 'object' && botIdOrObj !== null) {
      botId = botIdOrObj.botId;
      cId = botIdOrObj.chatId;
      mId = botIdOrObj.messageId;
      uType = botIdOrObj.updateType || 'message';
      cbId = botIdOrObj.callbackId || null;
      cbData = botIdOrObj.callbackData || null;
      uId = botIdOrObj.userId || null;
    }

    const stmt = db.prepare(`
      INSERT INTO bot_updates (bot_id, chat_id, message_id, update_type, callback_id, callback_data, user_id) 
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    const result = stmt.run(botId, cId, mId, uType, cbId, cbData, uId);
    return Number(result.lastInsertRowid);
  },

  getBotUpdates(botId, offset = 0, limit = 100) {
    let query = `
      SELECT 
        bu.update_id,
        bu.bot_id,
        bu.chat_id,
        bu.message_id,
        bu.update_type,
        bu.callback_id,
        bu.callback_data,
        bu.user_id as clicker_user_id,
        bu.created_at as update_created_at,
        m.text,
        m.reply_markup,
        m.created_at as message_created_at,
        m.sender_id,
        COALESCE(u_clicker.id, u_sender.id) as user_id,
        COALESCE(u_clicker.first_name, u_sender.first_name) as first_name,
        COALESCE(u_clicker.last_name, u_sender.last_name) as last_name,
        COALESCE(u_clicker.username, u_sender.username) as username
      FROM bot_updates bu
      JOIN messages m ON m.id = bu.message_id
      LEFT JOIN users u_sender ON u_sender.id = m.sender_id
      LEFT JOIN users u_clicker ON u_clicker.id = bu.user_id
      WHERE bu.bot_id = ?
    `;
    const params = [botId];
    if (offset > 0) {
      query += ' AND bu.update_id >= ?';
      params.push(offset);
    }
    query += ' ORDER BY bu.update_id ASC LIMIT ?';
    params.push(limit);
    const stmt = db.prepare(query);
    return stmt.all(...params);
  },

  // ===== CHANNELS =====
  createChannel({ ownerId, title, username, avatar, description }) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    const chatResult = db.prepare('INSERT INTO chats (is_channel) VALUES (1)').run();
    const chatId = Number(chatResult.lastInsertRowid);

    const stmt = db.prepare(`
      INSERT INTO channels (chat_id, owner_id, title, username, avatar, description)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    stmt.run(chatId, ownerId, title.trim(), cleanUsername, avatar || '', description || '');

    // Owner is first subscriber
    db.prepare('INSERT INTO chat_participants (chat_id, user_id) VALUES (?, ?)').run(chatId, ownerId);

    return this.getChannelByChatId(chatId, ownerId);
  },

  getChannelByChatId(chatId, currentUserId = null) {
    const stmt = db.prepare(`
      SELECT 
        ch.id,
        ch.chat_id,
        ch.owner_id,
        ch.title,
        ch.username,
        ch.avatar,
        ch.description,
        COALESCE(ch.verification, 'none') as verification,
        COALESCE(ch.artifacts, 0) as artifacts,
        ch.created_at,
        (SELECT COUNT(*) FROM chat_participants WHERE chat_id = ch.chat_id) as subscribers_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = ch.chat_id AND user_id = ?)
          ELSE 0 
        END as is_subscribed
      FROM channels ch
      WHERE ch.chat_id = ?
    `);
    return stmt.get(currentUserId, currentUserId, chatId);
  },

  updateChannel(chatId, ownerId, { title, username, description, avatar }) {
    const channel = this.getChannelByChatId(chatId);
    if (!channel) {
      throw new Error('Канал не найден');
    }
    if (channel.owner_id !== ownerId) {
      throw new Error('Только владелец может редактировать канал');
    }

    let cleanUsername = channel.username;
    if (username !== undefined && username !== null) {
      cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
      if (!cleanUsername || cleanUsername.length < 5) {
        throw new Error('Имя пользователя должно содержать минимум 5 символов');
      }
      if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
        throw new Error('Только латинские буквы, цифры и символ подчеркивания');
      }
      if (!this.isUsernameAvailable(cleanUsername, null, channel.id)) {
        throw new Error('Это имя пользователя уже занято');
      }
    }

    const cleanTitle = (title !== undefined && title !== null) ? title.trim() : channel.title;
    if (!cleanTitle) {
      throw new Error('Название канала обязательно');
    }

    const cleanDescription = description !== undefined ? description.trim() : (channel.description || '');
    const cleanAvatar = avatar !== undefined ? avatar : (channel.avatar || '');

    db.prepare(`
      UPDATE channels
      SET title = ?, username = ?, description = ?, avatar = ?
      WHERE chat_id = ? AND owner_id = ?
    `).run(cleanTitle, cleanUsername, cleanDescription, cleanAvatar, chatId, ownerId);

    return this.getChannelByChatId(chatId, ownerId);
  },

  getChannelByUsername(username) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    const stmt = db.prepare('SELECT * FROM channels WHERE LOWER(username) = ?');
    return stmt.get(cleanUsername);
  },

  subscribeToChannel(chatId, userId) {
    db.prepare('INSERT OR IGNORE INTO chat_participants (chat_id, user_id) VALUES (?, ?)').run(chatId, userId);
    return this.getChannelByChatId(chatId, userId);
  },

  unsubscribeFromChannel(chatId, userId) {
    const channel = this.getChannelByChatId(chatId);
    if (channel && channel.owner_id === userId) {
      // Owner cannot unsubscribe from their own channel
      return this.getChannelByChatId(chatId, userId);
    }
    db.prepare('DELETE FROM chat_participants WHERE chat_id = ? AND user_id = ?').run(chatId, userId);
    return this.getChannelByChatId(chatId, userId);
  },

  getChannelsCountByOwner(ownerId) {
    const row = db.prepare('SELECT COUNT(*) as count FROM channels WHERE owner_id = ?').get(ownerId);
    return Number(row?.count || 0);
  },

  getChannelsByOwner(ownerId) {
    return db.prepare('SELECT * FROM channels WHERE owner_id = ? ORDER BY id DESC').all(ownerId);
  },

  giftArtifactToChannel(chatId, userId) {
    const user = this.getUserById(userId);
    if (!user) throw new Error('Пользователь не найден');
    if (Number(user.artifacts || 0) < 1) {
      throw new Error('У вас нет доступных артефактов');
    }

    const channel = this.getChannelByChatId(chatId);
    if (!channel) throw new Error('Канал не найден');

    const deductUser = db.prepare('UPDATE users SET artifacts = COALESCE(artifacts, 0) - 1 WHERE id = ?');
    const addChannel = db.prepare('UPDATE channels SET artifacts = COALESCE(artifacts, 0) + 1 WHERE chat_id = ?');
    const insertLog = db.prepare('INSERT INTO channel_artifacts_gifts (channel_id, user_id) VALUES (?, ?)');

    db.exec('BEGIN');
    try {
      deductUser.run(userId);
      addChannel.run(channel.chat_id);
      insertLog.run(channel.id, userId);
      db.exec('COMMIT');
    } catch (err) {
      try {
        db.exec('ROLLBACK');
      } catch (_) {}
      throw err;
    }

    const updatedUser = this.getUserById(userId);
    const updatedChannel = this.getChannelByChatId(chatId, userId);

    return {
      updatedUser,
      updatedChannel,
      userArtifacts: Number(updatedUser.artifacts || 0),
      channelArtifacts: Number(updatedChannel.artifacts || 0)
    };
  },

  // ===== GROUPS =====
  generateUniqueInviteCode() {
    const chars = '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
    for (let attempts = 0; attempts < 50; attempts++) {
      let code = '';
      for (let i = 0; i < 8; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      const existing = db.prepare('SELECT id FROM groups WHERE invite_code = ?').get(code);
      if (!existing) {
        return code;
      }
    }
    return Math.random().toString(36).substring(2, 10);
  },

  createGroup({ ownerId, title, avatar, description }) {
    const inviteCode = this.generateUniqueInviteCode();
    const chatResult = db.prepare('INSERT INTO chats (is_channel, is_group) VALUES (0, 1)').run();
    const chatId = Number(chatResult.lastInsertRowid);

    const stmt = db.prepare(`
      INSERT INTO groups (chat_id, owner_id, title, avatar, description, invite_code)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    stmt.run(chatId, ownerId, title.trim(), avatar || '', description ? description.trim() : '', inviteCode);

    // Owner is first participant
    db.prepare('INSERT INTO chat_participants (chat_id, user_id) VALUES (?, ?)').run(chatId, ownerId);

    return this.getGroupByChatId(chatId, ownerId);
  },

  getGroupByChatId(chatId, currentUserId = null) {
    const stmt = db.prepare(`
      SELECT 
        g.id,
        g.chat_id,
        g.owner_id,
        g.title,
        g.avatar,
        g.description,
        g.invite_code,
        g.created_at,
        1 as is_group,
        0 as is_channel,
        (SELECT COUNT(*) FROM chat_participants WHERE chat_id = g.chat_id) as members_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = g.chat_id AND user_id = ?)
          ELSE 0 
        END as is_member
      FROM groups g
      WHERE g.chat_id = ?
    `);
    return stmt.get(currentUserId, currentUserId, chatId);
  },

  getGroupByInviteCode(inviteCode, currentUserId = null) {
    if (!inviteCode) return null;
    const clean = String(inviteCode).trim();
    const stmt = db.prepare(`
      SELECT 
        g.id,
        g.chat_id,
        g.owner_id,
        g.title,
        g.avatar,
        g.description,
        g.invite_code,
        g.created_at,
        1 as is_group,
        0 as is_channel,
        (SELECT COUNT(*) FROM chat_participants WHERE chat_id = g.chat_id) as members_count,
        CASE 
          WHEN ? IS NOT NULL THEN EXISTS(SELECT 1 FROM chat_participants WHERE chat_id = g.chat_id AND user_id = ?)
          ELSE 0 
        END as is_member
      FROM groups g
      WHERE LOWER(g.invite_code) = LOWER(?)
    `);
    return stmt.get(currentUserId, currentUserId, clean);
  },

  joinGroup(inviteCode, userId) {
    const group = this.getGroupByInviteCode(inviteCode, userId);
    if (!group) {
      throw new Error('Группа не найдена');
    }
    const alreadyMember = Boolean(group.is_member);
    if (!alreadyMember) {
      db.prepare('INSERT OR IGNORE INTO chat_participants (chat_id, user_id) VALUES (?, ?)').run(group.chat_id, userId);
    }
    return {
      group: this.getGroupByChatId(group.chat_id, userId),
      newlyJoined: !alreadyMember
    };
  },

  leaveGroup(chatId, userId) {
    db.prepare('DELETE FROM chat_participants WHERE chat_id = ? AND user_id = ?').run(chatId, userId);
    return this.getGroupByChatId(chatId, userId);
  },

  getGroupMembers(chatId) {
    const stmt = db.prepare(`
      SELECT 
        u.id,
        u.first_name,
        u.last_name,
        u.username,
        u.avatar,
        COALESCE(u.verification, 'none') as verification,
        COALESCE(u.is_premium, 0) as is_premium,
        u.last_seen
      FROM chat_participants cp
      JOIN users u ON u.id = cp.user_id
      WHERE cp.chat_id = ?
      ORDER BY cp.id ASC
    `);
    return stmt.all(chatId);
  },

  // ===== POST INTERACTIONS (LIKES, VIEWS, COMMENTS) =====
  togglePostLike(messageId, userId) {
    const existing = db.prepare('SELECT id FROM post_likes WHERE message_id = ? AND user_id = ?').get(messageId, userId);
    let isLiked = false;
    if (existing) {
      db.prepare('DELETE FROM post_likes WHERE message_id = ? AND user_id = ?').run(messageId, userId);
      isLiked = false;
    } else {
      db.prepare('INSERT INTO post_likes (message_id, user_id) VALUES (?, ?)').run(messageId, userId);
      isLiked = true;
    }
    const countRow = db.prepare('SELECT COUNT(*) as count FROM post_likes WHERE message_id = ?').get(messageId);
    return {
      messageId: Number(messageId),
      isLiked,
      likesCount: countRow ? countRow.count : 0
    };
  },

  recordPostView(messageId, userId) {
    db.prepare('INSERT OR IGNORE INTO post_views (message_id, user_id) VALUES (?, ?)').run(messageId, userId);
    const countRow = db.prepare('SELECT COUNT(*) as count FROM post_views WHERE message_id = ?').get(messageId);
    return {
      messageId: Number(messageId),
      viewsCount: countRow ? countRow.count : 0
    };
  },

  recordPostViews(messageIds, userId) {
    if (!Array.isArray(messageIds) || messageIds.length === 0) return [];
    const insertStmt = db.prepare('INSERT OR IGNORE INTO post_views (message_id, user_id) VALUES (?, ?)');
    const countStmt = db.prepare('SELECT COUNT(*) as count FROM post_views WHERE message_id = ?');
    
    const results = [];
    for (const rawId of messageIds) {
      const msgId = Number(rawId);
      if (!msgId) continue;
      insertStmt.run(msgId, userId);
      const countRow = countStmt.get(msgId);
      results.push({
        messageId: msgId,
        viewsCount: countRow ? countRow.count : 0
      });
    }
    return results;
  },

  getPostComments(messageId) {
    const stmt = db.prepare(`
      SELECT 
        c.id,
        c.message_id,
        c.user_id,
        c.text,
        c.created_at,
        u.first_name,
        u.last_name,
        u.username,
        u.avatar,
        u.is_bot,
        COALESCE(u.verification, 'none') as verification,
        COALESCE(u.is_premium, 0) as is_premium
      FROM post_comments c
      JOIN users u ON u.id = c.user_id
      WHERE c.message_id = ?
      ORDER BY c.id ASC
    `);
    return stmt.all(messageId);
  },

  addPostComment(messageId, userId, text) {
    const insertStmt = db.prepare(`
      INSERT INTO post_comments (message_id, user_id, text)
      VALUES (?, ?, ?)
    `);
    const result = insertStmt.run(messageId, userId, text.trim());
    const commentId = Number(result.lastInsertRowid);

    const fetchStmt = db.prepare(`
      SELECT 
        c.id,
        c.message_id,
        c.user_id,
        c.text,
        c.created_at,
        u.first_name,
        u.last_name,
        u.username,
        u.avatar,
        u.is_bot,
        COALESCE(u.verification, 'none') as verification
      FROM post_comments c
      JOIN users u ON u.id = c.user_id
      WHERE c.id = ?
    `);
    const comment = fetchStmt.get(commentId);
    const countRow = db.prepare('SELECT COUNT(*) as count FROM post_comments WHERE message_id = ?').get(messageId);

    return {
      comment,
      commentsCount: countRow ? countRow.count : 0
    };
  },

  // ===== SPARKS REACTIONS (POST DONATIONS & LEADERBOARDS) =====
  addPostSparksReaction(messageId, userId, amount = 1, isAnonymous = 0) {
    const numAmount = Math.max(1, Math.min(10000, Number(amount) || 1));
    const user = db.prepare('SELECT id, sparks FROM users WHERE id = ?').get(userId);
    if (!user) throw new Error('Пользователь не найден');

    const currentSparks = Number(user.sparks ?? 0);
    if (currentSparks < numAmount) {
      throw new Error(`Недостаточно Sparks на балансе. Требуется: ${numAmount}, доступно: ${currentSparks}`);
    }

    // 1. Deduct sparks from sender
    db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) - ? WHERE id = ?').run(numAmount, userId);

    // 2. Reward channel owner if applicable
    const msgOwner = db.prepare(`
      SELECT ch.owner_id 
      FROM messages m 
      LEFT JOIN channels ch ON ch.chat_id = m.chat_id 
      WHERE m.id = ?
    `).get(messageId);
    if (msgOwner && msgOwner.owner_id && msgOwner.owner_id !== userId) {
      db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) + ? WHERE id = ?').run(numAmount, msgOwner.owner_id);
    }

    // 3. Upsert post_sparks_reactions
    db.prepare(`
      INSERT INTO post_sparks_reactions (message_id, user_id, amount, is_anonymous, updated_at)
      VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(message_id, user_id) DO UPDATE SET
        amount = amount + excluded.amount,
        is_anonymous = excluded.is_anonymous,
        updated_at = CURRENT_TIMESTAMP
    `).run(messageId, userId, numAmount, isAnonymous ? 1 : 0);

    // 4. Get total sparks count
    const totalRow = db.prepare('SELECT COALESCE(SUM(amount), 0) as total FROM post_sparks_reactions WHERE message_id = ?').get(messageId);
    const sparksCount = totalRow ? Number(totalRow.total) : 0;

    // 5. Get user's own total sparks on this post
    const myRow = db.prepare('SELECT amount FROM post_sparks_reactions WHERE message_id = ? AND user_id = ?').get(messageId, userId);
    const mySparksCount = myRow ? Number(myRow.amount) : numAmount;

    // 6. Get updated sender balance
    const updatedUser = db.prepare('SELECT sparks FROM users WHERE id = ?').get(userId);
    const remainingSparks = updatedUser ? Number(updatedUser.sparks) : 0;

    // 7. Get top 3 leaders
    const leaders = this.getPostSparksLeaders(messageId);

    return {
      messageId: Number(messageId),
      sparksCount,
      mySparksCount,
      addedAmount: numAmount,
      remainingSparks,
      leaders,
      channelOwnerId: msgOwner?.owner_id || null
    };
  },

  getPostSparksLeaders(messageId) {
    const stmt = db.prepare(`
      SELECT 
        psr.user_id,
        psr.amount,
        psr.is_anonymous,
        CASE WHEN psr.is_anonymous = 1 THEN 'Аноним' ELSE u.first_name END as first_name,
        CASE WHEN psr.is_anonymous = 1 THEN '' ELSE COALESCE(u.last_name, '') END as last_name,
        CASE WHEN psr.is_anonymous = 1 THEN 'Аноним' ELSE COALESCE(u.username, u.first_name) END as username,
        CASE WHEN psr.is_anonymous = 1 THEN '' ELSE COALESCE(u.avatar, '') END as avatar
      FROM post_sparks_reactions psr
      JOIN users u ON u.id = psr.user_id
      WHERE psr.message_id = ?
      ORDER BY psr.amount DESC, psr.updated_at ASC
      LIMIT 25
    `);
    const rows = stmt.all(messageId);
    return rows.map(r => ({
      userId: r.user_id,
      amount: Number(r.amount),
      isAnonymous: Boolean(r.is_anonymous),
      firstName: r.first_name,
      lastName: r.last_name,
      username: r.username,
      avatar: r.avatar
    }));
  },

  // ===== MESSAGE REACTIONS (IOS APPLE EMOJI REACTIONS) =====
  getMessageReactions(messageId) {
    if (!messageId) return [];
    const stmt = db.prepare(`
      SELECT 
        mr.id,
        mr.message_id,
        mr.user_id,
        mr.emoji,
        mr.created_at,
        u.first_name,
        u.last_name,
        u.username,
        u.avatar
      FROM message_reactions mr
      JOIN users u ON u.id = mr.user_id
      WHERE mr.message_id = ?
      ORDER BY mr.created_at ASC
    `);
    return stmt.all(Number(messageId));
  },

  toggleMessageReaction(messageId, userId, emoji) {
    if (!messageId || !userId || !emoji) return [];
    const numMsgId = Number(messageId);
    const numUserId = Number(userId);

    const existing = db.prepare(
      'SELECT id, emoji FROM message_reactions WHERE message_id = ? AND user_id = ?'
    ).get(numMsgId, numUserId);

    if (existing) {
      if (existing.emoji === emoji) {
        // Toggle off (remove)
        db.prepare('DELETE FROM message_reactions WHERE id = ?').run(existing.id);
      } else {
        // Change to new emoji
        db.prepare('UPDATE message_reactions SET emoji = ?, created_at = CURRENT_TIMESTAMP WHERE id = ?').run(emoji, existing.id);
      }
    } else {
      // Add new reaction
      db.prepare(
        'INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (?, ?, ?)'
      ).run(numMsgId, numUserId, emoji);
    }

    return this.getMessageReactions(numMsgId);
  },

  getUserByUsername(username) {
    if (!username) return null;
    const clean = username.trim().toLowerCase().replace(/^@+/, '');
    
    // First try by primary username
    let stmt = db.prepare(`
      SELECT 
        id, 
        first_name, 
        last_name, 
        username, 
        avatar, 
        profile_completed, 
        is_bot, 
        COALESCE(sparks, 250) as sparks, 
        description,
        COALESCE(verification, 'none') as verification,
        COALESCE(is_premium, 0) as is_premium,
        COALESCE(banner_url, '') as banner_url,
        COALESCE(artifacts, 0) as artifacts,
        pinned_channel_id
      FROM users 
      WHERE LOWER(username) = ?
    `);
    let user = stmt.get(clean);

    // If not found, try by secondary usernames
    if (!user) {
      stmt = db.prepare(`
        SELECT 
          u.id, 
          u.first_name, 
          u.last_name, 
          u.username, 
          u.avatar, 
          u.profile_completed, 
          u.is_bot, 
          COALESCE(u.sparks, 250) as sparks, 
          u.description,
          COALESCE(u.verification, 'none') as verification,
          COALESCE(u.is_premium, 0) as is_premium,
          COALESCE(u.banner_url, '') as banner_url,
          COALESCE(u.artifacts, 0) as artifacts,
          u.pinned_channel_id as pinned_channel_id
        FROM users u
        JOIN user_secondary_usernames s ON s.user_id = u.id
        WHERE LOWER(s.username) = ?
        LIMIT 1
      `);
      user = stmt.get(clean);
    }

    if (user) {
      user.secondary_usernames = this.getUserSecondaryUsernames(user.id);
    }

    return user;
  },

  sendGift({ senderId, recipientId, giftId, giftName, giftFile, price = 50, comment = '', chatId = null }) {
    const sender = this.getUserById(senderId);
    if (!sender) throw new Error('Отправитель не найден');
    const currentSparks = Number(sender.sparks ?? 0);
    if (currentSparks < price) {
      throw new Error(`Недостаточно Sparks. Требуется: ${price}, на балансе: ${currentSparks}`);
    }

    // Deduct sparks
    db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) - ? WHERE id = ?').run(price, senderId);

    // Insert gift
    const insertStmt = db.prepare(`
      INSERT INTO user_gifts (sender_id, recipient_id, gift_id, gift_name, gift_file, price, comment, chat_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    `);
    const result = insertStmt.run(
      senderId, 
      recipientId, 
      giftId, 
      giftName, 
      giftFile, 
      price, 
      comment ? comment.trim() : '', 
      chatId
    );
    const giftDbId = Number(result.lastInsertRowid);

    return this.getGiftById(giftDbId);
  },

  getGiftById(id) {
    const stmt = db.prepare(`
      SELECT 
        g.id,
        g.sender_id,
        g.recipient_id,
        g.gift_id,
        g.gift_name,
        g.gift_file,
        g.price,
        g.comment,
        g.chat_id,
        g.created_at,
        g.is_upgraded,
        g.nft_number,
        g.model_name,
        g.model_file,
        g.model_rarity,
        g.backdrop_name,
        g.backdrop_gradient,
        g.backdrop_rarity,
        g.pattern_name,
        g.pattern_svg,
        g.pattern_rarity,
        COALESCE(g.is_pinned, 0) as is_pinned,
        g.pinned_at,
        COALESCE(g.is_hidden, 0) as is_hidden,
        u.first_name as sender_first_name,
        u.last_name as sender_last_name,
        u.username as sender_username,
        u.avatar as sender_avatar,
        r.first_name as recipient_first_name,
        r.last_name as recipient_last_name,
        r.username as recipient_username,
        r.avatar as recipient_avatar
      FROM user_gifts g
      JOIN users u ON u.id = g.sender_id
      JOIN users r ON r.id = g.recipient_id
      WHERE g.id = ?
    `);
    return stmt.get(id);
  },

  getUserGifts(userId, viewerId = null) {
    const isOwner = viewerId !== null && Number(viewerId) === Number(userId);
    let sql = `
      SELECT 
        g.id,
        g.sender_id,
        g.recipient_id,
        g.gift_id,
        g.gift_name,
        g.gift_file,
        g.price,
        g.comment,
        g.chat_id,
        g.created_at,
        g.is_upgraded,
        g.nft_number,
        g.model_name,
        g.model_file,
        g.model_rarity,
        g.backdrop_name,
        g.backdrop_gradient,
        g.backdrop_rarity,
        g.pattern_name,
        g.pattern_svg,
        g.pattern_rarity,
        COALESCE(g.is_pinned, 0) as is_pinned,
        g.pinned_at,
        COALESCE(g.is_hidden, 0) as is_hidden,
        u.first_name as sender_first_name,
        u.last_name as sender_last_name,
        u.username as sender_username,
        u.avatar as sender_avatar,
        r.first_name as recipient_first_name,
        r.last_name as recipient_last_name,
        r.username as recipient_username,
        r.avatar as recipient_avatar
      FROM user_gifts g
      LEFT JOIN users u ON u.id = g.sender_id
      LEFT JOIN users r ON r.id = g.recipient_id
      WHERE g.recipient_id = ?
    `;

    if (!isOwner) {
      sql += ' AND COALESCE(g.is_hidden, 0) = 0';
    }

    sql += ' ORDER BY COALESCE(g.is_pinned, 0) DESC, g.pinned_at DESC, g.id DESC';

    const stmt = db.prepare(sql);
    return stmt.all(userId);
  },

  togglePinUserGift(giftRecordId, userId) {
    const gift = db.prepare('SELECT id, recipient_id, COALESCE(is_pinned, 0) as is_pinned FROM user_gifts WHERE id = ?').get(giftRecordId);
    if (!gift) throw new Error('Подарок не найден');
    if (gift.recipient_id !== userId) throw new Error('Только владелец подарка может закрепить его');

    if (gift.is_pinned === 1) {
      db.prepare('UPDATE user_gifts SET is_pinned = 0, pinned_at = NULL WHERE id = ?').run(giftRecordId);
      return { is_pinned: 0 };
    } else {
      const row = db.prepare('SELECT COUNT(*) as count FROM user_gifts WHERE recipient_id = ? AND is_pinned = 1').get(userId);
      if (row.count >= 3) {
        throw new Error('Можно закрепить не более 3 подарков');
      }
      db.prepare('UPDATE user_gifts SET is_pinned = 1, pinned_at = CURRENT_TIMESTAMP WHERE id = ?').run(giftRecordId);
      return { is_pinned: 1 };
    }
  },

  toggleHideUserGift(giftRecordId, userId) {
    const gift = db.prepare('SELECT id, recipient_id, COALESCE(is_hidden, 0) as is_hidden FROM user_gifts WHERE id = ?').get(giftRecordId);
    if (!gift) throw new Error('Подарок не найден');
    if (gift.recipient_id !== userId) throw new Error('Только владелец подарка может скрыть его');

    const nextHidden = gift.is_hidden === 1 ? 0 : 1;
    db.prepare('UPDATE user_gifts SET is_hidden = ? WHERE id = ?').run(nextHidden, giftRecordId);
    return { is_hidden: nextHidden };
  },

  upgradeUserGift(giftRecordId, userId, preselected = null) {
    const gift = db.prepare('SELECT * FROM user_gifts WHERE id = ?').get(giftRecordId);
    if (!gift) throw new Error('Подарок не найден');
    if (gift.recipient_id !== userId) throw new Error('Только получатель подарка может его улучшить');
    if (gift.is_upgraded === 1) throw new Error('Этот подарок уже улучшен');

    const user = this.getUserById(userId);
    const sparks = Number(user.sparks ?? 0);
    if (sparks < 1000) {
      throw new Error(`Недостаточно Sparks для улучшения. Требуется 1000, у вас на балансе: ${sparks}`);
    }

    // 1. Deduct 1000 Sparks
    db.prepare('UPDATE users SET sparks = COALESCE(sparks, 250) - 1000 WHERE id = ?').run(userId);

    // 2. Determine sequential NFT number for this model category (#1, #2, ...)
    const numRow = db.prepare('SELECT COALESCE(MAX(nft_number), 0) + 1 as next_num FROM user_gifts WHERE gift_id = ? AND is_upgraded = 1').get(gift.gift_id);
    const nftNumber = numRow?.next_num || 1;

    // 3. Pick model, backdrop, pattern
    let model = preselected?.model;
    let backdrop = preselected?.backdrop;
    let pattern = preselected?.pattern;

    if (!model) {
      let skins = GIFT_SKINS_BY_CATEGORY[gift.gift_id];
      if (!skins) {
        const lower = (gift.gift_name || '').toLowerCase();
        if (lower.includes('car') || lower.includes('bmw') || lower.includes('lada') || lower.includes('tesla') || lower.includes('mercedes')) {
          skins = GIFT_SKINS_BY_CATEGORY.cars;
        } else if (lower.includes('girl')) {
          skins = GIFT_SKINS_BY_CATEGORY.girl;
        } else if (lower.includes('theel') || lower.includes('bumblebee')) {
          skins = GIFT_SKINS_BY_CATEGORY.theel;
        } else {
          skins = GIFT_SKINS_BY_CATEGORY.gargona;
        }
      }
      model = skins[Math.floor(Math.random() * skins.length)];
    }
    if (!backdrop) {
      backdrop = GIFT_BACKDROPS[Math.floor(Math.random() * GIFT_BACKDROPS.length)];
    }
    if (!pattern) {
      pattern = GIFT_PATTERNS[Math.floor(Math.random() * GIFT_PATTERNS.length)];
    }

    // 4. Update gift record
    db.prepare(`
      UPDATE user_gifts 
      SET is_upgraded = 1,
          nft_number = ?,
          model_name = ?,
          model_file = ?,
          model_rarity = ?,
          backdrop_name = ?,
          backdrop_gradient = ?,
          backdrop_rarity = ?,
          pattern_name = ?,
          pattern_svg = ?,
          pattern_rarity = ?
      WHERE id = ?
    `).run(
      nftNumber,
      model.name,
      model.file,
      model.rarity,
      backdrop.name,
      backdrop.gradient,
      backdrop.rarity,
      pattern.name,
      pattern.id,
      pattern.rarity,
      giftRecordId
    );

    // 5. Update associated chat message card if exists
    if (gift.chat_id) {
      try {
        const msgs = db.prepare("SELECT id, text FROM messages WHERE chat_id = ? AND text LIKE '%[PORTAL_GIFT]%'").all(gift.chat_id);
        for (const m of msgs) {
          if (m.text.includes(String(giftRecordId))) {
            let giftData = JSON.parse(m.text.slice('[PORTAL_GIFT]:'.length));
            if (giftData.giftDbId === giftRecordId) {
              giftData.isUpgraded = true;
              giftData.nftNumber = nftNumber;
              giftData.modelName = model.name;
              giftData.modelFile = model.file;
              giftData.modelRarity = model.rarity;
              giftData.backdropName = backdrop.name;
              giftData.backdropGradient = backdrop.gradient;
              giftData.backdropRarity = backdrop.rarity;
              giftData.patternName = pattern.name;
              giftData.patternSvg = pattern.id;
              giftData.patternRarity = pattern.rarity;
              db.prepare('UPDATE messages SET text = ? WHERE id = ?').run('[PORTAL_GIFT]:' + JSON.stringify(giftData), m.id);
            }
          }
        }
      } catch (err) {
        console.warn('Error updating message text after gift upgrade:', err);
      }
    }

    const updatedUser = this.getUserById(userId);
    const updatedGift = this.getGiftById(giftRecordId);

    return {
      gift: updatedGift,
      sparks: Number(updatedUser.sparks)
    };
  },

  // Web Push Subscriptions
  savePushSubscription(userId, subscription) {
    if (!userId || !subscription?.endpoint) return null;
    const endpoint = String(subscription.endpoint);
    const p256dh = String(subscription.keys?.p256dh || '');
    const auth = String(subscription.keys?.auth || '');

    const stmt = db.prepare(`
      INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth, created_at)
      VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(endpoint) DO UPDATE SET
        user_id = excluded.user_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        created_at = CURRENT_TIMESTAMP
    `);
    stmt.run(userId, endpoint, p256dh, auth);
    return true;
  },

  deletePushSubscription(endpoint) {
    if (!endpoint) return;
    db.prepare('DELETE FROM push_subscriptions WHERE endpoint = ?').run(endpoint);
  },

  getPushSubscriptionsForUser(userId) {
    if (!userId) return [];
    return db.prepare('SELECT * FROM push_subscriptions WHERE user_id = ?').all(userId);
  },

  deletePushSubscriptionsForUser(userId) {
    if (!userId) return;
    db.prepare('DELETE FROM push_subscriptions WHERE user_id = ?').run(userId);
  },

  // Flutter Mobile Fast Sync & Bootstrap Methods
  getRecentChatMessages(chatId, currentUserId = null, limit = 30) {
    const all = this.getChatMessages(chatId, currentUserId);
    if (!limit || all.length <= limit) return all;
    return all.slice(-limit);
  },

  getBootstrapData(userId, maxMessagesPerChat = 30) {
    const user = this.getUserById(userId);
    if (!user) return null;

    const rawChats = this.getUserChats(userId);
    const recentMessages = {};
    const topChats = rawChats.slice(0, 25);

    for (const chat of topChats) {
      if (!chat.id) continue;
      recentMessages[chat.id] = this.getRecentChatMessages(chat.id, userId, maxMessagesPerChat);
    }

    return {
      server_time: new Date().toISOString(),
      user,
      chats: rawChats,
      recent_messages: recentMessages
    };
  },

  getDeltaSync(userId, sinceTimestamp) {
    const user = this.getUserById(userId);
    if (!user) return null;

    const userChats = this.getUserChats(userId);
    const chatIds = userChats.map((c) => c.id).filter(Boolean);

    let newMessages = [];
    if (chatIds.length > 0 && sinceTimestamp) {
      const placeholders = chatIds.map(() => '?').join(',');
      try {
        const stmt = db.prepare(`
          SELECT 
            m.id,
            m.chat_id,
            m.sender_id,
            m.text,
            m.reply_markup,
            m.reply_to_message_id,
            COALESCE(m.is_edited, 0) as is_edited,
            m.created_at,
            m.updated_at,
            m.is_read,
            u.first_name as sender_first_name,
            u.last_name as sender_last_name,
            TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) as sender_name,
            u.username as sender_username,
            u.avatar as sender_avatar,
            u.is_bot as sender_is_bot,
            COALESCE(u.verification, 'none') as sender_verification,
            COALESCE(u.is_premium, 0) as sender_is_premium
          FROM messages m
          JOIN users u ON u.id = m.sender_id
          WHERE m.chat_id IN (${placeholders})
            AND (m.created_at > ? OR (m.updated_at IS NOT NULL AND m.updated_at > ?))
          ORDER BY m.id ASC
        `);
        const rows = stmt.all(...chatIds, sinceTimestamp, sinceTimestamp);
        newMessages = rows.map((r) => this._formatMessage(r));
      } catch (e) {
        console.error('[DB] getDeltaSync error:', e);
      }
    }

    return {
      server_time: new Date().toISOString(),
      user,
      chats: userChats,
      messages: newMessages
    };
  },

  getChatHistoryBefore(chatId, currentUserId, beforeMessageId, limit = 50) {
    const all = this.getChatMessages(chatId, currentUserId);
    if (!beforeMessageId) {
      return all.slice(-limit);
    }
    const idx = all.findIndex((m) => m.id === beforeMessageId);
    if (idx === -1) {
      return all.filter((m) => m.id < beforeMessageId).slice(-limit);
    }
    const start = Math.max(0, idx - limit);
    return all.slice(start, idx);
  }
};
