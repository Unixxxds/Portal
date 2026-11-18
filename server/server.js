import http from 'node:http';
import express from 'express';
import cors from 'cors';
import { WebSocketServer, WebSocket } from 'ws';
import crypto from 'node:crypto';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { EventEmitter } from 'node:events';
import multer from 'multer';
import webpush from 'web-push';
import { database } from './database.js';
import { sendVerificationEmail, isResendConfigured } from './emailService.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);
const PORT = process.env.PORT || 3002;

// Web Push VAPID Configuration
const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY || 'BG8pY6QBdFbRVpIpnj63bFTPws14yDFPoXV5Y5zKtT9uQpLjXSWEZzxDnFgMpLSaR-Gi4lKtR_26fHQdcQzq5eY';
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY || 'Y0GaEEOAkhpQ-SZYKDWMlD7pZlgTEIJQJ_7CLcggGmY';
const VAPID_SUBJECT = process.env.VAPID_SUBJECT || 'mailto:support@portal.chat';

try {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
} catch (vapidErr) {
  console.warn('[Web Push] VAPID initialization warning:', vapidErr.message);
}

// Bot update events emitter for fast, reactive long polling
const botEvents = new EventEmitter();
botEvents.setMaxListeners(200);

// Active callback queries for answerCallbackQuery routing
const activeCallbacks = new Map();
setInterval(() => {
  const now = Date.now();
  for (const [id, item] of activeCallbacks.entries()) {
    if (now - item.timestamp > 120000) {
      activeCallbacks.delete(id);
    }
  }
}, 60000);

// Ensure uploads folder exists
const uploadsDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Multer storage for voice messages
const voiceStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.webm';
    cb(null, `voice_${Date.now()}_${crypto.randomBytes(4).toString('hex')}${ext}`);
  }
});
const uploadVoiceMulter = multer({
  storage: voiceStorage,
  limits: { fileSize: 30 * 1024 * 1024 }
});

// Multer storage for photos / gallery images
const photoStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `photo_${Date.now()}_${crypto.randomBytes(4).toString('hex')}${ext}`);
  }
});
const uploadPhotoMulter = multer({
  storage: photoStorage,
  limits: { fileSize: 40 * 1024 * 1024 }
});

// Multer storage for videos
const videoStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.mp4';
    cb(null, `video_${Date.now()}_${crypto.randomBytes(4).toString('hex')}${ext}`);
  }
});
const uploadVideoMulter = multer({
  storage: videoStorage,
  limits: { fileSize: 100 * 1024 * 1024 } // 100MB
});

// Multer storage for documents and generic files
const fileStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '';
    const safeBase = path.basename(file.originalname, ext).replace(/[^a-zA-Z0-9_\-\u0400-\u04FF]/g, '_').slice(0, 50);
    cb(null, `file_${Date.now()}_${crypto.randomBytes(4).toString('hex')}_${safeBase}${ext}`);
  }
});
const uploadFileMulter = multer({
  storage: fileStorage,
  limits: { fileSize: 100 * 1024 * 1024 } // 100MB
});

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use('/uploads', express.static(uploadsDir));
app.use('/gifts', express.static(path.join(__dirname, '../public/gifts')));
app.use('/site', express.static(path.join(__dirname, '../site')));
app.use(express.static(path.join(__dirname, '../public')));

// Bank Acquirer & Regulatory Compliance public document endpoints
app.get('/privacy', (req, res) => res.sendFile(path.join(__dirname, '../public/privacy.html')));
app.get('/terms', (req, res) => res.sendFile(path.join(__dirname, '../public/terms.html')));
app.get('/tariffs', (req, res) => res.sendFile(path.join(__dirname, '../public/terms.html')));
app.get('/legal', (req, res) => res.sendFile(path.join(__dirname, '../public/terms.html')));

// In-memory active user sockets: Map<userId, Set<WebSocket>>
const activeSockets = new Map();

// In-memory active ringing calls: Map<callId, { callId, callerId, targetId, timeoutId, incomingPayload }>
const activeCalls = new Map();

app.get('/api/debug/sockets', (req, res) => {
  const onlineUsers = Array.from(activeSockets.entries()).map(([userId, sockets]) => ({
    userId,
    activeSocketsCount: sockets.size
  }));
  res.json({
    onlineUsers,
    totalOnlineUsers: onlineUsers.length,
    activeCalls: Array.from(activeCalls.values()).map(c => ({
      callId: c.callId,
      callerId: c.callerId,
      targetId: c.targetId
    }))
  });
});

function addActiveSocket(userId, ws) {
  const numId = Number(userId);
  if (!numId) return;
  if (!activeSockets.has(numId)) {
    activeSockets.set(numId, new Set());
  }
  activeSockets.get(numId).add(ws);
}

function removeActiveSocket(userId, ws) {
  const numId = Number(userId);
  if (!numId) return;
  if (activeSockets.has(numId)) {
    const set = activeSockets.get(numId);
    set.delete(ws);
    if (set.size === 0) {
      activeSockets.delete(numId);
    }
  }
}

function sendToUser(userId, data) {
  const numId = Number(userId);
  if (!numId) return false;
  if (activeSockets.has(numId)) {
    const payload = JSON.stringify(data);
    let sent = false;
    for (const ws of activeSockets.get(numId)) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(payload);
        sent = true;
      }
    }
    return sent;
  }
  return false;
}

// Presence & Activity Tracking Engine
function isUserOnline(userId) {
  if (!userId) return false;
  const numId = Number(userId);
  if (!activeSockets.has(numId)) return false;
  const set = activeSockets.get(numId);
  for (const s of set) {
    if (s.readyState === WebSocket.OPEN) return true;
  }
  return false;
}

function broadcastUserStatus(userId, isOnline, lastSeen) {
  try {
    const partnerIds = database.getUserContactPartnerIds(userId);
    const payload = {
      type: 'user_status',
      userId: Number(userId),
      is_online: Boolean(isOnline),
      last_seen: lastSeen || new Date().toISOString()
    };
    for (const pId of partnerIds) {
      sendToUser(pId, payload);
    }
  } catch (err) {
    console.error('[PRESENCE] broadcastUserStatus error:', err);
  }
}

function handleUserSocketConnect(userId, ws) {
  const numId = Number(userId);
  if (!numId) return;
  const wasOnline = isUserOnline(numId);
  addActiveSocket(numId, ws);

  const nowIso = new Date().toISOString();
  database.updateUserLastSeen(numId, nowIso);

  const u = database.getUserById(numId);
  const name = u ? `${u.first_name || ''} ${u.last_name || ''}`.trim() : `User #${numId}`;
  console.log(`[WS] ${name} (ID: ${numId}) CONNECTED. Online users: [${Array.from(activeSockets.keys()).join(', ')}]`);

  // Deliver any pending incoming call for this user
  for (const [cId, callInfo] of activeCalls.entries()) {
    if (callInfo.targetId === numId) {
      console.log(`[CALL] Delivering pending call ${cId} to newly connected user ${numId}`);
      sendToUser(numId, callInfo.incomingPayload);
    }
  }

  if (!wasOnline) {
    broadcastUserStatus(numId, true, nowIso);
  }
}

function handleUserSocketDisconnect(userId, ws) {
  const numId = Number(userId);
  if (!numId) return;
  removeActiveSocket(numId, ws);
  const isStillOnline = isUserOnline(numId);

  console.log(`[WS] User ID ${numId} DISCONNECTED. Still online: ${isStillOnline}. Online users: [${Array.from(activeSockets.keys()).join(', ')}]`);

  if (!isStillOnline) {
    const nowIso = new Date().toISOString();
    database.updateUserLastSeen(numId, nowIso);
    broadcastUserStatus(numId, false, nowIso);
  }
}

function enrichChatWithOnline(chat) {
  if (!chat) return chat;
  const isDirect = !chat.is_channel && !chat.is_group;
  const isOnline = isDirect && !chat.is_bot && isUserOnline(chat.participant_id);
  return {
    ...chat,
    is_online: isOnline,
    last_seen: chat.last_seen || null
  };
}

// Authentication Middleware
function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Необходима авторизация' });
  }
  const token = authHeader.split(' ')[1];
  const user = database.getUserByToken(token);
  if (!user) {
    return res.status(401).json({ error: 'Недействительный токен авторизации' });
  }
  req.user = user;
  req.token = token;
  next();
}

// Strict Admin Authorization Middleware
function adminMiddleware(req, res, next) {
  authMiddleware(req, res, () => {
    const freshUser = database.getUserById(req.user.id);
    if (!freshUser) {
      return res.status(401).json({ error: 'Пользователь не найден' });
    }
    const isAdmin = Boolean(freshUser.is_admin) || freshUser.verification === 'dev' || freshUser.id === 1;
    if (!isAdmin) {
      console.warn(`[Security Alert] Unauthorized admin access attempt: User ID ${freshUser.id} (${freshUser.username || freshUser.phone}) from IP ${req.ip}`);
      return res.status(403).json({ error: 'Доступ запрещён: требуются права администратора Portal' });
    }
    req.adminUser = freshUser;
    next();
  });
}

function optionalAuthMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    const user = database.getUserByToken(token);
    if (user) req.user = user;
  }
  next();
}

// ================= WEB PUSH NOTIFICATION ENGINE =================
function formatPushBody(text) {
  if (!text) return 'Новое сообщение';
  if (text.startsWith('[PORTAL_PHOTO]:')) {
    try {
      const data = JSON.parse(text.slice('[PORTAL_PHOTO]:'.length));
      return data.caption ? `📷 ${data.caption}` : '📷 Фотография';
    } catch (_) {
      return '📷 Фотография';
    }
  }
  if (text.startsWith('[PORTAL_VOICE]:')) {
    return '🎤 Голосовое сообщение';
  }
  if (text.startsWith('[PORTAL_STICKER]:')) {
    return '✨ Стикер';
  }
  if (text.startsWith('[PORTAL_GIFT]:')) {
    try {
      const data = JSON.parse(text.slice('[PORTAL_GIFT]:'.length));
      return `🎁 Подарок: ${data.giftName || 'Подарок'}`;
    } catch (_) {
      return '🎁 Подарок';
    }
  }
  if (text.startsWith('[PORTAL_SYSTEM]:')) {
    return text.slice('[PORTAL_SYSTEM]:'.length);
  }
  return text.length > 120 ? text.slice(0, 117) + '...' : text;
}

async function sendPushNotificationToUser(userId, payload) {
  if (!userId) return;
  try {
    const subs = database.getPushSubscriptionsForUser(userId);
    if (!subs || subs.length === 0) return;

    const pushData = JSON.stringify(payload);

    for (const sub of subs) {
      const pushSubscription = {
        endpoint: sub.endpoint,
        keys: {
          p256dh: sub.p256dh,
          auth: sub.auth
        }
      };

      webpush.sendNotification(pushSubscription, pushData).catch((err) => {
        if (err.statusCode === 404 || err.statusCode === 410) {
          database.deletePushSubscription(sub.endpoint);
        } else {
          console.warn(`[Web Push] Error sending to user ${userId}:`, err.message || err);
        }
      });
    }
  } catch (err) {
    console.warn('[Web Push] dispatch error:', err);
  }
}

function notifyUserNewMessage(targetUserId, message, chatId, senderId) {
  if (!targetUserId || targetUserId === senderId) return;
  const sender = database.getUserById(senderId);
  const senderName = sender
    ? `${sender.first_name || ''} ${sender.last_name || ''}`.trim() || `@${sender.username}`
    : 'Portal';

  const payload = {
    title: senderName,
    body: formatPushBody(message.text),
    icon: (sender?.avatar && !sender.avatar.startsWith('data:')) ? sender.avatar : '/icons/icon-192.png',
    badge: '/icons/badge-72.png',
    tag: `portal_chat_${chatId}`,
    data: {
      chatId: chatId,
      url: `/?chat=${chatId}`
    }
  };

  sendPushNotificationToUser(targetUserId, payload);
}

// ================= BOTFATHER INTERACTION ENGINE =================
function getBotManageCard(targetBot) {
  const text = 
`🤖 Управление ботом **${targetBot.first_name}** (@${targetBot.username}):

🏷 **Имя:** ${targetBot.first_name}
📝 **Описание:** ${targetBot.description || 'Не установлено'}
🔑 **API Токен:**
\`${targetBot.bot_token}\`

Выберите действие для настройки:`;

  const markup = {
    inline_keyboard: [
      [
        { text: '✏️ Изменить имя', callback_data: `bf_setname_${targetBot.id}` },
        { text: '📝 Изменить описание', callback_data: `bf_setdesc_${targetBot.id}` }
      ],
      [
        { text: '🔑 Показать токен', callback_data: `bf_token_${targetBot.id}` }
      ],
      [
        { text: '« К списку ботов', callback_data: 'bf_mybots' }
      ]
    ]
  };

  return { text, markup };
}

function processBotFatherMessage({ chatId, userId, text, botFather }) {
  const trimmed = text.trim();
  const lower = trimmed.toLowerCase();
  let replyText = '';
  let replyMarkup = null;

  if (lower === '/start') {
    database.clearBotFatherSession(userId);
    replyText = 
`👋 Привет! Я — BotFather, официальный бот для создания и управления ботами в Portal.

Вы можете управлять мной с помощью кнопок ниже или команд:
/newbot — создать нового бота
/mybots — список ваших ботов и настройки
/setname — изменить имя бота
/setdescription — изменить описание бота
/token — получить API токен бота
/terms — условия оферты и тарифы
/privacy — политика конфиденциальности
/support — контакты службы поддержки
/cancel — отменить текущую операцию
/help — справка по командам`;

    replyMarkup = {
      inline_keyboard: [
        [
          { text: '➕ Создать нового бота', callback_data: 'bf_newbot' },
          { text: '📋 Мои боты', callback_data: 'bf_mybots' }
        ],
        [
          { text: '✏️ Изменить имя', callback_data: 'bf_setname' },
          { text: '📝 Изменить описание', callback_data: 'bf_setdesc' }
        ],
        [
          { text: '📜 Условия и тарифы', callback_data: 'bf_terms' },
          { text: '🔒 Конфиденциальность', callback_data: 'bf_privacy' }
        ],
        [
          { text: '💬 Поддержка', callback_data: 'bf_support' },
          { text: '❓ Справка', callback_data: 'bf_help' }
        ]
      ]
    };
  } else if (lower === '/cancel') {
    database.clearBotFatherSession(userId);
    replyText = `Действие отменено. Чем ещё могу помочь? Используйте кнопки ниже:`;
    replyMarkup = {
      inline_keyboard: [
        [
          { text: '➕ Создать бота', callback_data: 'bf_newbot' },
          { text: '📋 Мои боты', callback_data: 'bf_mybots' }
        ],
        [
          { text: '✏️ Изменить имя', callback_data: 'bf_setname' },
          { text: '📝 Изменить описание', callback_data: 'bf_setdesc' }
        ]
      ]
    };
  } else if (lower === '/help') {
    replyText = 
`📖 Справка по командам BotFather:

🤖 **Создание и управление:**
/newbot — пошаговый мастер создания бота
/mybots — список всех ваших ботов и их настройки

⚙️ **Редактирование ботов:**
/setname — изменить имя бота
/setdescription — изменить описание бота
/token — получить или скопировать API токен бота

🛠 **Прочее:**
/cancel — прервать текущий ввод
/help — показать эту справку`;

    replyMarkup = {
      inline_keyboard: [
        [
          { text: '➕ Создать бота', callback_data: 'bf_newbot' },
          { text: '📋 Мои боты', callback_data: 'bf_mybots' }
        ],
        [
          { text: '✏️ Изменить имя', callback_data: 'bf_setname' },
          { text: '📝 Изменить описание', callback_data: 'bf_setdesc' }
        ],
        [
          { text: '❌ Отмена', callback_data: 'bf_cancel' }
        ]
      ]
    };
  } else if (lower === '/terms' || lower === '/tariffs') {
    replyText = 
`📜 **Пользовательское соглашение и тарифы Portal**
Дата актуализации: 29 октября 2026 г.

💎 **Тарифные планы Portal Premium:**
• 1 месяц — **299 ₽**
• 3 месяца — **799 ₽** (скидка 11%, 266 ₽/мес)
• 12 месяцев — **2 490 ₽** (скидка 30%, 207 ₽/мес)

✨ **В подписку входит:**
• Загрузка файлов до 4 ГБ без сжатия
• Анимированные GIF/видео баннеры и аватары
• Расшифровка голосовых сообщений
• Перевод сообщений на десятки языков
• До 20 ботов в BotFather вместо 5
• Эксклюзивная звезда Premium около имени
• Приоритетная служба поддержки

💳 Оплата банковскими картами (МИР, Visa, Mastercard). Услуга предоставляется сразу в цифровом виде.
Возврат средств: в течение 24 часов при обращении в поддержку.

🔗 Полный текст соглашения доступен по ссылке:
https://portalmsg.ru/terms.html`;

    replyMarkup = {
      inline_keyboard: [
        [
          { text: '🔒 Конфиденциальность', callback_data: 'bf_privacy' },
          { text: '💬 Поддержка', callback_data: 'bf_support' }
        ],
        [
          { text: '« Главное меню', callback_data: 'bf_start' }
        ]
      ]
    };
  } else if (lower === '/privacy') {
    replyText = 
`🔒 **Политика конфиденциальности Portal**
Дата вступления в силу: 29 октября 2026 г.

Сервис Portal уважает вашу конфиденциальность и обеспечивает надёжную защиту данных:
• Все данные передаются по защищённым протоколам шифрования TLS/SSL.
• Персональные данные хранятся в защищённом дата-центре на территории РФ в строгом соответствии с 152-ФЗ.
• Мы никогда не передаём и не продаём ваши данные третьим лицам.
• Банковские платежи обрабатываются сертифицированным платёжным шлюзом банка (PCI DSS Level 1). Данные карт не сохраняются на наших серверах.

🔗 Полный текст политики конфиденциальности:
https://portalmsg.ru/privacy.html`;

    replyMarkup = {
      inline_keyboard: [
        [
          { text: '📜 Условия и тарифы', callback_data: 'bf_terms' },
          { text: '💬 Поддержка', callback_data: 'bf_support' }
        ],
        [
          { text: '« Главное меню', callback_data: 'bf_start' }
        ]
      ]
    };
  } else if (lower === '/support') {
    replyText = 
`💬 **Служба клиентской поддержки Portal**

Мы на связи и готовы помочь по любым вопросам работы мессенджера, подписки или проведения платежей:

📧 **Email поддержки:** support@portalmsg.ru
👤 **Официальный юзернейм:** @support
🕒 **График работы:** ежедневно с 09:00 до 21:00 (МСК)
⏱ **Срок ответа:** в течение 24 часов

Для решения вопросов возврата средств, пожалуйста, отправьте заявку на электронную почту с темой "Возврат средств".`;

    replyMarkup = {
      inline_keyboard: [
        [
          { text: '📜 Условия и тарифы', callback_data: 'bf_terms' },
          { text: '🔒 Конфиденциальность', callback_data: 'bf_privacy' }
        ],
        [
          { text: '« Главное меню', callback_data: 'bf_start' }
        ]
      ]
    };
  } else if (lower === '/mybots') {
    const userBots = database.getUserBots(userId);
    if (!userBots || userBots.length === 0) {
      replyText = `У вас пока нет созданных ботов. Нажмите кнопку ниже, чтобы создать своего первого бота! 🚀`;
      replyMarkup = {
        inline_keyboard: [
          [{ text: '➕ Создать бота', callback_data: 'bf_newbot' }]
        ]
      };
    } else {
      replyText = `🤖 Ваши боты (${userBots.length}):\n\n` + userBots.map((b, i) => (
        `${i + 1}. **${b.first_name}** (@${b.username})\n` +
        `   Описание: ${b.description || 'Не установлено'}\n` +
        `   Токен: \`${b.bot_token}\`\n`
      )).join('\n') + `Выберите бота для настройки его имени, описания или получения токена:`;

      const botButtons = userBots.map(b => [
        { text: `⚙️ @${b.username} (${b.first_name})`, callback_data: `bf_manage_${b.id}` }
      ]);
      botButtons.push([
        { text: '➕ Создать ещё одного бота', callback_data: 'bf_newbot' }
      ]);

      replyMarkup = {
        inline_keyboard: botButtons
      };
    }
  } else if (lower === '/newbot') {
    const userBots = database.getUserBots(userId) || [];
    const currentUser = database.getUserById(userId);
    const isPremium = Boolean(currentUser?.is_premium);
    const maxBots = isPremium ? 20 : 5;

    if (userBots.length >= maxBots) {
      if (!isPremium) {
        replyText = 
`⚠️ Достигнут лимит ботов (${userBots.length} из ${maxBots} для стандартных аккаунтов).

✨ Подключите Portal Premium, чтобы создавать до 20 ботов!`;
      } else {
        replyText = `⚠️ Вы достигли максимального лимита ботов (${maxBots}). Удалите одного из ботов, чтобы создать нового.`;
      }
      replyMarkup = {
        inline_keyboard: [
          [{ text: '📋 Мои боты', callback_data: 'bf_mybots' }]
        ]
      };
    } else {
      database.setBotFatherSession(userId, 'WAITING_FOR_BOT_NAME', null);
      replyText = 
`Отлично, давайте создадим нового бота! 🤖 (${userBots.length + 1}/${maxBots})

Как мы его назовём? Пожалуйста, введите имя для вашего бота (например: My Assistant или Portal Weather):`;
      replyMarkup = {
        inline_keyboard: [
          [{ text: '❌ Отменить создание', callback_data: 'bf_cancel' }]
        ]
      };
    }
  } else if (lower.startsWith('/setname')) {
    const userBots = database.getUserBots(userId);
    if (!userBots || userBots.length === 0) {
      replyText = `У вас пока нет созданных ботов. Создайте бота с помощью /newbot!`;
      replyMarkup = {
        inline_keyboard: [[{ text: '➕ Создать бота', callback_data: 'bf_newbot' }]]
      };
    } else {
      const parts = trimmed.split(/\s+/);
      // Case 1: /setname @botname New Name Here
      if (parts.length >= 3 && (parts[1].startsWith('@') || userBots.some(b => b.username.toLowerCase() === parts[1].toLowerCase().replace(/^@+/, '')))) {
        const targetUsername = parts[1].toLowerCase().replace(/^@+/, '');
        const targetBot = userBots.find(b => b.username.toLowerCase() === targetUsername);
        if (!targetBot) {
          replyText = `❌ Бот @${targetUsername} не найден среди ваших ботов.`;
        } else {
          const newName = parts.slice(2).join(' ').trim();
          if (newName.length < 1 || newName.length > 64) {
            replyText = `Имя бота должно содержать от 1 до 64 символов.`;
          } else {
            database.updateBotName(targetBot.id, userId, newName);
            database.clearBotFatherSession(userId);
            replyText = `✅ Успешно! Новое имя для @${targetBot.username}: **${newName}**`;
            replyMarkup = {
              inline_keyboard: [
                [
                  { text: `⚙️ Управление @${targetBot.username}`, callback_data: `bf_manage_${targetBot.id}` },
                  { text: '📋 Мои боты', callback_data: 'bf_mybots' }
                ]
              ]
            };
          }
        }
      } 
      // Case 2: /setname @botname
      else if (parts.length === 2 && (parts[1].startsWith('@') || userBots.some(b => b.username.toLowerCase() === parts[1].toLowerCase().replace(/^@+/, '')))) {
        const targetUsername = parts[1].toLowerCase().replace(/^@+/, '');
        const targetBot = userBots.find(b => b.username.toLowerCase() === targetUsername);
        if (!targetBot) {
          replyText = `❌ Бот @${targetUsername} не найден среди ваших ботов.`;
        } else {
          database.setBotFatherSession(userId, 'WAITING_FOR_EDIT_NAME', null, targetBot.id);
          replyText = `Текущее имя бота: **${targetBot.first_name}** (@${targetBot.username}).\n\nПожалуйста, введите новое имя для бота (от 1 до 64 символов):`;
          replyMarkup = {
            inline_keyboard: [
              [{ text: '❌ Отмена', callback_data: 'bf_cancel' }]
            ]
          };
        }
      } 
      // Case 3: /setname (no arguments)
      else {
        if (userBots.length === 1) {
          const targetBot = userBots[0];
          database.setBotFatherSession(userId, 'WAITING_FOR_EDIT_NAME', null, targetBot.id);
          replyText = `Текущее имя бота: **${targetBot.first_name}** (@${targetBot.username}).\n\nПожалуйста, введите новое имя для бота (от 1 до 64 символов):`;
          replyMarkup = {
            inline_keyboard: [
              [{ text: '❌ Отмена', callback_data: 'bf_cancel' }]
            ]
          };
        } else {
          replyText = `Выберите бота, имя которого вы хотите изменить:`;
          const buttons = userBots.map(b => [
            { text: `✏️ ${b.first_name} (@${b.username})`, callback_data: `bf_setname_${b.id}` }
          ]);
          buttons.push([{ text: '❌ Отмена', callback_data: 'bf_cancel' }]);
          replyMarkup = { inline_keyboard: buttons };
        }
      }
    }
  } else if (lower.startsWith('/setdescription')) {
    const userBots = database.getUserBots(userId);
    if (!userBots || userBots.length === 0) {
      replyText = `У вас пока нет созданных ботов. Создайте бота с помощью /newbot!`;
      replyMarkup = {
        inline_keyboard: [[{ text: '➕ Создать бота', callback_data: 'bf_newbot' }]]
      };
    } else {
      const parts = trimmed.split(/\s+/);
      // Case 1: /setdescription @botname New Description Text...
      if (parts.length >= 3 && (parts[1].startsWith('@') || userBots.some(b => b.username.toLowerCase() === parts[1].toLowerCase().replace(/^@+/, '')))) {
        const targetUsername = parts[1].toLowerCase().replace(/^@+/, '');
        const targetBot = userBots.find(b => b.username.toLowerCase() === targetUsername);
        if (!targetBot) {
          replyText = `❌ Бот @${targetUsername} не найден среди ваших ботов.`;
        } else {
          const newDesc = parts.slice(2).join(' ').trim();
          if (newDesc.length > 512) {
            replyText = `Описание бота не должно превышать 512 символов.`;
          } else {
            database.updateBotDescription(targetBot.id, userId, newDesc);
            database.clearBotFatherSession(userId);
            replyText = `✅ Успешно! Описание для @${targetBot.username} обновлено:\n\n"${newDesc}"`;
            replyMarkup = {
              inline_keyboard: [
                [
                  { text: `⚙️ Управление @${targetBot.username}`, callback_data: `bf_manage_${targetBot.id}` },
                  { text: '📋 Мои боты', callback_data: 'bf_mybots' }
                ]
              ]
            };
          }
        }
      } 
      // Case 2: /setdescription @botname
      else if (parts.length === 2 && (parts[1].startsWith('@') || userBots.some(b => b.username.toLowerCase() === parts[1].toLowerCase().replace(/^@+/, '')))) {
        const targetUsername = parts[1].toLowerCase().replace(/^@+/, '');
        const targetBot = userBots.find(b => b.username.toLowerCase() === targetUsername);
        if (!targetBot) {
          replyText = `❌ Бот @${targetUsername} не найден среди ваших ботов.`;
        } else {
          database.setBotFatherSession(userId, 'WAITING_FOR_EDIT_DESCRIPTION', null, targetBot.id);
          replyText = `Текущее описание для @${targetBot.username}:\n"${targetBot.description || 'Не установлено'}"\n\nПожалуйста, введите новое описание для бота (до 512 символов):`;
          replyMarkup = {
            inline_keyboard: [
              [{ text: '❌ Отмена', callback_data: 'bf_cancel' }]
            ]
          };
        }
      } 
      // Case 3: /setdescription (no arguments)
      else {
        if (userBots.length === 1) {
          const targetBot = userBots[0];
          database.setBotFatherSession(userId, 'WAITING_FOR_EDIT_DESCRIPTION', null, targetBot.id);
          replyText = `Текущее описание для @${targetBot.username}:\n"${targetBot.description || 'Не установлено'}"\n\nПожалуйста, введите новое описание для бота (до 512 символов):`;
          replyMarkup = {
            inline_keyboard: [
              [{ text: '❌ Отмена', callback_data: 'bf_cancel' }]
            ]
          };
        } else {
          replyText = `Выберите бота, описание которого вы хотите изменить:`;
          const buttons = userBots.map(b => [
            { text: `📝 ${b.first_name} (@${b.username})`, callback_data: `bf_setdesc_${b.id}` }
          ]);
          buttons.push([{ text: '❌ Отмена', callback_data: 'bf_cancel' }]);
          replyMarkup = { inline_keyboard: buttons };
        }
      }
    }
  } else if (lower.startsWith('/token')) {
    const userBots = database.getUserBots(userId);
    if (!userBots || userBots.length === 0) {
      replyText = `У вас пока нет созданных ботов. Создайте бота с помощью /newbot!`;
      replyMarkup = {
        inline_keyboard: [[{ text: '➕ Создать бота', callback_data: 'bf_newbot' }]]
      };
    } else {
      const parts = trimmed.split(/\s+/);
      if (parts.length >= 2) {
        const targetUsername = parts[1].toLowerCase().replace(/^@+/, '');
        const targetBot = userBots.find(b => b.username.toLowerCase() === targetUsername);
        if (!targetBot) {
          replyText = `❌ Бот @${targetUsername} не найден среди ваших ботов.`;
        } else {
          replyText = `🔑 API Токен для @${targetBot.username}:\n\`${targetBot.bot_token}\`\n\n🌐 Базовый адрес API:\nhttps://api.portalmsg.ru/bot${targetBot.bot_token}/<METHOD>\n\nНикому не передавайте этот токен.`;
          replyMarkup = {
            inline_keyboard: [
              [{ text: `⚙️ Управление @${targetBot.username}`, callback_data: `bf_manage_${targetBot.id}` }]
            ]
          };
        }
      } else {
        if (userBots.length === 1) {
          const targetBot = userBots[0];
          replyText = `🔑 API Токен для @${targetBot.username}:\n\`${targetBot.bot_token}\`\n\n🌐 Базовый адрес API:\nhttps://api.portalmsg.ru/bot${targetBot.bot_token}/<METHOD>\n\nНикому не передавайте этот токен.`;
          replyMarkup = {
            inline_keyboard: [
              [{ text: `⚙️ Управление @${targetBot.username}`, callback_data: `bf_manage_${targetBot.id}` }]
            ]
          };
        } else {
          replyText = `Выберите бота, для которого вы хотите получить токен:`;
          const buttons = userBots.map(b => [
            { text: `🔑 Токен @${b.username}`, callback_data: `bf_token_${b.id}` }
          ]);
          buttons.push([{ text: '❌ Отмена', callback_data: 'bf_cancel' }]);
          replyMarkup = { inline_keyboard: buttons };
        }
      }
    }
  } else {
    // Check user's current session state
    const session = database.getBotFatherSession(userId);
    if (session && session.step === 'WAITING_FOR_BOT_NAME') {
      const botName = trimmed;
      if (botName.length < 1 || botName.length > 64) {
        replyText = `Имя бота должно содержать от 1 до 64 символов. Пожалуйста, введите корректное имя:`;
        replyMarkup = {
          inline_keyboard: [
            [{ text: '❌ Отменить', callback_data: 'bf_cancel' }]
          ]
        };
      } else {
        database.setBotFatherSession(userId, 'WAITING_FOR_BOT_USERNAME', botName);
        replyText = 
`Хорошо! Имя бота: "${botName}".

Теперь выберите юзернейм (@username) для вашего бота.
⚠️ Важно: юзернейм обязан заканчиваться на "bot" (например: TetrisBot или tetris_bot).
Разрешены только латинские буквы, цифры и символ подчёркивания (от 3 до 32 символов).`;
        replyMarkup = {
          inline_keyboard: [
            [{ text: '❌ Отменить', callback_data: 'bf_cancel' }]
          ]
        };
      }
    } else if (session && session.step === 'WAITING_FOR_BOT_USERNAME') {
      const cleanUsername = trimmed.toLowerCase().replace(/^@+/, '');

      if (!cleanUsername.endsWith('bot')) {
        replyText = `❌ Ошибка: юзернейм бота обязан заканчиваться на "bot" (например: sample_bot или HelperBot). Попробуйте ещё раз:`;
        replyMarkup = {
          inline_keyboard: [
            [{ text: '❌ Отменить', callback_data: 'bf_cancel' }]
          ]
        };
      } else if (!/^[a-z0-9_]{3,32}$/.test(cleanUsername)) {
        replyText = `❌ Юзернейм должен содержать от 3 до 32 символов (латинские буквы, цифры и _). Попробуйте ещё раз:`;
        replyMarkup = {
          inline_keyboard: [
            [{ text: '❌ Отменить', callback_data: 'bf_cancel' }]
          ]
        };
      } else if (!database.isUsernameAvailable(cleanUsername)) {
        replyText = `❌ К сожалению, юзернейм @${cleanUsername} уже занят. Пожалуйста, выберите другое имя:`;
        replyMarkup = {
          inline_keyboard: [
            [{ text: '❌ Отменить', callback_data: 'bf_cancel' }]
          ]
        };
      } else {
        // Success: generate official format token and create bot user
        const tokenPrefix = Math.floor(100000000 + Math.random() * 900000000);
        const randomSecret = crypto.randomBytes(16).toString('base64url');
        const token = `${tokenPrefix}:AAF${randomSecret}`;

        const newBot = database.createBotUser({
          ownerId: userId,
          firstName: session.draft_name || cleanUsername,
          username: cleanUsername,
          token,
          description: `Бот создан пользователем через @BotFather`
        });

        database.clearBotFatherSession(userId);

        replyText = 
`Готово! Поздравляем с созданием нового бота! 🎉

Вы можете найти его в поиске Portal: @${newBot.username}

Используйте этот токен для доступа к Portal Bot API:
\`${newBot.bot_token}\`

🌐 Базовый адрес API:
https://api.portalmsg.ru/bot${newBot.bot_token}/<METHOD>

Храните ваш токен в секрете! Он позволяет полностью управлять ботом через API.

Документация по API доступна в файле BOT_API.md
Тестовый скрипт для запуска: test_bot.py`;

        replyMarkup = {
          inline_keyboard: [
            [
              { text: `⚙️ Управление @${newBot.username}`, callback_data: `bf_manage_${newBot.id}` },
              { text: '📋 Мои боты', callback_data: 'bf_mybots' }
            ]
          ]
        };
      }
    } else if (session && session.step === 'WAITING_FOR_EDIT_NAME') {
      const targetBot = database.getBotById(session.target_bot_id);
      if (!targetBot || targetBot.bot_owner_id !== userId) {
        database.clearBotFatherSession(userId);
        replyText = `❌ Ошибка: бот не найден или у вас нет прав на его редактирование.`;
      } else {
        const newName = trimmed;
        if (newName.length < 1 || newName.length > 64) {
          replyText = `Имя бота должно содержать от 1 до 64 символов. Попробуйте ещё раз:`;
          replyMarkup = {
            inline_keyboard: [[{ text: '❌ Отменить', callback_data: 'bf_cancel' }]]
          };
        } else {
          database.updateBotName(targetBot.id, userId, newName);
          database.clearBotFatherSession(userId);
          replyText = `✅ Имя бота @${targetBot.username} успешно изменено на **${newName}**!`;
          replyMarkup = {
            inline_keyboard: [
              [
                { text: `⚙️ Управление @${targetBot.username}`, callback_data: `bf_manage_${targetBot.id}` },
                { text: '📋 Мои боты', callback_data: 'bf_mybots' }
              ]
            ]
          };
        }
      }
    } else if (session && session.step === 'WAITING_FOR_EDIT_DESCRIPTION') {
      const targetBot = database.getBotById(session.target_bot_id);
      if (!targetBot || targetBot.bot_owner_id !== userId) {
        database.clearBotFatherSession(userId);
        replyText = `❌ Ошибка: бот не найден или у вас нет прав на его редактирование.`;
      } else {
        const newDesc = trimmed;
        if (newDesc.length > 512) {
          replyText = `Описание бота не должно превышать 512 символов. Попробуйте ещё раз:`;
          replyMarkup = {
            inline_keyboard: [[{ text: '❌ Отменить', callback_data: 'bf_cancel' }]]
          };
        } else {
          database.updateBotDescription(targetBot.id, userId, newDesc);
          database.clearBotFatherSession(userId);
          replyText = `✅ Описание для @${targetBot.username} успешно обновлено!\n\n"${newDesc}"`;
          replyMarkup = {
            inline_keyboard: [
              [
                { text: `⚙️ Управление @${targetBot.username}`, callback_data: `bf_manage_${targetBot.id}` },
                { text: '📋 Мои боты', callback_data: 'bf_mybots' }
              ]
            ]
          };
        }
      }
    } else {
      replyText = `Я не понял эту команду. Используйте кнопки ниже для выбора действия:`;
      replyMarkup = {
        inline_keyboard: [
          [
            { text: '➕ Создать бота', callback_data: 'bf_newbot' },
            { text: '📋 Мои боты', callback_data: 'bf_mybots' }
          ],
          [
            { text: '✏️ Изменить имя', callback_data: 'bf_setname' },
            { text: '📝 Изменить описание', callback_data: 'bf_setdesc' }
          ],
          [
            { text: '❓ Справка', callback_data: 'bf_help' }
          ]
        ]
      };
    }
  }

  // Save BotFather's response message into database
  const botMessage = database.saveMessage(chatId, botFather.id, replyText, replyMarkup);

  // Broadcast to user via WebSocket
  const payload = {
    type: 'new_message',
    message: botMessage,
    chatId
  };
  sendToUser(userId, payload);
  sendToUser(userId, {
    type: 'chat_updated',
    chatId,
    lastMessage: botMessage,
    unreadCount: 0
  });

  notifyUserNewMessage(userId, botMessage, chatId, botFather.id);
}

// User callback query processor for inline keyboard button interactions
function handleCallbackQuery({ userId, chatId, messageId, data, callbackQueryId }) {
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(userId)) {
    return false;
  }

  const message = database.getMessageById(messageId, userId);
  if (!message || message.chat_id !== chatId) {
    return false;
  }

  const bot = database.getUserById(message.sender_id);
  if (!bot || !bot.is_bot) {
    return false;
  }

  // Built-in BotFather handling
  if (bot.username === 'botfather') {
    if (data === 'bf_newbot') {
      processBotFatherMessage({ chatId, userId, text: '/newbot', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Запуск мастера создания бота...',
        showAlert: false
      });
    } else if (data === 'bf_mybots') {
      processBotFatherMessage({ chatId, userId, text: '/mybots', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Список ваших ботов',
        showAlert: false
      });
    } else if (data === 'bf_setname') {
      processBotFatherMessage({ chatId, userId, text: '/setname', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Изменение имени бота',
        showAlert: false
      });
    } else if (data === 'bf_terms') {
      processBotFatherMessage({ chatId, userId, text: '/terms', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Условия оферты и тарифы Portal',
        showAlert: false
      });
    } else if (data === 'bf_privacy') {
      processBotFatherMessage({ chatId, userId, text: '/privacy', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Политика конфиденциальности Portal',
        showAlert: false
      });
    } else if (data === 'bf_support') {
      processBotFatherMessage({ chatId, userId, text: '/support', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Контакты поддержки: support@portalmsg.ru',
        showAlert: false
      });
    } else if (data === 'bf_start') {
      processBotFatherMessage({ chatId, userId, text: '/start', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Главное меню BotFather',
        showAlert: false
      });
    } else if (data.startsWith('bf_setname_')) {
      const bId = Number(data.slice('bf_setname_'.length));
      const targetBot = database.getBotById(bId);
      if (targetBot && targetBot.bot_owner_id === userId) {
        database.setBotFatherSession(userId, 'WAITING_FOR_EDIT_NAME', null, bId);
        const promptMsg = database.saveMessage(chatId, bot.id, `Текущее имя бота: **${targetBot.first_name}** (@${targetBot.username}).\n\nПожалуйста, введите новое имя для бота (от 1 до 64 символов):`, {
          inline_keyboard: [[{ text: '❌ Отмена', callback_data: 'bf_cancel' }]]
        });
        sendToUser(userId, {
          type: 'new_message',
          message: promptMsg,
          chatId
        });
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: `Введите новое имя для @${targetBot.username}`,
          showAlert: false
        });
      } else {
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: 'Бот не найден или нет доступа',
          showAlert: true
        });
      }
    } else if (data === 'bf_setdesc') {
      processBotFatherMessage({ chatId, userId, text: '/setdescription', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Изменение описания бота',
        showAlert: false
      });
    } else if (data.startsWith('bf_setdesc_')) {
      const bId = Number(data.slice('bf_setdesc_'.length));
      const targetBot = database.getBotById(bId);
      if (targetBot && targetBot.bot_owner_id === userId) {
        database.setBotFatherSession(userId, 'WAITING_FOR_EDIT_DESCRIPTION', null, bId);
        const promptMsg = database.saveMessage(chatId, bot.id, `Текущее описание для @${targetBot.username}:\n"${targetBot.description || 'Не установлено'}"\n\nПожалуйста, введите новое описание для бота (до 512 символов):`, {
          inline_keyboard: [[{ text: '❌ Отмена', callback_data: 'bf_cancel' }]]
        });
        sendToUser(userId, {
          type: 'new_message',
          message: promptMsg,
          chatId
        });
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: `Введите новое описание для @${targetBot.username}`,
          showAlert: false
        });
      } else {
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: 'Бот не найден или нет доступа',
          showAlert: true
        });
      }
    } else if (data.startsWith('bf_manage_')) {
      const bId = Number(data.slice('bf_manage_'.length));
      const targetBot = database.getBotById(bId);
      if (targetBot && targetBot.bot_owner_id === userId) {
        const { text: cardText, markup: cardMarkup } = getBotManageCard(targetBot);
        const cardMsg = database.saveMessage(chatId, bot.id, cardText, cardMarkup);
        sendToUser(userId, {
          type: 'new_message',
          message: cardMsg,
          chatId
        });
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: `Управление @${targetBot.username}`,
          showAlert: false
        });
      } else {
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: 'Бот не найден или нет доступа',
          showAlert: true
        });
      }
    } else if (data === 'bf_help') {
      processBotFatherMessage({ chatId, userId, text: '/help', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Справка BotFather',
        showAlert: false
      });
    } else if (data === 'bf_cancel') {
      processBotFatherMessage({ chatId, userId, text: '/cancel', botFather: bot });
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Операция отменена',
        showAlert: false
      });
    } else if (data.startsWith('bf_token_')) {
      const bId = Number(data.slice('bf_token_'.length));
      const targetBot = database.getBotById(bId);
      if (targetBot && targetBot.bot_owner_id === userId) {
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: `Токен для @${targetBot.username}:\n${targetBot.bot_token}`,
          showAlert: true
        });
        const tokenMsg = database.saveMessage(chatId, bot.id, `🔑 **API Токен для @${targetBot.username}**:\n\`${targetBot.bot_token}\`\n\n🌐 Базовый адрес API:\nhttps://api.portalmsg.ru/bot${targetBot.bot_token}/<METHOD>\n\nНикому не передавайте этот токен.`);
        sendToUser(userId, {
          type: 'new_message',
          message: tokenMsg,
          chatId
        });
      } else {
        sendToUser(userId, {
          type: 'callback_query_answered',
          callbackQueryId,
          text: 'Бот не найден или нет доступа',
          showAlert: true
        });
      }
    } else {
      sendToUser(userId, {
        type: 'callback_query_answered',
        callbackQueryId,
        text: 'Команда получена',
        showAlert: false
      });
    }
    return true;
  }

  // Custom user bot handling
  activeCallbacks.set(callbackQueryId, {
    userId,
    chatId,
    messageId,
    data,
    timestamp: Date.now()
  });

  database.addBotUpdate({
    botId: bot.id,
    chatId,
    messageId,
    updateType: 'callback_query',
    callbackId: callbackQueryId,
    callbackData: data,
    userId
  });

  botEvents.emit('update', bot.id);
  return true;
}

// Outgoing message pipeline for both WebSocket and REST
function handleOutgoingUserMessage({ chatId, senderId, text, replyToMessageId = null }) {
  // Check if this chat is a channel or group
  const channel = database.getChannelByChatId(chatId);
  const group = database.getGroupByChatId(chatId);

  if (channel && channel.owner_id !== senderId) {
    throw new Error('Только владелец канала может публиковать сообщения');
  }

  if (group) {
    const participants = database.getChatParticipantUserIds(chatId);
    if (!participants.includes(senderId)) {
      throw new Error('Вы не являетесь участником этой группы');
    }
  }

  // Privacy checks and Sparks message paywall for 1-on-1 direct chats
  if (!channel && !group) {
    const otherUser = database.getOtherParticipantInChat(chatId, senderId);
    if (otherUser && !otherUser.is_bot && otherUser.id !== senderId) {
      if (otherUser.privacy_messages === 'nobody') {
        throw new Error('Пользователь ограничил круг лиц, которые могут отправлять ему сообщения');
      }
      if (otherUser.privacy_messages === 'contacts') {
        const contacts = database.getUserContactPartnerIds(otherUser.id);
        if (!contacts.includes(senderId)) {
          throw new Error('Только контакты могут отправлять сообщения этому пользователю');
        }
      }
      if (otherUser.privacy_messages === 'sparks') {
        const price = Math.max(1, Number(otherUser.privacy_messages_sparks_price) || 1);
        const senderUser = database.getUserById(senderId);
        if ((senderUser?.sparks || 0) < price) {
          throw new Error(`Недостаточно Sparks. Для отправки сообщения требуется ${price} Sparks.`);
        }
        const { senderSparks, recipientSparks } = database.transferSparks(senderId, otherUser.id, price);
        sendToUser(senderId, { type: 'sparks_balance_updated', sparks: senderSparks });
        sendToUser(otherUser.id, { type: 'sparks_balance_updated', sparks: recipientSparks });
      }
    }
  }

  // 1. Save user message to SQLite
  const savedMessage = database.saveMessage(chatId, senderId, text, null, replyToMessageId || null);

  // 2. Broadcast in real time to all chat participants
  const participants = database.getChatParticipantUserIds(chatId);
  const payload = {
    type: 'new_message',
    message: savedMessage,
    chatId
  };

  for (const pId of participants) {
    sendToUser(pId, payload);
    const unreadCount = database.getUnreadCountForChat(chatId, pId);
    sendToUser(pId, {
      type: 'chat_updated',
      chatId,
      lastMessage: savedMessage,
      unreadCount
    });

    if (pId !== senderId) {
      notifyUserNewMessage(pId, savedMessage, chatId, senderId);
    }
  }

  // 3. Check if the chat is with a Bot (only for direct chats)
  if (!channel && !group) {
    const otherUser = database.getOtherParticipantInChat(chatId, senderId);
    if (otherUser && otherUser.is_bot) {
      if (otherUser.username === 'botfather') {
        setTimeout(() => {
          processBotFatherMessage({ chatId, userId: senderId, text, botFather: otherUser });
        }, 200);
      } else {
        // User-created bot: queue update and notify polling listeners
        database.addBotUpdate(otherUser.id, chatId, savedMessage.id);
        botEvents.emit('update', otherUser.id);
      }
    }
  }

  return savedMessage;
}

// ================= REST API ROUTES =================

// ==========================================================================
// RESEND EMAIL & PHONE AUTHENTICATION ENGINE
// ==========================================================================

// Periodic cleanup of expired auth codes and cloud tokens
setInterval(() => {
  try {
    database.cleanupExpiredAuthCodes();
  } catch (_) {}
  const now = Date.now();
  for (const [token, item] of pendingCloudAuths.entries()) {
    if (now > item.expiresAt) {
      pendingCloudAuths.delete(token);
    }
  }
}, 60 * 1000);

// Temporary tokens for 2-step cloud password verification
const pendingCloudAuths = new Map();

// Helper to format authenticated user response
function formatAuthUserResponse(user) {
  const isEmailPhone = user.phone && user.phone.includes('@');
  return {
    id: user.id,
    email: user.email || (isEmailPhone ? user.phone : ''),
    phone: (!isEmailPhone && user.phone) ? user.phone : '',
    first_name: user.first_name || '',
    last_name: user.last_name || '',
    username: user.username || null,
    avatar: user.avatar || '',
    description: user.description || '',
    profile_completed: Boolean(user.profile_completed),
    sparks: Number(user.sparks ?? 250),
    artifacts: Number(user.artifacts || 0),
    verification: user.verification || 'none',
    is_frozen: Boolean(user.is_frozen),
    frozen_reason: user.frozen_reason || '',
    frozen_until: user.frozen_until || '',
    is_premium: Boolean(user.is_premium),
    premium_since: user.premium_since || '',
    premium_until: user.premium_until || '',
    has_cloud_password: Boolean(user.has_cloud_password),
    banner_url: user.banner_url || '',
    pinned_channel_id: user.pinned_channel_id !== undefined ? user.pinned_channel_id : null,
    pinnedChannelId: user.pinned_channel_id !== undefined ? user.pinned_channel_id : null,
    channel_id: user.pinned_channel_id !== undefined ? user.pinned_channel_id : null
  };
}

// Helper: Parse client session metadata (Device, OS, Browser, IP, Location)
function getClientSessionInfo(req) {
  const ua = req?.headers?.['user-agent'] || '';
  const forwarded = req?.headers?.['x-forwarded-for'];
  const ip = (forwarded ? forwarded.split(',')[0].trim() : req?.socket?.remoteAddress || '127.0.0.1').replace(/^::ffff:/, '');

  let platform = 'Web';
  let deviceName = 'Portal Web Desktop';
  let browser = 'Браузер';

  if (/windows/i.test(ua)) {
    platform = 'Windows 11';
    deviceName = 'Portal Web Desktop';
  } else if (/iphone/i.test(ua)) {
    platform = 'iOS 18.2';
    deviceName = 'iPhone 15 Pro';
  } else if (/ipad/i.test(ua)) {
    platform = 'iPadOS 18.2';
    deviceName = 'iPad Air';
  } else if (/macintosh|mac os x/i.test(ua)) {
    platform = 'macOS Sequoia';
    deviceName = 'MacBook Pro';
  } else if (/android/i.test(ua)) {
    platform = 'Android 15';
    deviceName = 'Samsung Galaxy / Android';
  } else if (/linux/i.test(ua)) {
    platform = 'Linux';
    deviceName = 'Portal Linux Client';
  }

  if (/edg/i.test(ua)) {
    browser = 'Microsoft Edge';
  } else if (/chrome/i.test(ua)) {
    browser = 'Google Chrome';
  } else if (/safari/i.test(ua) && !/chrome/i.test(ua)) {
    browser = 'Apple Safari';
  } else if (/firefox/i.test(ua)) {
    browser = 'Mozilla Firefox';
  }

  let location = 'Москва, Россия';
  if (ip === '127.0.0.1' || ip === '::1' || ip.startsWith('192.168.') || ip.startsWith('172.') || ip.startsWith('10.')) {
    location = 'Москва, Россия';
  }

  return { deviceName, platform, browser, ipAddress: ip || '178.62.204.15', location };
}

// 1. Send Verification Code (Email via Resend / Legacy Phone SMS)
app.post('/api/auth/send-code', async (req, res) => {
  const { email, phone } = req.body;

  // A. EMAIL AUTHENTICATION (Primary)
  if (email && typeof email === 'string') {
    const cleanEmail = email.trim().toLowerCase();
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(cleanEmail)) {
      return res.status(400).json({ error: 'Введите корректный адрес электронной почты' });
    }

    // Rate-limit: 45 seconds between code requests for same email
    const existing = database.getAuthCode(cleanEmail);
    const now = Date.now();
    if (existing && (now - existing.sent_at) < 45 * 1000) {
      const waitSec = Math.ceil((45 * 1000 - (now - existing.sent_at)) / 1000);
      return res.status(429).json({ 
        error: `Подождите ${waitSec} сек. перед повторной отправкой кода`,
        retryAfter: waitSec
      });
    }

    // Generate cryptographic 6-digit numeric code
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    
    // Store persistently in SQLite with 10 minutes expiration
    database.saveAuthCode(cleanEmail, code, now + 10 * 60 * 1000, now);
    console.log(`[AUTH SEND] Code generated for ${cleanEmail}: ${code}`);

    try {
      const sendResult = await sendVerificationEmail(cleanEmail, code);
      return res.json({
        success: true,
        type: 'email',
        email: cleanEmail,
        message: sendResult.message,
        simulated: Boolean(sendResult.simulated),
        testCode: sendResult.simulated ? code : undefined
      });
    } catch (sendErr) {
      console.error('[Auth Send Code Error]', sendErr);
      return res.status(500).json({
        error: sendErr.message || 'Не удалось отправить код подтверждения на почту'
      });
    }
  }

  // B. PHONE AUTHENTICATION (Legacy / Fallback)
  if (phone && typeof phone === 'string' && phone.trim().length >= 5) {
    const cleanPhone = phone.trim().replace(/[^\d+]/g, '');
    return res.json({
      success: true,
      type: 'phone',
      message: 'Код подтверждения отправлен (для теста: 000000)',
      testCode: '000000',
      phone: cleanPhone
    });
  }

  return res.status(400).json({ error: 'Укажите адрес электронной почты или номер телефона' });
});

// 2. Verify Verification Code
app.post('/api/auth/verify-code', (req, res) => {
  const { email, phone, code } = req.body;

  if (!code || typeof code !== 'string') {
    return res.status(400).json({ error: 'Введите 6-значный проверочный код' });
  }
  const cleanCode = String(code).trim().replace(/\D/g, '');

  // A. EMAIL VERIFICATION
  if (email && typeof email === 'string') {
    const cleanEmail = email.trim().toLowerCase();
    const pending = database.getAuthCode(cleanEmail);

    console.log(`[AUTH VERIFY] Email: ${cleanEmail}, Input: "${cleanCode}", Stored: "${pending?.code}"`);

    if (!pending || Date.now() > pending.expires_at) {
      if (pending) database.deleteAuthCode(cleanEmail);
      return res.status(400).json({ error: 'Срок действия кода истек или код не запрашивался. Запросите новый код.' });
    }

    if (pending.attempts >= 5) {
      database.deleteAuthCode(cleanEmail);
      return res.status(429).json({ error: 'Слишком много неверных попыток. Запросите новый код.' });
    }

    const isMatch = String(cleanCode).trim() === String(pending.code).trim() || (!isResendConfigured() && cleanCode === '000000');
    if (!isMatch) {
      database.incrementAuthCodeAttempts(cleanEmail);
      const left = 5 - (pending.attempts + 1);
      return res.status(400).json({ 
        error: `Неверный проверочный код. Осталось попыток: ${left}` 
      });
    }

    let user = database.getUserByEmail(cleanEmail);

    // If 2FA Cloud Password enabled, require second step
    if (user && user.has_cloud_password) {
      database.deleteAuthCode(cleanEmail);
      const tempToken = crypto.randomBytes(32).toString('hex');
      pendingCloudAuths.set(tempToken, {
        userId: user.id,
        email: cleanEmail,
        expiresAt: Date.now() + 10 * 60 * 1000
      });

      return res.json({
        success: true,
        requiresCloudPassword: true,
        tempToken,
        email: cleanEmail,
        hint: user.cloud_password_hint || ''
      });
    }

    const token = crypto.randomBytes(32).toString('hex');
    const sessionInfo = getClientSessionInfo(req);

    if (!user) {
      user = database.createUserWithEmail(cleanEmail, token);
      console.log(`[PORTAL AUTH] New user registered via email: ${cleanEmail} (ID: ${user.id})`);
    } else {
      database.updateToken(user.id, token);
      user = database.getUserById(user.id);
      console.log(`[PORTAL AUTH] User logged in via email: ${cleanEmail} (ID: ${user.id})`);
    }

    database.createSession(user.id, token, sessionInfo);
    database.deleteAuthCode(cleanEmail);

    return res.json({
      success: true,
      requiresCloudPassword: false,
      token,
      user: formatAuthUserResponse(user)
    });
  }

  // B. PHONE VERIFICATION (Legacy)
  if (phone && typeof phone === 'string') {
    if (cleanCode !== '000000') {
      return res.status(400).json({ error: 'Неверный проверочный код. Тестовый код: 000000' });
    }

    const cleanPhone = phone.trim().replace(/[^\d+]/g, '');
    let user = database.getUserByPhone(cleanPhone);

    if (user && user.has_cloud_password) {
      const tempToken = crypto.randomBytes(32).toString('hex');
      pendingCloudAuths.set(tempToken, {
        userId: user.id,
        phone: cleanPhone,
        expiresAt: Date.now() + 10 * 60 * 1000
      });

      return res.json({
        success: true,
        requiresCloudPassword: true,
        tempToken,
        phone: cleanPhone,
        hint: user.cloud_password_hint || ''
      });
    }

    const token = crypto.randomBytes(32).toString('hex');
    const sessionInfo = getClientSessionInfo(req);

    if (!user) {
      user = database.createUser(cleanPhone, token);
    } else {
      database.updateToken(user.id, token);
      user = database.getUserById(user.id);
    }
    database.createSession(user.id, token, sessionInfo);

    return res.json({
      success: true,
      requiresCloudPassword: false,
      token,
      user: formatAuthUserResponse(user)
    });
  }

  return res.status(400).json({ error: 'Укажите адрес электронной почты или номер телефона' });
});

// 2.1 Verify Cloud Password (2FA Step)
app.post('/api/auth/verify-cloud-password', (req, res) => {
  const { tempToken, password } = req.body;
  if (!tempToken || !password) {
    return res.status(400).json({ error: 'Укажите облачный пароль' });
  }

  const pending = pendingCloudAuths.get(tempToken);
  if (!pending || pending.expiresAt < Date.now()) {
    if (pending) pendingCloudAuths.delete(tempToken);
    return res.status(400).json({ error: 'Сессия подтверждения истекла. Пожалуйста, запросите код заново' });
  }

  const isCorrect = database.verifyCloudPassword(pending.userId, password);
  if (!isCorrect) {
    return res.status(400).json({ error: 'Неверный облачный пароль' });
  }

  pendingCloudAuths.delete(tempToken);
  const token = crypto.randomBytes(32).toString('hex');
  database.updateToken(pending.userId, token);
  const sessionInfo = getClientSessionInfo(req);
  database.createSession(pending.userId, token, sessionInfo);
  const user = database.getUserById(pending.userId);

  return res.json({
    success: true,
    token,
    user: formatAuthUserResponse(user)
  });
});

// 3. Check Username Availability
app.get('/api/users/check-username', (req, res) => {
  const username = req.query.username;
  const excludeUserId = req.query.excludeId ? Number(req.query.excludeId) : null;
  let excludeChannelId = req.query.excludeChannelId ? Number(req.query.excludeChannelId) : null;
  if (!excludeChannelId && req.query.excludeChatId) {
    const chan = database.getChannelByChatId(Number(req.query.excludeChatId));
    if (chan) excludeChannelId = chan.id;
  }

  if (!username || typeof username !== 'string') {
    return res.json({ available: false, error: 'Имя пользователя не указано' });
  }

  const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
  if (cleanUsername.length < 5) {
    return res.json({ available: false, error: 'Минимум 5 символов' });
  }
  if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
    return res.json({ available: false, error: 'Только латинские буквы, цифры и _' });
  }

  const available = database.isUsernameAvailable(cleanUsername, excludeUserId, excludeChannelId);
  return res.json({ available, username: cleanUsername });
});

app.get('/api/channels/check-username', (req, res) => {
  const username = req.query.username;
  const excludeChannelId = req.query.excludeChannelId ? Number(req.query.excludeChannelId) : null;
  const excludeChatId = req.query.excludeChatId ? Number(req.query.excludeChatId) : null;
  let channelIdToExclude = excludeChannelId;
  if (!channelIdToExclude && excludeChatId) {
    const chan = database.getChannelByChatId(excludeChatId);
    if (chan) channelIdToExclude = chan.id;
  }

  if (!username || typeof username !== 'string') {
    return res.json({ available: false, error: 'Имя пользователя не указано' });
  }

  const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
  if (cleanUsername.length < 5) {
    return res.json({ available: false, error: 'Минимум 5 символов' });
  }
  if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
    return res.json({ available: false, error: 'Только латинские буквы, цифры и _' });
  }

  const available = database.isUsernameAvailable(cleanUsername, null, channelIdToExclude);
  return res.json({ available, username: cleanUsername });
});

// 4. Update Profile
app.post('/api/users/profile', authMiddleware, (req, res) => {
  if (req.user.is_frozen) {
    return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
  }

  const { firstName, lastName, username, avatar } = req.body;

  if (!firstName || !firstName.trim()) {
    return res.status(400).json({ error: 'Имя обязательно для заполнения' });
  }

  if (username && username.trim()) {
    const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
    const isCurrentUsername = cleanUsername === (req.user.username || '').toLowerCase();
    if (!isCurrentUsername && cleanUsername.length < 5) {
      return res.status(400).json({ error: 'Имя пользователя должно содержать минимум 5 символов' });
    }
    if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
      return res.status(400).json({ error: 'Имя пользователя может содержать только латинские буквы, цифры и _' });
    }
    const available = database.isUsernameAvailable(cleanUsername, req.user.id);
    if (!available) {
      return res.status(400).json({ error: 'Это имя пользователя уже занято' });
    }
  }

  const rawPinned = req.body.pinned_channel_id !== undefined
    ? req.body.pinned_channel_id
    : (req.body.pinnedChannelId !== undefined
        ? req.body.pinnedChannelId
        : (req.body.channel_id !== undefined ? req.body.channel_id : undefined));

  let pinnedChannelId = undefined;
  if (rawPinned !== undefined) {
    if (rawPinned === null || rawPinned === '' || rawPinned === 0 || rawPinned === 'null') {
      pinnedChannelId = null;
    } else {
      const parsed = parseInt(rawPinned, 10);
      pinnedChannelId = (!isNaN(parsed) && parsed > 0) ? parsed : null;
    }
  }

  const updatedUser = database.updateUserProfile(req.user.id, {
    firstName,
    lastName: lastName || '',
    username: username || '',
    avatar: avatar || '',
    description: req.body.description !== undefined ? req.body.description : undefined,
    pinnedChannelId
  });

  return res.json({
    success: true,
    user: {
      id: updatedUser.id,
      email: updatedUser.email || (updatedUser.phone && updatedUser.phone.includes('@') ? updatedUser.phone : ''),
      phone: (updatedUser.phone && !updatedUser.phone.includes('@')) ? updatedUser.phone : '',
      first_name: updatedUser.first_name,
      last_name: updatedUser.last_name,
      username: updatedUser.username,
      secondary_usernames: updatedUser.secondary_usernames || [],
      avatar: updatedUser.avatar,
      description: updatedUser.description || '',
      profile_completed: Boolean(updatedUser.profile_completed),
      sparks: Number(updatedUser.sparks ?? 250),
      verification: updatedUser.verification || 'none',
      is_frozen: Boolean(updatedUser.is_frozen),
      frozen_reason: updatedUser.frozen_reason || '',
      frozen_until: updatedUser.frozen_until || '',
      is_premium: Boolean(updatedUser.is_premium),
      premium_since: updatedUser.premium_since || '',
      premium_until: updatedUser.premium_until || '',
      has_cloud_password: Boolean(updatedUser.has_cloud_password),
      banner_url: updatedUser.banner_url || '',
      pinned_channel_id: updatedUser.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null,
      pinnedChannelId: updatedUser.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null,
      channel_id: updatedUser.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null,
      privacy_messages: updatedUser.privacy_messages || 'all',
      privacy_messages_sparks_price: Number(updatedUser.privacy_messages_sparks_price || 1),
      privacy_phone: updatedUser.privacy_phone || 'all',
      privacy_last_seen: updatedUser.privacy_last_seen || 'all'
    }
  });
});

// 5. Get Current User Profile
app.get('/api/users/me', authMiddleware, (req, res) => {
  const freshUser = database.getUserById(req.user.id);
  const isEmailPhone = freshUser?.phone && freshUser.phone.includes('@');
  return res.json({
    user: {
      id: freshUser.id,
      email: freshUser.email || (isEmailPhone ? freshUser.phone : ''),
      phone: (!isEmailPhone && freshUser.phone) ? freshUser.phone : '',
      first_name: freshUser.first_name,
      last_name: freshUser.last_name,
      username: freshUser.username,
      secondary_usernames: freshUser.secondary_usernames || [],
      avatar: freshUser.avatar,
      description: freshUser.description || '',
      profile_completed: Boolean(freshUser.profile_completed),
      sparks: Number(freshUser.sparks ?? 250),
      artifacts: Number(freshUser.artifacts || 0),
      verification: freshUser.verification || 'none',
      is_frozen: Boolean(freshUser.is_frozen),
      frozen_reason: freshUser.frozen_reason || '',
      frozen_until: freshUser.frozen_until || '',
      is_premium: Boolean(freshUser.is_premium),
      premium_since: freshUser.premium_since || '',
      premium_until: freshUser.premium_until || '',
      has_cloud_password: Boolean(freshUser.has_cloud_password),
      banner_url: freshUser.banner_url || '',
      pinned_channel_id: freshUser.pinned_channel_id !== undefined ? freshUser.pinned_channel_id : null,
      pinnedChannelId: freshUser.pinned_channel_id !== undefined ? freshUser.pinned_channel_id : null,
      channel_id: freshUser.pinned_channel_id !== undefined ? freshUser.pinned_channel_id : null,
      privacy_messages: freshUser.privacy_messages || 'all',
      privacy_messages_sparks_price: Number(freshUser.privacy_messages_sparks_price || 1),
      privacy_phone: freshUser.privacy_phone || 'all',
      privacy_last_seen: freshUser.privacy_last_seen || 'all',
      name_font: freshUser.name_font || 'default',
      status_font: freshUser.status_font || 'default',
      custom_activity_status: freshUser.custom_activity_status || '',
      is_admin: Boolean(freshUser.is_admin || freshUser.verification === 'dev' || freshUser.id === 1)
    }
  });
});

// Privacy settings update
const handlePrivacyUpdate = (req, res) => {
  const { privacy_messages, privacy_messages_sparks_price, privacy_phone, privacy_last_seen } = req.body;
  try {
    const updatedUser = database.updateUserPrivacy(req.user.id, {
      privacy_messages,
      privacy_messages_sparks_price,
      privacy_phone,
      privacy_last_seen
    });
    return res.json({
      success: true,
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        secondary_usernames: updatedUser.secondary_usernames || [],
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        profile_completed: Boolean(updatedUser.profile_completed),
        sparks: Number(updatedUser.sparks ?? 250),
        verification: updatedUser.verification || 'none',
        is_frozen: Boolean(updatedUser.is_frozen),
        frozen_reason: updatedUser.frozen_reason || '',
        frozen_until: updatedUser.frozen_until || '',
        is_premium: Boolean(updatedUser.is_premium),
        premium_since: updatedUser.premium_since || '',
        premium_until: updatedUser.premium_until || '',
        has_cloud_password: Boolean(updatedUser.has_cloud_password),
        banner_url: updatedUser.banner_url || '',
        pinned_channel_id: updatedUser.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null,
        pinnedChannelId: updatedUser.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null,
        channel_id: updatedUser.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null,
        privacy_messages: updatedUser.privacy_messages || 'all',
        privacy_messages_sparks_price: Number(updatedUser.privacy_messages_sparks_price || 1),
        privacy_phone: updatedUser.privacy_phone || 'all',
        privacy_last_seen: updatedUser.privacy_last_seen || 'all'
      }
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка обновления настроек приватности' });
  }
};

app.post('/api/user/privacy', authMiddleware, handlePrivacyUpdate);
app.post('/api/users/privacy', authMiddleware, handlePrivacyUpdate);

// Profile Banner endpoints (Portal Premium exclusive)
app.post('/api/user/banner', authMiddleware, (req, res) => {
  const freshUser = database.getUserById(req.user.id);
  if (!freshUser) return res.status(404).json({ error: 'Пользователь не найден' });
  if (!freshUser.is_premium) {
    return res.status(403).json({ error: 'Установка баннера профиля доступна только с подпиской Portal Premium' });
  }

  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadPhotoMulter.single('banner')(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || 'Ошибка загрузки баннера' });
      if (!req.file) return res.status(400).json({ error: 'Файл баннера не передан' });
      const bannerUrl = `/uploads/${req.file.filename}`;
      const updated = database.updateUserBanner(req.user.id, bannerUrl);
      return res.json({ success: true, user: updated, banner_url: bannerUrl });
    });
  } else {
    const { banner_url } = req.body;
    try {
      const updated = database.updateUserBanner(req.user.id, banner_url || '');
      return res.json({ success: true, user: updated, banner_url: updated.banner_url });
    } catch (err) {
      return res.status(400).json({ error: err.message });
    }
  }
});

app.delete('/api/user/banner', authMiddleware, (req, res) => {
  const freshUser = database.getUserById(req.user.id);
  if (!freshUser) return res.status(404).json({ error: 'Пользователь не найден' });
  try {
    const updated = database.updateUserBanner(req.user.id, '');
    return res.json({ success: true, user: updated, banner_url: '' });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// Customization endpoints (Portal Premium exclusive)
app.post(['/api/user/customization', '/api/users/customization'], authMiddleware, (req, res) => {
  const freshUser = database.getUserById(req.user.id);
  if (!freshUser) return res.status(404).json({ error: 'Пользователь не найден' });
  const { name_font, status_font, custom_activity_status } = req.body;

  const isChangingFont = (name_font && name_font !== 'default' && name_font !== freshUser.name_font) ||
                         (status_font && status_font !== 'default' && status_font !== freshUser.status_font);

  if (isChangingFont && !freshUser.is_premium) {
    return res.status(403).json({ error: 'Кастомизация шрифтов доступна только обладателям подписки Portal Premium' });
  }

  const allowedFonts = ['default', 'minecraft'];
  const validNameFont = (name_font && allowedFonts.includes(name_font)) ? name_font : (freshUser.name_font || 'default');
  const validStatusFont = (status_font && allowedFonts.includes(status_font)) ? status_font : (freshUser.status_font || 'default');
  const validCustomStatus = custom_activity_status !== undefined
    ? String(custom_activity_status).trim().slice(0, 60)
    : (freshUser.custom_activity_status || '');

  try {
    const updatedUser = database.updateUserCustomization(req.user.id, {
      name_font: validNameFont,
      status_font: validStatusFont,
      custom_activity_status: validCustomStatus
    });

    sendToUser(req.user.id, {
      type: 'user_updated',
      user: updatedUser
    });

    return res.json({
      success: true,
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        secondary_usernames: updatedUser.secondary_usernames || [],
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        profile_completed: Boolean(updatedUser.profile_completed),
        sparks: Number(updatedUser.sparks ?? 250),
        verification: updatedUser.verification || 'none',
        is_frozen: Boolean(updatedUser.is_frozen),
        is_premium: Boolean(updatedUser.is_premium),
        name_font: updatedUser.name_font || 'default',
        status_font: updatedUser.status_font || 'default',
        custom_activity_status: updatedUser.custom_activity_status || ''
      }
    });
  } catch (err) {
    console.error('[Customization Error]', err);
    return res.status(500).json({ error: 'Ошибка при сохранении кастомизации' });
  }
});

// 5.1 Cloud Password Security Endpoints
app.post('/api/security/cloud-password/set', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }
    const { password, hint } = req.body;
    if (!password || typeof password !== 'string' || password.length < 4) {
      return res.status(400).json({ error: 'Пароль должен содержать не менее 4 символов' });
    }
    const updatedUser = database.setCloudPassword(req.user.id, password, hint);
    return res.json({
      success: true,
      message: 'Облачный пароль успешно установлен',
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        secondary_usernames: updatedUser.secondary_usernames || [],
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        profile_completed: Boolean(updatedUser.profile_completed),
        sparks: Number(updatedUser.sparks ?? 250),
        verification: updatedUser.verification || 'none',
        is_frozen: Boolean(updatedUser.is_frozen),
        frozen_reason: updatedUser.frozen_reason || '',
        frozen_until: updatedUser.frozen_until || '',
        is_premium: Boolean(updatedUser.is_premium),
        premium_since: updatedUser.premium_since || '',
        premium_until: updatedUser.premium_until || '',
        has_cloud_password: Boolean(updatedUser.has_cloud_password)
      }
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка установки облачного пароля' });
  }
});

app.post('/api/security/cloud-password/change', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }
    const { currentPassword, newPassword, hint } = req.body;
    if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 4) {
      return res.status(400).json({ error: 'Новый пароль должен содержать не менее 4 символов' });
    }
    const updatedUser = database.changeCloudPassword(req.user.id, currentPassword, newPassword, hint);
    return res.json({
      success: true,
      message: 'Облачный пароль успешно изменен',
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        secondary_usernames: updatedUser.secondary_usernames || [],
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        profile_completed: Boolean(updatedUser.profile_completed),
        sparks: Number(updatedUser.sparks ?? 250),
        verification: updatedUser.verification || 'none',
        is_frozen: Boolean(updatedUser.is_frozen),
        frozen_reason: updatedUser.frozen_reason || '',
        frozen_until: updatedUser.frozen_until || '',
        is_premium: Boolean(updatedUser.is_premium),
        premium_since: updatedUser.premium_since || '',
        premium_until: updatedUser.premium_until || '',
        has_cloud_password: Boolean(updatedUser.has_cloud_password)
      }
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка изменения облачного пароля' });
  }
});

app.post('/api/security/cloud-password/remove', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }
    const { currentPassword } = req.body;
    const updatedUser = database.removeCloudPassword(req.user.id, currentPassword);
    return res.json({
      success: true,
      message: 'Облачный пароль успешно отключен',
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        secondary_usernames: updatedUser.secondary_usernames || [],
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        profile_completed: Boolean(updatedUser.profile_completed),
        sparks: Number(updatedUser.sparks ?? 250),
        verification: updatedUser.verification || 'none',
        is_frozen: Boolean(updatedUser.is_frozen),
        frozen_reason: updatedUser.frozen_reason || '',
        frozen_until: updatedUser.frozen_until || '',
        is_premium: Boolean(updatedUser.is_premium),
        premium_since: updatedUser.premium_since || '',
        premium_until: updatedUser.premium_until || '',
        has_cloud_password: Boolean(updatedUser.has_cloud_password)
      }
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка отключения облачного пароля' });
  }
});

// ================= PASSCODE LOCK ROUTES =================
app.post('/api/security/passcode/set', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }
    const { passcode } = req.body;
    if (!passcode || typeof passcode !== 'string' || passcode.trim().length < 4) {
      return res.status(400).json({ error: 'Код-пароль должен содержать минимум 4 символа' });
    }
    const updatedUser = database.setPasscode(req.user.id, passcode);
    return res.json({
      success: true,
      message: 'Код-пароль успешно установлен',
      user: updatedUser
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка установки код-пароля' });
  }
});

app.post('/api/security/passcode/change', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }
    const { currentPasscode, newPasscode } = req.body;
    if (!newPasscode || typeof newPasscode !== 'string' || newPasscode.trim().length < 4) {
      return res.status(400).json({ error: 'Новый код-пароль должен содержать минимум 4 символа' });
    }
    const updatedUser = database.changePasscode(req.user.id, currentPasscode, newPasscode);
    return res.json({
      success: true,
      message: 'Код-пароль успешно изменен',
      user: updatedUser
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка изменения код-пароля' });
  }
});

app.post('/api/security/passcode/remove', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }
    const { currentPasscode } = req.body;
    const updatedUser = database.removePasscode(req.user.id, currentPasscode);
    return res.json({
      success: true,
      message: 'Код-пароль успешно отключен',
      user: updatedUser
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка отключения код-пароля' });
  }
});

app.post('/api/security/passcode/verify', authMiddleware, (req, res) => {
  try {
    const { passcode } = req.body;
    if (!passcode) {
      return res.status(400).json({ valid: false, error: 'Код-пароль не передан' });
    }
    const isValid = database.verifyPasscode(req.user.id, passcode);
    if (!isValid) {
      return res.status(400).json({ valid: false, error: 'Неверный код-пароль' });
    }
    return res.json({ success: true, valid: true });
  } catch (err) {
    return res.status(500).json({ valid: false, error: 'Ошибка проверки код-пароля' });
  }
});

// 5.2 Active Sessions Management
app.get('/api/security/sessions', authMiddleware, (req, res) => {
  try {
    const currentToken = req.token || req.headers.authorization?.split(' ')[1] || '';
    const sessions = database.getUserSessions(req.user.id, currentToken);
    const currentSession = sessions.find(s => s.is_current) || sessions[0] || null;
    const otherSessions = sessions.filter(s => s !== currentSession);

    return res.json({
      success: true,
      currentSession,
      otherSessions,
      totalCount: sessions.length
    });
  } catch (err) {
    console.error('Error fetching sessions:', err);
    return res.status(500).json({ error: 'Ошибка получения списка сеансов' });
  }
});

app.delete('/api/security/sessions/:id', authMiddleware, (req, res) => {
  try {
    const sessionId = Number(req.params.id);
    const currentToken = req.token || req.headers.authorization?.split(' ')[1] || '';
    const terminated = database.terminateSession(req.user.id, sessionId, currentToken);
    if (!terminated) {
      return res.status(404).json({ error: 'Сеанс не найден или уже завершен' });
    }

    return res.json({
      success: true,
      message: 'Сеанс успешно завершен',
      terminatedSessionId: sessionId
    });
  } catch (err) {
    console.error('Error terminating session:', err);
    return res.status(500).json({ error: 'Ошибка завершения сеанса' });
  }
});

app.post('/api/security/sessions/terminate-all-others', authMiddleware, (req, res) => {
  try {
    const currentToken = req.token || req.headers.authorization?.split(' ')[1] || '';
    const terminatedCount = database.terminateAllOtherSessions(req.user.id, currentToken);

    return res.json({
      success: true,
      message: `Завершено сеансов: ${terminatedCount}`,
      terminatedCount
    });
  } catch (err) {
    console.error('Error terminating other sessions:', err);
    return res.status(500).json({ error: 'Ошибка завершения других сеансов' });
  }
});

// 5.0 Portal Premium Subscription
app.post('/api/premium/subscribe', authMiddleware, (req, res) => {
  try {
    if (req.user.is_frozen) {
      return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
    }

    const cost = 1500;
    const updatedUser = database.subscribePremium(req.user.id, cost);

    // Broadcast updated sparks and user profile
    sendToUser(req.user.id, {
      type: 'sparks_updated',
      sparks: Number(updatedUser.sparks)
    });
    sendToUser(req.user.id, {
      type: 'user_profile_updated',
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        sparks: Number(updatedUser.sparks),
        verification: updatedUser.verification || 'none',
        is_premium: Boolean(updatedUser.is_premium),
        premium_since: updatedUser.premium_since || '',
        premium_until: updatedUser.premium_until || ''
      }
    });

    return res.json({
      success: true,
      message: 'Portal Premium успешно активирован!',
      user: {
        id: updatedUser.id,
        phone: updatedUser.phone,
        first_name: updatedUser.first_name,
        last_name: updatedUser.last_name,
        username: updatedUser.username,
        secondary_usernames: updatedUser.secondary_usernames || [],
        avatar: updatedUser.avatar,
        description: updatedUser.description || '',
        profile_completed: Boolean(updatedUser.profile_completed),
        sparks: Number(updatedUser.sparks ?? 250),
        verification: updatedUser.verification || 'none',
        is_frozen: Boolean(updatedUser.is_frozen),
        frozen_reason: updatedUser.frozen_reason || '',
        frozen_until: updatedUser.frozen_until || '',
        is_premium: Boolean(updatedUser.is_premium),
        premium_since: updatedUser.premium_since || '',
        premium_until: updatedUser.premium_until || ''
      }
    });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка активации Portal Premium' });
  }
});

// ================= PORTAL SECURE ADMIN API =================

// 1. GET /api/admin/stats
app.get('/api/admin/stats', adminMiddleware, (req, res) => {
  try {
    const stats = database.getAdminStats();
    return res.json({ success: true, stats });
  } catch (err) {
    return res.status(500).json({ error: 'Ошибка получения статистики' });
  }
});

// 2. GET /api/admin/users
app.get('/api/admin/users', adminMiddleware, (req, res) => {
  try {
    const { q, filter, limit, offset } = req.query;
    const result = database.getAdminUsersList({
      query: q || '',
      filter: filter || 'all',
      limit: Number(limit) || 50,
      offset: Number(offset) || 0
    });
    // Add real-time online status
    const usersWithOnline = result.users.map(u => ({
      ...u,
      is_online: !u.is_bot && isUserOnline(u.id)
    }));
    return res.json({ success: true, users: usersWithOnline, total: result.total });
  } catch (err) {
    return res.status(500).json({ error: 'Ошибка загрузки пользователей' });
  }
});

// 3. POST /api/admin/users/:userId/freeze
app.post(['/api/admin/users/:userId/freeze', '/api/admin/freeze'], adminMiddleware, (req, res) => {
  try {
    const targetUserId = req.params.userId ? Number(req.params.userId) : (req.body.targetUserId ? Number(req.body.targetUserId) : null);
    if (!targetUserId) {
      return res.status(400).json({ error: 'Не указан ID пользователя' });
    }
    if (targetUserId === 1) {
      return res.status(400).json({ error: 'Нельзя заморозить главного создателя' });
    }
    if (targetUserId === req.user.id) {
      return res.status(400).json({ error: 'Нельзя заморозить собственный аккаунт' });
    }

    const { isFrozen, reason, until } = req.body;
    const frozenState = isFrozen === undefined ? 1 : (isFrozen ? 1 : 0);
    const updatedUser = database.setUserFrozen(targetUserId, frozenState, reason || '', until || '');

    // Instantly notify target user via WebSocket
    sendToUser(targetUserId, {
      type: 'account_freeze_changed',
      is_frozen: Boolean(frozenState),
      reason: reason || '',
      until: until || ''
    });

    broadcast({
      type: 'user_profile_updated',
      userId: targetUserId,
      is_frozen: Boolean(frozenState)
    });

    return res.json({ success: true, user: updatedUser });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка изменения статуса заморозки' });
  }
});

// 4. POST /api/admin/users/:userId/sparks
app.post('/api/admin/users/:userId/sparks', adminMiddleware, (req, res) => {
  try {
    const targetUserId = Number(req.params.userId);
    if (!targetUserId) {
      return res.status(400).json({ error: 'Не указан ID пользователя' });
    }
    const { action, amount } = req.body; // 'add' | 'deduct' | 'set'
    const numAmount = Number(amount);
    if (isNaN(numAmount) || numAmount < 0) {
      return res.status(400).json({ error: 'Укажите корректную сумму Sparks' });
    }

    const updatedUser = database.adminSetUserSparks(targetUserId, action || 'add', numAmount);

    sendToUser(targetUserId, {
      type: 'sparks_updated',
      sparks: Number(updatedUser.sparks)
    });

    broadcast({
      type: 'user_profile_updated',
      userId: targetUserId,
      sparks: Number(updatedUser.sparks)
    });

    return res.json({ success: true, user: updatedUser, sparks: Number(updatedUser.sparks) });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка изменения баланса Sparks' });
  }
});

// 5. POST /api/admin/users/:userId/premium
app.post('/api/admin/users/:userId/premium', adminMiddleware, (req, res) => {
  try {
    const targetUserId = Number(req.params.userId);
    if (!targetUserId) {
      return res.status(400).json({ error: 'Не указан ID пользователя' });
    }
    const { isPremium, durationMonths, isLifetime } = req.body;
    const premiumState = isPremium === undefined ? true : Boolean(isPremium);

    const updatedUser = database.adminSetUserPremium(targetUserId, premiumState, durationMonths || 1, Boolean(isLifetime));

    sendToUser(targetUserId, {
      type: 'premium_updated',
      is_premium: Boolean(updatedUser.is_premium),
      premium_until: updatedUser.premium_until || ''
    });

    broadcast({
      type: 'user_profile_updated',
      userId: targetUserId,
      is_premium: Boolean(updatedUser.is_premium)
    });

    return res.json({ success: true, user: updatedUser });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка изменения статуса Portal Premium' });
  }
});

// 6. POST /api/admin/users/:userId/verification
app.post(['/api/admin/users/:userId/verification', '/api/admin/verification'], adminMiddleware, (req, res) => {
  try {
    const targetUserId = req.params.userId ? Number(req.params.userId) : (req.body.targetUserId ? Number(req.body.targetUserId) : null);
    if (!targetUserId) {
      return res.status(400).json({ error: 'Не указан ID пользователя' });
    }
    const { verification } = req.body;
    const valid = ['dev', 'verified', 'artist', 'none'].includes(verification) ? verification : 'none';
    const updatedUser = database.setUserVerification(targetUserId, valid);

    broadcast({
      type: 'user_profile_updated',
      userId: targetUserId,
      verification: valid
    });

    return res.json({ success: true, user: updatedUser });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка обновления статуса верификации' });
  }
});

// POST /api/admin/channels/:channelId/verification
app.post(['/api/admin/channels/:channelId/verification', '/api/admin/channel-verification'], adminMiddleware, (req, res) => {
  try {
    const channelId = req.params.channelId ? Number(req.params.channelId) : (req.body.channelId ? Number(req.body.channelId) : null);
    if (!channelId) {
      return res.status(400).json({ error: 'Не указан ID канала' });
    }
    const { verification } = req.body;
    const valid = ['dev', 'verified', 'artist', 'none'].includes(verification) ? verification : 'none';
    database.setChannelVerification(channelId, valid);
    broadcast({
      type: 'channel_updated',
      channelId,
      verification: valid
    });
    return res.json({ success: true, channelId, verification: valid });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка обновления статуса верификации канала' });
  }
});

// 7. POST /api/admin/secondary-usernames
app.post('/api/admin/secondary-usernames', adminMiddleware, (req, res) => {
  try {
    const { targetUserId, username, action } = req.body;
    const uid = targetUserId ? Number(targetUserId) : req.user.id;
    if (!username || !username.trim()) {
      return res.status(400).json({ error: 'Укажите username' });
    }
    if (action === 'remove') {
      const updatedUser = database.removeSecondaryUsername(uid, username);
      return res.json({ success: true, user: updatedUser });
    }
    const updatedUser = database.addSecondaryUsername(uid, username);
    return res.json({ success: true, user: updatedUser });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка управления доп. юзернеймами' });
  }
});

// 5.1 Top Up Sparks Currency
app.post('/api/sparks/topup', authMiddleware, (req, res) => {
  return res.status(503).json({
    error: 'Пополнение баланса Sparks временно недоступно. Ведутся технические работы на платёжном шлюзе.'
  });
});

// 5.2 Gifts Catalog and Sending
const GIFTS_CATALOG = [
  {
    id: 'gargona',
    name: 'Chrome Gorgon',
    file: '/gifts/gargona/Chrome-Gorgon.json',
    price: 50,
    description: 'Легендарный анимированный подарок Chrome Gorgon'
  },
  {
    id: 'girl',
    name: 'Anime Girl',
    file: '/gifts/girl/animegirl.json',
    price: 50,
    description: 'Очаровательный анимированный подарок Anime Girl'
  },
  {
    id: 'theel',
    name: 'Bumblebee',
    file: '/gifts/theel/Bumblebee.json',
    price: 50,
    description: 'Энергичный анимированный подарок Bumblebee'
  },
  {
    id: 'cars',
    name: 'BMW M4',
    collection: 'CARS',
    file: '/gifts/cars/bmw-model-m4.png',
    price: 50,
    description: 'Эксклюзивная коллекция CARS: спортивное купе BMW M4'
  }
];

// GET /api/gifts/catalog
app.get('/api/gifts/catalog', (req, res) => {
  return res.json({ gifts: GIFTS_CATALOG });
});

// GET /api/users/search - Search Users by @username or name
app.get('/api/users/search', authMiddleware, (req, res) => {
  const query = req.query.q || '';
  if (!query.trim()) {
    return res.json({ users: [] });
  }
  const rawUsers = database.searchUsers(query, req.user.id);
  const users = rawUsers.map(u => ({
    ...u,
    is_online: !u.is_bot && isUserOnline(u.id),
    last_seen: u.last_seen || null
  }));
  return res.json({ users });
});

// GET /api/users/:userId
app.get('/api/users/:userId', authMiddleware, (req, res, next) => {
  if (req.params.userId === 'search') return next();
  const userId = parseInt(req.params.userId, 10);
  if (!userId) return res.status(400).json({ error: 'Неверный ID пользователя' });
  const user = database.getUserById(userId);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });

  let phone = user.phone;
  let isOnline = !user.is_bot && isUserOnline(user.id);
  let lastSeen = user.last_seen || null;
  let isActivityHidden = false;

  if (req.user.id !== user.id && !user.is_bot) {
    if (user.privacy_phone === 'nobody') {
      phone = null;
    } else if (user.privacy_phone === 'contacts') {
      const contacts = database.getUserContactPartnerIds(user.id);
      if (!contacts.includes(req.user.id)) {
        phone = null;
      }
    }

    // Enforce privacy_last_seen
    if (user.privacy_last_seen === 'nobody') {
      isOnline = false;
      lastSeen = null;
      isActivityHidden = true;
    } else if (user.privacy_last_seen === 'contacts') {
      const contacts = database.getUserContactPartnerIds(user.id);
      if (!contacts.includes(req.user.id)) {
        isOnline = false;
        lastSeen = null;
        isActivityHidden = true;
      }
    }
  }

  const enriched = {
    ...user,
    pinned_channel_id: user.pinned_channel_id !== undefined ? user.pinned_channel_id : null,
    pinnedChannelId: user.pinned_channel_id !== undefined ? user.pinned_channel_id : null,
    channel_id: user.pinned_channel_id !== undefined ? user.pinned_channel_id : null,
    phone,
    is_online: isOnline,
    last_seen: lastSeen,
    is_activity_hidden: isActivityHidden,
    custom_activity_status: user.custom_activity_status || ''
  };
  return res.json({ user: enriched });
});

// Update Pinned Channel dedicated endpoint
app.post('/api/users/pinned-channel', authMiddleware, (req, res) => {
  const rawId = req.body.channel_id ?? req.body.pinned_channel_id ?? req.body.pinnedChannelId ?? null;
  const parsedId = (rawId !== null && rawId !== '' && rawId !== 0 && rawId !== 'null') ? parseInt(rawId, 10) : null;
  const validId = (!isNaN(parsedId) && parsedId > 0) ? parsedId : null;
  const updatedUser = database.updateUserPinnedChannel(req.user.id, validId);
  return res.json({
    success: true,
    pinned_channel_id: updatedUser?.pinned_channel_id !== undefined ? updatedUser.pinned_channel_id : null
  });
});

// GET /api/users/:userId/gifts
app.get('/api/users/:userId/gifts', authMiddleware, (req, res) => {
  const userId = parseInt(req.params.userId, 10);
  if (!userId) return res.status(400).json({ error: 'Неверный ID пользователя' });
  const gifts = database.getUserGifts(userId, req.user?.id);
  return res.json({ gifts });
});

// GET /api/gifts/:id
app.get('/api/gifts/:id', authMiddleware, (req, res) => {
  const giftId = parseInt(req.params.id, 10);
  if (!giftId) return res.status(400).json({ error: 'Неверный ID подарка' });
  const gift = database.getGiftById(giftId);
  if (!gift) return res.status(404).json({ error: 'Подарок не найден' });
  return res.json({ gift });
});

// POST /api/gifts/:id/pin - Toggle pin gift (up to 3)
app.post('/api/gifts/:id/pin', authMiddleware, (req, res) => {
  const giftId = parseInt(req.params.id, 10);
  if (!giftId) return res.status(400).json({ error: 'Неверный ID подарка' });
  try {
    const result = database.togglePinUserGift(giftId, req.user.id);
    return res.json({ success: true, ...result });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// POST /api/gifts/:id/hide - Toggle hide gift from public
app.post('/api/gifts/:id/hide', authMiddleware, (req, res) => {
  const giftId = parseInt(req.params.id, 10);
  if (!giftId) return res.status(400).json({ error: 'Неверный ID подарка' });
  try {
    const result = database.toggleHideUserGift(giftId, req.user.id);
    return res.json({ success: true, ...result });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// POST /api/gifts/upgrade - Upgrade gift for 1000 Sparks into unique NFT model with backdrops & patterns
app.post('/api/gifts/upgrade', authMiddleware, (req, res) => {
  try {
    const { giftRecordId, preselected } = req.body;
    if (!giftRecordId) {
      return res.status(400).json({ error: 'ID подарка обязателен' });
    }

    const result = database.upgradeUserGift(parseInt(giftRecordId, 10), req.user.id, preselected);

    // Broadcast sparks updated to user
    sendToUser(req.user.id, {
      type: 'sparks_updated',
      sparks: result.sparks
    });

    // Broadcast gift updated event
    const recipientId = result.gift.recipient_id;
    const senderId = result.gift.sender_id;
    const payload = {
      type: 'gift_upgraded',
      gift: result.gift
    };
    sendToUser(recipientId, payload);
    if (senderId && senderId !== recipientId) {
      sendToUser(senderId, payload);
    }

    return res.json({ success: true, ...result });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка улучшения подарка' });
  }
});

// POST /api/gifts/send
app.post('/api/gifts/send', authMiddleware, (req, res) => {
  try {
    const { giftId, recipientUsername, comment } = req.body;
    if (!giftId || !recipientUsername) {
      return res.status(400).json({ error: 'Укажите подарок и юзернейм получателя' });
    }

    const giftItem = GIFTS_CATALOG.find(g => g.id === giftId);
    if (!giftItem) {
      return res.status(400).json({ error: 'Подарок не найден в каталоге' });
    }

    const cleanUsername = recipientUsername.trim().toLowerCase().replace(/^@+/, '');
    const recipient = database.getUserByUsername(cleanUsername);
    if (!recipient) {
      return res.status(404).json({ error: `Пользователь @${cleanUsername} не найден` });
    }

    const sender = database.getUserById(req.user.id);
    if (Number(sender.sparks ?? 0) < giftItem.price) {
      return res.status(400).json({ error: `Недостаточно Sparks. Стоимость: ${giftItem.price}, у вас на балансе: ${Number(sender.sparks ?? 0)}` });
    }

    // Get or create direct chat between sender and recipient
    const chatId = database.getOrCreateDirectChat(sender.id, recipient.id);

    // Purchase & save gift
    const giftRecord = database.sendGift({
      senderId: sender.id,
      recipientId: recipient.id,
      giftId: giftItem.id,
      giftName: giftItem.name,
      giftFile: giftItem.file,
      price: giftItem.price,
      comment: comment || '',
      chatId
    });

    // Create gift notification card in the chat
    const senderFullName = `${sender.first_name || ''} ${sender.last_name || ''}`.trim() || sender.username || 'Пользователь';
    const recipientFullName = `${recipient.first_name || ''} ${recipient.last_name || ''}`.trim() || recipient.username || 'Пользователь';
    
    const giftPayload = JSON.stringify({
      type: 'gift_card',
      giftDbId: giftRecord.id,
      giftId: giftRecord.gift_id,
      giftName: giftRecord.gift_name,
      giftFile: giftRecord.gift_file,
      price: giftRecord.price,
      comment: giftRecord.comment,
      senderId: sender.id,
      senderName: senderFullName,
      senderAvatar: sender.avatar,
      senderUsername: sender.username,
      recipientId: recipient.id,
      recipientName: recipientFullName,
      recipientAvatar: recipient.avatar,
      recipientUsername: recipient.username,
      createdAt: giftRecord.created_at
    });

    const savedMessage = handleOutgoingUserMessage({
      chatId,
      senderId: sender.id,
      text: '[PORTAL_GIFT]:' + giftPayload
    });

    const updatedSender = database.getUserById(sender.id);

    // Broadcast updated sparks balance to sender
    sendToUser(sender.id, {
      type: 'sparks_updated',
      sparks: Number(updatedSender.sparks)
    });

    // Broadcast new gift event to recipient
    sendToUser(recipient.id, {
      type: 'new_gift_received',
      gift: giftRecord,
      message: savedMessage
    });

    return res.json({
      success: true,
      gift: giftRecord,
      sparks: Number(updatedSender.sparks),
      message: savedMessage,
      chatId
    });
  } catch (err) {
    console.error('[Send Gift Error]', err);
    return res.status(500).json({ error: err.message || 'Ошибка отправки подарка' });
  }
});


// ==========================================
// 6.5 Flutter Mobile Fast Sync & Bootstrap API
// ==========================================

// GET /api/sync/bootstrap - Single-request bootstrap for Flutter mobile app
app.get('/api/sync/bootstrap', authMiddleware, (req, res) => {
  try {
    const messagesLimit = Math.min(Number(req.query.limit) || 30, 100);
    const data = database.getBootstrapData(req.user.id, messagesLimit);
    if (!data) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    // Enrich chats with live presence & online statuses
    if (Array.isArray(data.chats)) {
      data.chats = data.chats.map(enrichChatWithOnline);
    }

    return res.json({
      success: true,
      server_time: data.server_time,
      user: data.user,
      chats: data.chats,
      recent_messages: data.recent_messages,
      catalog: GIFTS_CATALOG,
      features: {
        max_upload_size_mb: 50,
        voice_enabled: true,
        gifts_enabled: true,
        reactions_enabled: true,
        channels_limits: {
          free_max: 3,
          premium_max: 8
        }
      }
    });
  } catch (err) {
    console.error('[Sync Bootstrap Error]', err);
    return res.status(500).json({ error: 'Ошибка быстрой синхронизации' });
  }
});

// GET /api/sync/delta - Blazing-fast delta updates since timestamp
app.get('/api/sync/delta', authMiddleware, (req, res) => {
  try {
    const since = req.query.since;
    if (!since) {
      return res.status(400).json({ error: 'Параметр since обязателен' });
    }

    const data = database.getDeltaSync(req.user.id, since);
    if (!data) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    if (Array.isArray(data.chats)) {
      data.chats = data.chats.map(enrichChatWithOnline);
    }

    return res.json({
      success: true,
      server_time: data.server_time,
      user: data.user,
      chats: data.chats,
      messages: data.messages
    });
  } catch (err) {
    console.error('[Sync Delta Error]', err);
    return res.status(500).json({ error: 'Ошибка получения обновлений' });
  }
});

// GET /api/sync/chat/:chatId/history - Fast paginated history before message ID
app.get('/api/sync/chat/:chatId/history', authMiddleware, (req, res) => {
  try {
    const chatId = Number(req.params.chatId);
    const channel = database.getChannelByChatId(chatId, req.user.id);
    const participants = database.getChatParticipantUserIds(chatId);

    if (!channel && !participants.includes(req.user.id)) {
      return res.status(403).json({ error: 'Доступ к чату запрещен' });
    }

    const before = req.query.before ? Number(req.query.before) : null;
    const limit = Math.min(Number(req.query.limit) || 50, 100);
    const messages = database.getChatHistoryBefore(chatId, req.user.id, before, limit);

    return res.json({
      success: true,
      chat_id: chatId,
      messages
    });
  } catch (err) {
    console.error('[Sync Chat History Error]', err);
    return res.status(500).json({ error: 'Ошибка загрузки истории сообщений' });
  }
});

// GET /api/sync/schema - DDL schema for Flutter local SQLite cache
app.get('/api/sync/schema', (req, res) => {
  return res.json({
    version: 1,
    tables: {
      users: `CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        first_name TEXT,
        last_name TEXT,
        username TEXT,
        avatar TEXT,
        phone TEXT,
        email TEXT,
        description TEXT,
        sparks INTEGER DEFAULT 250,
        is_premium INTEGER DEFAULT 0,
        verification TEXT DEFAULT 'none',
        last_seen TEXT,
        updated_at TEXT
      );`,
      chats: `CREATE TABLE IF NOT EXISTS chats (
        id INTEGER PRIMARY KEY,
        title TEXT,
        type TEXT,
        avatar TEXT,
        last_message_text TEXT,
        last_message_time TEXT,
        last_message_sender_id INTEGER,
        unread_count INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        is_channel INTEGER DEFAULT 0,
        participant_id INTEGER,
        updated_at TEXT
      );`,
      messages: `CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY,
        chat_id INTEGER NOT NULL,
        sender_id INTEGER NOT NULL,
        text TEXT,
        reply_markup TEXT,
        reply_to_message_id INTEGER,
        reply_to_text TEXT,
        reply_to_sender_name TEXT,
        created_at TEXT,
        updated_at TEXT,
        is_read INTEGER DEFAULT 0,
        is_edited INTEGER DEFAULT 0,
        likes_count INTEGER DEFAULT 0,
        is_liked INTEGER DEFAULT 0,
        views_count INTEGER DEFAULT 0,
        sender_name TEXT,
        sender_avatar TEXT
      );`
    }
  });
});

// 7. Get User Chats
app.get('/api/chats', authMiddleware, (req, res) => {
  try {
    const rawChats = database.getUserChats(req.user.id) || [];
    const chats = (Array.isArray(rawChats) ? rawChats : []).map(chat => {
      try {
        return enrichChatWithOnline(chat);
      } catch (onlineErr) {
        return chat;
      }
    });
    return res.json({ chats });
  } catch (err) {
    console.error('[API /api/chats Error]', err);
    return res.status(500).json({ error: 'Ошибка загрузки чатов', details: err?.message });
  }
});

// 8. Open or Create Direct Chat
app.post('/api/chats/direct', authMiddleware, (req, res) => {
  const { targetUserId } = req.body;
  if (!targetUserId || targetUserId === req.user.id) {
    return res.status(400).json({ error: 'Неверный идентификатор пользователя' });
  }

  const targetUser = database.getUserById(targetUserId);
  if (!targetUser) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }

  const chatId = database.getOrCreateDirectChat(req.user.id, targetUserId);
  const rawChat = database.getChatById(chatId, req.user.id);
  const chat = enrichChatWithOnline(rawChat);

  return res.json({ chatId, chat });
});

// 9. Get Chat Messages
app.get('/api/chats/:chatId/messages', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const channel = database.getChannelByChatId(chatId, req.user.id);
  const participants = database.getChatParticipantUserIds(chatId);

  // For channels, public preview is allowed; for direct chats, only participants
  if (!channel && !participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  const messages = database.getChatMessages(chatId, req.user.id);
  return res.json({ messages });
});

// 10. Send Message via REST
app.post('/api/chats/:chatId/messages', authMiddleware, (req, res) => {
  if (req.user.is_frozen) {
    return res.status(403).json({ error: 'Ваш аккаунт временно заморожен' });
  }

  const chatId = Number(req.params.chatId);
  const { text, replyToMessageId } = req.body;
  if (!text || !text.trim()) {
    return res.status(400).json({ error: 'Текст сообщения обязателен' });
  }

  const channel = database.getChannelByChatId(chatId, req.user.id);
  if (channel) {
    if (channel.owner_id !== req.user.id) {
      return res.status(403).json({ error: 'Только владелец канала может публиковать сообщения' });
    }
  } else {
    const participants = database.getChatParticipantUserIds(chatId);
    if (!participants.includes(req.user.id)) {
      return res.status(403).json({ error: 'Доступ к чату запрещен' });
    }
  }

  try {
    const message = handleOutgoingUserMessage({
      chatId,
      senderId: req.user.id,
      text: text.trim(),
      replyToMessageId: replyToMessageId ? Number(replyToMessageId) : null
    });
    return res.json({ success: true, message });
  } catch (err) {
    return res.status(403).json({ error: err.message });
  }
});

// 10.1 Edit Message via REST
app.put('/api/messages/:id', authMiddleware, (req, res) => {
  const messageId = Number(req.params.id);
  const { text } = req.body;
  if (!text || !text.trim()) {
    return res.status(400).json({ error: 'Текст сообщения не может быть пустым' });
  }

  const existing = database.getMessageById(messageId, req.user.id);
  if (!existing) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  if (existing.sender_id !== req.user.id) {
    return res.status(403).json({ error: 'Вы можете редактировать только свои сообщения' });
  }

  try {
    const updated = database.editMessage(messageId, text.trim());
    const participants = database.getChatParticipantUserIds(Number(updated.chat_id));
    for (const pId of participants) {
      sendToUser(pId, {
        type: 'message_edited',
        chatId: Number(updated.chat_id),
        message: updated
      });
    }
    return res.json({ success: true, message: updated });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// 10.2 Delete Message via REST (for both users)
app.delete('/api/messages/:id', authMiddleware, (req, res) => {
  const messageId = Number(req.params.id);
  const existing = database.getMessageById(messageId, req.user.id);
  if (!existing) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const chatId = Number(existing.chat_id);
  const channel = database.getChannelByChatId(chatId);
  const isAuthor = existing.sender_id === req.user.id;
  const isChannelOwner = channel && channel.owner_id === req.user.id;

  if (!isAuthor && !isChannelOwner) {
    return res.status(403).json({ error: 'Недостаточно прав для удаления сообщения' });
  }

  try {
    database.deleteMessage(messageId);
    const participants = database.getChatParticipantUserIds(chatId);
    for (const pId of participants) {
      sendToUser(pId, {
        type: 'message_deleted',
        chatId,
        messageId
      });
    }
    return res.json({ success: true, messageId, chatId });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// 10.2.1 Expire View-Once Photo
app.post('/api/messages/:id/expire-photo', authMiddleware, (req, res) => {
  const messageId = Number(req.params.id);
  const existing = database.getMessageById(messageId, req.user.id);
  if (!existing) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const participants = database.getChatParticipantUserIds(Number(existing.chat_id));
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Нет доступа к этому сообщению' });
  }

  if (!existing.text?.startsWith('[PORTAL_PHOTO]:')) {
    return res.status(400).json({ error: 'Сообщение не является фотографией' });
  }

  let photoData;
  try {
    photoData = JSON.parse(existing.text.slice('[PORTAL_PHOTO]:'.length));
  } catch (_) {
    return res.status(400).json({ error: 'Некорректный формат данных' });
  }

  if (!photoData.isViewOnce) {
    return res.status(400).json({ error: 'Фотография не является одноразовой' });
  }

  if (photoData.isExpired) {
    return res.json({ success: true, message: existing });
  }

  // Only the recipient (not the author/sender) viewing the photo expires it
  if (req.user.id === existing.sender_id) {
    return res.json({ success: true, message: existing, ignored: 'sender_view' });
  }

  photoData.isExpired = true;
  photoData.url = '';
  const newPayload = `[PORTAL_PHOTO]:${JSON.stringify(photoData)}`;

  try {
    const updated = database.editMessage(messageId, newPayload, undefined, false);
    for (const pId of participants) {
      sendToUser(pId, {
        type: 'message_edited',
        chatId: Number(updated.chat_id),
        message: updated
      });
    }
    return res.json({ success: true, message: updated });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// 10.3 Pin / Unpin Message
app.post('/api/chats/:chatId/pin', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const { messageId } = req.body;
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  try {
    const { pinnedMessage, isPinned } = database.pinMessage(chatId, messageId ? Number(messageId) : null);
    for (const pId of participants) {
      sendToUser(pId, {
        type: 'chat_pinned_message',
        chatId,
        pinnedMessage,
        isPinned,
        pinnedMessageId: isPinned ? Number(messageId) : null
      });
    }
    return res.json({ success: true, pinnedMessage, isPinned });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// 10.4 Get Pinned Message
app.get('/api/chats/:chatId/pin', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  const pinnedMessage = database.getPinnedMessage(chatId, req.user.id);
  return res.json({ success: true, pinnedMessage });
});

// 10.5 Set / Update Chat Wallpaper (visible to both users)
app.post('/api/chats/:chatId/wallpaper', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const { wallpaperUrl, isBlurred = false } = req.body;
  if (!chatId) {
    return res.status(400).json({ error: 'Chat ID required' });
  }

  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  try {
    database.updateChatWallpaper(chatId, wallpaperUrl || null, isBlurred ? 1 : 0);
    const payload = {
      type: 'chat_wallpaper_updated',
      chatId,
      wallpaper_url: wallpaperUrl || null,
      wallpaper_blur: isBlurred ? 1 : 0,
      updated_by: req.user.id
    };
    for (const pId of participants) {
      sendToUser(pId, payload);
    }
    return res.json({ success: true, wallpaper_url: wallpaperUrl || null, wallpaper_blur: isBlurred ? 1 : 0 });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// 10.6 Saved Messages (Избранное)
app.get('/api/chats/saved', authMiddleware, (req, res) => {
  const savedChatId = database.getOrCreateSavedChat(req.user.id);
  const chat = database.getChatById(savedChatId, req.user.id);
  return res.json({ chat });
});

app.post('/api/saved-messages', authMiddleware, (req, res) => {
  const { text, replyToMessageId } = req.body;
  if (!text) return res.status(400).json({ error: 'Текст обязателен' });
  const savedChatId = database.getOrCreateSavedChat(req.user.id);
  const savedMessage = database.saveMessage(savedChatId, req.user.id, text, null, replyToMessageId || null);
  sendToUser(req.user.id, {
    type: 'new_message',
    message: savedMessage,
    chatId: savedChatId
  });
  sendToUser(req.user.id, {
    type: 'chat_updated',
    chatId: savedChatId,
    lastMessage: savedMessage,
    unreadCount: 0
  });
  return res.json({ success: true, message: savedMessage, chatId: savedChatId });
});

// 11. Mark Chat as Read
app.post('/api/chats/:chatId/read', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  const updatedCount = database.markChatAsRead(chatId, req.user.id);

  for (const pId of participants) {
    if (pId !== req.user.id) {
      sendToUser(pId, {
        type: 'messages_read',
        chatId,
        readerId: req.user.id
      });
    } else {
      sendToUser(pId, {
        type: 'chat_read',
        chatId,
        unreadCount: 0
      });
    }
  }

  return res.json({ success: true, chatId, updatedCount });
});

// 12. Clear Chat History
app.delete('/api/chats/:chatId/messages', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  database.clearChatMessages(chatId);

  for (const pId of participants) {
    sendToUser(pId, {
      type: 'chat_cleared',
      chatId
    });
  }

  return res.json({ success: true, chatId });
});

// 12.1 Pin / Unpin Chat (3 max for regular users, 10 max for Premium users)
app.post('/api/chats/:chatId/pin-chat', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  try {
    const result = database.togglePinChat(chatId, req.user.id);
    return res.json({ success: true, chatId, is_pinned: result.is_pinned });
  } catch (err) {
    return res.status(400).json({ error: err.message, code: err.code });
  }
});

// 12.2 Delete Chat Completely for Both Participants
app.delete('/api/chats/:chatId', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Доступ к чату запрещен' });
  }

  try {
    database.deleteChat(chatId);

    // Notify ALL participants in real time so the chat is removed from everyone's list
    for (const pId of participants) {
      sendToUser(pId, {
        type: 'chat_deleted',
        chatId
      });
    }

    return res.json({ success: true, chatId });
  } catch (err) {
    console.error('Failed to delete chat:', err);
    return res.status(500).json({ error: 'Не удалось удалить чат' });
  }
});

// ================= CHANNEL ROUTES =================

// 0. Channel Limits
app.get('/api/channels/limits', authMiddleware, (req, res) => {
  const freshUser = database.getUserById(req.user.id);
  const isPremium = Boolean(freshUser?.is_premium);
  const maxChannels = isPremium ? 8 : 3;
  const currentChannelsCount = database.getChannelsCountByOwner(req.user.id);

  return res.json({
    isPremium,
    maxChannels,
    currentChannelsCount,
    canCreate: currentChannelsCount < maxChannels
  });
});

// 1. Create a Channel
app.post('/api/channels', authMiddleware, (req, res) => {
  // Check user channel limit
  const freshUser = database.getUserById(req.user.id);
  const isPremium = Boolean(freshUser?.is_premium);
  const maxChannels = isPremium ? 8 : 3;
  const currentChannelsCount = database.getChannelsCountByOwner(req.user.id);

  if (currentChannelsCount >= maxChannels) {
    if (!isPremium) {
      return res.status(403).json({
        error: `Лимит создания каналов исчерпан (${currentChannelsCount} из ${maxChannels}). С подпиской Portal Premium можно создать до 8 каналов.`,
        limitReached: true,
        maxChannels,
        currentChannelsCount,
        isPremium: false
      });
    } else {
      return res.status(403).json({
        error: `Вы достигли максимального лимита создания каналов (${currentChannelsCount} из ${maxChannels}).`,
        limitReached: true,
        maxChannels,
        currentChannelsCount,
        isPremium: true
      });
    }
  }

  const { title, username, avatar, description } = req.body;
  if (!title || !title.trim()) {
    return res.status(400).json({ error: 'Название канала обязательно' });
  }
  if (!username || !username.trim()) {
    return res.status(400).json({ error: 'Имя пользователя (@username) обязательно' });
  }

  const cleanUsername = username.trim().toLowerCase().replace(/^@+/, '');
  if (cleanUsername.length < 5) {
    return res.status(400).json({ error: 'Имя пользователя должно содержать минимум 5 символов' });
  }
  if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
    return res.status(400).json({ error: 'Только латинские буквы, цифры и символ подчеркивания' });
  }
  if (!database.isUsernameAvailable(cleanUsername)) {
    return res.status(400).json({ error: 'Это имя пользователя уже занято' });
  }

  const channel = database.createChannel({
    ownerId: req.user.id,
    title: title.trim(),
    username: cleanUsername,
    avatar: avatar || '',
    description: description ? description.trim() : ''
  });

  return res.json({ success: true, channel });
});

// 2. Subscribe to Channel
app.post('/api/channels/:chatId/subscribe', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const channel = database.getChannelByChatId(chatId, req.user.id);
  if (!channel) {
    return res.status(404).json({ error: 'Канал не найден' });
  }

  const updated = database.subscribeToChannel(chatId, req.user.id);
  return res.json({ success: true, channel: updated });
});

// 3. Unsubscribe from Channel
app.post('/api/channels/:chatId/unsubscribe', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const channel = database.getChannelByChatId(chatId, req.user.id);
  if (!channel) {
    return res.status(404).json({ error: 'Канал не найден' });
  }

  const updated = database.unsubscribeFromChannel(chatId, req.user.id);
  return res.json({ success: true, channel: updated });
});

// 4. Get Channel Details
app.get('/api/channels/:chatId', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const channel = database.getChannelByChatId(chatId, req.user.id);
  if (!channel) {
    return res.status(404).json({ error: 'Канал не найден' });
  }
  return res.json({ success: true, channel });
});

// Gift Artifact to Channel
app.post('/api/channels/:chatId/gift-artifact', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  try {
    const result = database.giftArtifactToChannel(chatId, req.user.id);

    // Notify the user about updated balance
    sendToUser(req.user.id, {
      type: 'user_profile_updated',
      userId: req.user.id,
      artifacts: result.userArtifacts
    });

    // Notify subscribers/participants about channel artifact update
    const participantUserIds = database.getChatParticipantUserIds(chatId);
    participantUserIds.forEach(userId => {
      sendToUser(userId, {
        type: 'channel_updated',
        chat_id: chatId,
        artifacts: result.channelArtifacts,
        channel: result.updatedChannel
      });
    });

    return res.json({
      success: true,
      message: 'Артефакт успешно передан!',
      userArtifacts: result.userArtifacts,
      channelArtifacts: result.channelArtifacts,
      channel: result.updatedChannel
    });
  } catch (err) {
    console.error('Error gifting artifact:', err);
    return res.status(400).json({ error: err.message || 'Ошибка передачи артефакта' });
  }
});

// 5. Update Channel (Owner only)
const handleChannelUpdate = (req, res) => {
  const chatId = Number(req.params.chatId);
  const { title, username, description, avatar } = req.body;

  try {
    const updatedChannel = database.updateChannel(chatId, req.user.id, {
      title,
      username,
      description,
      avatar
    });

    // Notify all subscribers in real-time
    const participantUserIds = database.getChatParticipantUserIds(chatId);
    participantUserIds.forEach(userId => {
      sendToUser(userId, {
        type: 'channel_updated',
        chat_id: chatId,
        channel: updatedChannel
      });
    });

    return res.json({ success: true, channel: updatedChannel });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Ошибка обновления канала' });
  }
};

app.put('/api/channels/:chatId', authMiddleware, handleChannelUpdate);
app.post('/api/channels/:chatId/edit', authMiddleware, handleChannelUpdate);

// ================= GROUP ROUTES =================

// 1. Create a Group
app.post('/api/groups', authMiddleware, (req, res) => {
  const { title, avatar, description } = req.body;
  if (!title || !title.trim()) {
    return res.status(400).json({ error: 'Название группы обязательно' });
  }

  const group = database.createGroup({
    ownerId: req.user.id,
    title: title.trim(),
    avatar: avatar || '',
    description: description ? description.trim() : ''
  });

  return res.json({ success: true, group });
});

// 2. Preview Group by Invite Code
app.get('/api/groups/preview/:inviteCode', optionalAuthMiddleware, (req, res) => {
  const inviteCode = req.params.inviteCode;
  const currentUserId = req.user ? req.user.id : null;
  const group = database.getGroupByInviteCode(inviteCode, currentUserId);
  if (!group) {
    return res.status(404).json({ error: 'Группа не найдена' });
  }
  return res.json({ success: true, group });
});

// 3. Join Group via Invite Code
app.post('/api/groups/join', authMiddleware, (req, res) => {
  const { inviteCode } = req.body;
  if (!inviteCode || !inviteCode.trim()) {
    return res.status(400).json({ error: 'Код приглашения обязателен' });
  }

  try {
    const result = database.joinGroup(inviteCode.trim(), req.user.id);
    const group = result.group;

    if (result.newlyJoined) {
      // Create a system message announcing the user joined
      const userName = [req.user.first_name, req.user.last_name].filter(Boolean).join(' ') || 'Пользователь';
      const systemText = `[PORTAL_SYSTEM]:${userName} присоединился к группе`;
      const systemMessage = database.saveMessage(group.chat_id, req.user.id, systemText);

      // Broadcast new message and updated group event to all participants
      const participants = database.getChatParticipantUserIds(group.chat_id);
      for (const pId of participants) {
        sendToUser(pId, {
          type: 'new_message',
          message: systemMessage,
          chatId: group.chat_id
        });
        sendToUser(pId, {
          type: 'chat_updated',
          chatId: group.chat_id,
          lastMessage: systemMessage,
          unreadCount: database.getUnreadCountForChat(group.chat_id, pId)
        });
        sendToUser(pId, {
          type: 'group_member_joined',
          chatId: group.chat_id,
          membersCount: group.members_count
        });
      }
    }

    return res.json({ success: true, group, chatId: group.chat_id });
  } catch (err) {
    return res.status(400).json({ error: err.message || 'Не удалось присоединиться к группе' });
  }
});

// 4. Leave Group
app.post('/api/groups/:chatId/leave', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const group = database.getGroupByChatId(chatId, req.user.id);
  if (!group) {
    return res.status(404).json({ error: 'Группа не найдена' });
  }

  database.leaveGroup(chatId, req.user.id);

  // Send system message that user left
  const userName = [req.user.first_name, req.user.last_name].filter(Boolean).join(' ') || 'Пользователь';
  const systemText = `[PORTAL_SYSTEM]:${userName} покинул группу`;
  const systemMessage = database.saveMessage(chatId, req.user.id, systemText);

  const remainingParticipants = database.getChatParticipantUserIds(chatId);
  for (const pId of remainingParticipants) {
    sendToUser(pId, {
      type: 'new_message',
      message: systemMessage,
      chatId
    });
    sendToUser(pId, {
      type: 'chat_updated',
      chatId,
      lastMessage: systemMessage,
      unreadCount: database.getUnreadCountForChat(chatId, pId)
    });
  }

  return res.json({ success: true });
});

// 5. Get Group Members
app.get('/api/groups/:chatId/members', authMiddleware, (req, res) => {
  const chatId = Number(req.params.chatId);
  const members = database.getGroupMembers(chatId);
  return res.json({ success: true, members });
});

// ================= POST INTERACTIONS ROUTES (LIKES, VIEWS, COMMENTS) =================

// 1. Toggle Like on a message / post
app.post('/api/messages/:messageId/like', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const msg = database.getMessageById(messageId, req.user.id);
  if (!msg) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const result = database.togglePostLike(messageId, req.user.id);
  
  // Broadcast update to all chat participants
  const participants = database.getChatParticipantUserIds(msg.chat_id);
  const eventPayload = {
    type: 'post_like_updated',
    chatId: msg.chat_id,
    messageId,
    userId: req.user.id,
    isLiked: result.isLiked,
    likesCount: result.likesCount
  };
  for (const pId of participants) {
    sendToUser(pId, eventPayload);
  }

  return res.json({ success: true, ...result, chatId: msg.chat_id });
});

// 1.1 Add Sparks reaction (Stars reaction) to a message / post
app.post('/api/messages/:messageId/sparks-reaction', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const msg = database.getMessageById(messageId, req.user.id);
  if (!msg) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const { amount = 1, isAnonymous = false } = req.body || {};
  try {
    const result = database.addPostSparksReaction(messageId, req.user.id, amount, isAnonymous);

    // Broadcast sparks balance update to sender
    sendToUser(req.user.id, {
      type: 'sparks_updated',
      sparks: result.remainingSparks
    });

    // If channel owner received reward, broadcast to owner too
    if (result.channelOwnerId && result.channelOwnerId !== req.user.id) {
      const ownerUser = database.getUserById(result.channelOwnerId);
      if (ownerUser) {
        sendToUser(result.channelOwnerId, {
          type: 'sparks_updated',
          sparks: Number(ownerUser.sparks)
        });
      }
    }

    // Broadcast post reaction update to all chat participants
    const participants = database.getChatParticipantUserIds(msg.chat_id);
    const eventPayload = {
      type: 'post_sparks_updated',
      chatId: msg.chat_id,
      messageId,
      userId: req.user.id,
      addedAmount: result.addedAmount,
      sparksCount: result.sparksCount,
      leaders: result.leaders
    };
    for (const pId of participants) {
      sendToUser(pId, eventPayload);
    }

    return res.json({ success: true, ...result, chatId: msg.chat_id });
  } catch (err) {
    console.error('Sparks reaction error:', err);
    return res.status(400).json({ error: err.message || 'Ошибка отправки реакции' });
  }
});

// 1.2 Get Sparks reaction leaders for a message
app.get('/api/messages/:messageId/sparks-leaders', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const leaders = database.getPostSparksLeaders(messageId);
  return res.json({ success: true, messageId, leaders });
});

// 1.3 Toggle standard message reaction (iOS Apple emoji reaction)
app.post('/api/messages/:messageId/reactions', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const { emoji } = req.body;
  if (!messageId || !emoji) {
    return res.status(400).json({ error: 'messageId and emoji are required' });
  }

  const msg = database.getMessageById(messageId, req.user.id);
  if (!msg) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const chatId = Number(msg.chat_id);
  const channel = database.getChannelByChatId(chatId);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!channel && !participants.includes(req.user.id)) {
    return res.status(403).json({ error: 'Нет доступа к чату' });
  }

  const reactions = database.toggleMessageReaction(messageId, req.user.id, emoji);
  const eventPayload = {
    type: 'message_reaction_updated',
    chatId,
    messageId,
    reactions
  };
  for (const pId of participants) {
    sendToUser(pId, eventPayload);
  }
  if (!participants.includes(req.user.id)) {
    sendToUser(req.user.id, eventPayload);
  }

  return res.json({ success: true, messageId, reactions });
});

// 2. Record single post view
app.post('/api/messages/:messageId/view', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const msg = database.getMessageById(messageId, req.user.id);
  if (!msg) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const result = database.recordPostView(messageId, req.user.id);

  const participants = database.getChatParticipantUserIds(msg.chat_id);
  const eventPayload = {
    type: 'post_view_updated',
    chatId: msg.chat_id,
    messageId,
    viewsCount: result.viewsCount
  };
  for (const pId of participants) {
    sendToUser(pId, eventPayload);
  }

  return res.json({ success: true, ...result, chatId: msg.chat_id });
});

// 3. Record batch views for multiple messages
app.post('/api/messages/views', authMiddleware, (req, res) => {
  const { messageIds, chatId } = req.body;
  if (!Array.isArray(messageIds) || messageIds.length === 0) {
    return res.json({ success: true, results: [] });
  }

  const results = database.recordPostViews(messageIds, req.user.id);

  if (chatId) {
    const participants = database.getChatParticipantUserIds(Number(chatId));
    const eventPayload = {
      type: 'post_views_batch_updated',
      chatId: Number(chatId),
      results
    };
    for (const pId of participants) {
      sendToUser(pId, eventPayload);
    }
  }

  return res.json({ success: true, results });
});

// 4. Get Comments for a message / post
app.get('/api/messages/:messageId/comments', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const comments = database.getPostComments(messageId);
  return res.json({ success: true, comments });
});

// 5. Add Comment to a message / post
app.post('/api/messages/:messageId/comments', authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const { text } = req.body;
  if (!text || !text.trim()) {
    return res.status(400).json({ error: 'Текст комментария обязателен' });
  }

  const msg = database.getMessageById(messageId, req.user.id);
  if (!msg) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }

  const result = database.addPostComment(messageId, req.user.id, text.trim());

  // Broadcast comment to chat participants
  const participants = database.getChatParticipantUserIds(msg.chat_id);
  const eventPayload = {
    type: 'post_comment_added',
    chatId: msg.chat_id,
    messageId,
    comment: result.comment,
    commentsCount: result.commentsCount
  };
  for (const pId of participants) {
    sendToUser(pId, eventPayload);
  }

  return res.json({ success: true, ...result, chatId: msg.chat_id });
});

// ==========================================================================
// TRANSLATION SERVICE (FREE GOOGLE TRANSLATE GTX PROXY WITH CACHING)
// ==========================================================================
const translationCache = new Map();

const LANGUAGE_NAMES = {
  'en': 'английского',
  'de': 'немецкого',
  'fr': 'французского',
  'es': 'испанского',
  'it': 'итальянского',
  'zh': 'китайского',
  'zh-CN': 'китайского',
  'zh-TW': 'китайского',
  'ja': 'японского',
  'ko': 'корейского',
  'ar': 'арабского',
  'tr': 'турецкого',
  'pl': 'польского',
  'uk': 'украинского',
  'be': 'белорусского',
  'kk': 'казахского',
  'uz': 'узбекского',
  'pt': 'португальского',
  'nl': 'нидерландского',
  'sv': 'шведского',
  'no': 'норвежского',
  'fi': 'финского',
  'cs': 'чешского',
  'ro': 'румынского',
  'bg': 'болгарского',
  'el': 'греческого',
  'he': 'иврита',
  'hi': 'хинди',
  'id': 'индонезийского',
  'vi': 'вьетнамского',
  'th': 'тайского',
  'fa': 'персидского'
};

async function translateSingleText(text, targetLang = 'ru') {
  const trimmed = (text || '').trim();
  if (!trimmed) return { original: text, translated: text, detectedLang: 'ru' };

  const cacheKey = `${targetLang}:${trimmed}`;
  if (translationCache.has(cacheKey)) {
    return translationCache.get(cacheKey);
  }

  const endpoints = [
    `https://translate.googleapis.com/translate_a/single?client=dict-chrome-ex&sl=auto&tl=${encodeURIComponent(targetLang)}&dt=t&q=${encodeURIComponent(trimmed)}`,
    `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=${encodeURIComponent(targetLang)}&dt=t&q=${encodeURIComponent(trimmed)}`
  ];

  for (const url of endpoints) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        const data = await response.json();
        const translatedText = Array.isArray(data[0])
          ? data[0].map(s => s[0]).join('')
          : trimmed;
        const detectedLang = data[2] || 'auto';

        const result = {
          original: trimmed,
          translated: translatedText,
          detectedLang
        };

        if (translationCache.size > 5000) {
          const firstKey = translationCache.keys().next().value;
          translationCache.delete(firstKey);
        }
        translationCache.set(cacheKey, result);

        return result;
      }
    } catch (err) {
      console.warn('[Translate] Endpoint attempt failed:', err.message);
    }
  }

  return { original: trimmed, translated: trimmed, detectedLang: 'unknown' };
}

app.post('/api/translate', authMiddleware, async (req, res) => {
  try {
    // Check premium membership requirement
    if (!req.user?.is_premium) {
      return res.status(403).json({
        error: 'PREMIUM_REQUIRED',
        message: 'Перевод сообщений доступен только с подпиской Portal Premium'
      });
    }

    const { messages, text, texts } = req.body;

    if (Array.isArray(messages)) {
      const translations = {};
      const langCounts = {};

      for (const item of messages) {
        if (!item || !item.text) continue;
        const trans = await translateSingleText(item.text, 'ru');
        translations[item.id] = trans.translated;
        if (trans.detectedLang && trans.detectedLang !== 'ru' && trans.detectedLang !== 'auto') {
          langCounts[trans.detectedLang] = (langCounts[trans.detectedLang] || 0) + 1;
        }
      }

      let mostCommonLang = 'en';
      let maxCount = 0;
      for (const [l, cnt] of Object.entries(langCounts)) {
        if (cnt > maxCount) {
          maxCount = cnt;
          mostCommonLang = l;
        }
      }

      return res.json({
        success: true,
        translations,
        detectedLang: mostCommonLang,
        langName: LANGUAGE_NAMES[mostCommonLang] || mostCommonLang
      });
    }

    if (typeof text === 'string') {
      const result = await translateSingleText(text, 'ru');
      return res.json({
        success: true,
        ...result,
        langName: LANGUAGE_NAMES[result.detectedLang] || result.detectedLang
      });
    }

    if (Array.isArray(texts)) {
      const results = await Promise.all(texts.map(t => translateSingleText(t, 'ru')));
      return res.json({ success: true, results });
    }

    return res.status(400).json({ error: 'Требуется поле messages или text' });
  } catch (err) {
    console.error('[Translate] Server error:', err);
    return res.status(500).json({ error: 'Ошибка перевода', message: err.message });
  }
});

// 13. Upload Avatar (Base64 handler)
app.post('/api/upload/avatar', authMiddleware, (req, res) => {
  const { imageBase64 } = req.body;
  if (!imageBase64 || typeof imageBase64 !== 'string') {
    return res.status(400).json({ error: 'Изображение не передано' });
  }

  try {
    const matches = imageBase64.match(/^data:([A-Za-z-+\/]+);base64,(.+)$/);
    if (!matches || matches.length !== 3) {
      if (imageBase64.startsWith('/uploads/') || imageBase64.startsWith('http')) {
        const updatedUser = database.updateUserAvatar(req.user.id, imageBase64);
        return res.json({ success: true, url: imageBase64, user: updatedUser });
      }
      return res.json({ url: imageBase64 });
    }

    const ext = matches[1].split('/')[1] || 'jpg';
    const buffer = Buffer.from(matches[2], 'base64');
    const filename = `avatar_${req.user.id}_${Date.now()}.${ext}`;

    const uploadsDir = path.join(__dirname, 'uploads');
    if (!fs.existsSync(uploadsDir)) {
      fs.mkdirSync(uploadsDir, { recursive: true });
    }
    const filePath = path.join(uploadsDir, filename);
    fs.writeFileSync(filePath, buffer);

    // Mirror to dist/uploads and public/uploads for Nginx/Vite direct static serving
    const distUploads = path.join(__dirname, '../dist/uploads');
    if (fs.existsSync(distUploads)) {
      try {
        fs.writeFileSync(path.join(distUploads, filename), buffer);
      } catch (e) {}
    }
    const publicUploads = path.join(__dirname, '../public/uploads');
    if (fs.existsSync(publicUploads)) {
      try {
        fs.writeFileSync(path.join(publicUploads, filename), buffer);
      } catch (e) {}
    }

    const url = `/uploads/${filename}`;
    const updatedUser = database.updateUserAvatar(req.user.id, url);

    return res.json({
      success: true,
      url,
      user: updatedUser
    });
  } catch (err) {
    console.error('Error saving avatar:', err);
    return res.status(500).json({ error: 'Не удалось сохранить изображение' });
  }
});

// 14. Upload Voice Message (Supports multipart/form-data and base64 JSON)
app.post('/api/upload-voice', authMiddleware, (req, res) => {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadVoiceMulter.single('voice')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: err.message || 'Ошибка загрузки аудио' });
      }
      if (!req.file) {
        return res.status(400).json({ error: 'Аудио файл не передан' });
      }
      const url = `/uploads/${req.file.filename}`;
      let duration = parseFloat(req.body.duration) || 0;
      let waveform = [];
      try {
        if (req.body.waveform) {
          waveform = typeof req.body.waveform === 'string' ? JSON.parse(req.body.waveform) : req.body.waveform;
        }
      } catch (_) {}
      return res.json({ url, duration, waveform: Array.isArray(waveform) ? waveform : [] });
    });
  } else {
    // Base64 JSON fallback
    const { audioBase64, duration, waveform } = req.body;
    if (!audioBase64 || typeof audioBase64 !== 'string') {
      return res.status(400).json({ error: 'Аудио данные не переданы' });
    }
    try {
      const matches = audioBase64.match(/^data:([A-Za-z-+\/]+);base64,(.+)$/);
      const base64Data = matches ? matches[2] : audioBase64;
      const mime = matches ? matches[1] : 'audio/webm';
      const ext = mime.includes('mp4') || mime.includes('m4a') ? '.m4a' : mime.includes('ogg') ? '.ogg' : '.webm';
      const filename = `voice_${Date.now()}_${crypto.randomBytes(4).toString('hex')}${ext}`;
      const filePath = path.join(__dirname, 'uploads', filename);

      fs.writeFileSync(filePath, Buffer.from(base64Data, 'base64'));

      let parsedWaveform = [];
      try {
        if (waveform) {
          parsedWaveform = typeof waveform === 'string' ? JSON.parse(waveform) : waveform;
        }
      } catch (_) {}

      return res.json({
        url: `/uploads/${filename}`,
        duration: parseFloat(duration) || 0,
        waveform: Array.isArray(parsedWaveform) ? parsedWaveform : []
      });
    } catch (err) {
      console.error('Error saving voice message:', err);
      return res.status(500).json({ error: 'Не удалось сохранить голосовое сообщение' });
    }
  }
});

// 15. Upload Photo (supports multipart/form-data and base64 JSON)
app.post('/api/upload-photos', authMiddleware, (req, res) => {
  uploadPhotoMulter.array('photos', 5)(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Ошибка загрузки фотографий' });
    }
    if (!req.files || req.files.length === 0) {
      return res.status(400).json({ error: 'Файлы не переданы' });
    }
    const urls = req.files.map((file) => `/uploads/${file.filename}`);
    return res.json({ ok: true, urls, filenames: req.files.map((f) => f.filename) });
  });
});

app.post('/api/upload-photo', authMiddleware, (req, res) => {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('multipart/form-data')) {
    uploadPhotoMulter.single('photo')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: err.message || 'Ошибка загрузки фото' });
      }
      if (!req.file) {
        return res.status(400).json({ error: 'Файл фото не передан' });
      }
      const url = `/uploads/${req.file.filename}`;
      return res.json({ ok: true, url, filename: req.file.filename });
    });
  } else {
    // Base64 JSON fallback
    const { photoBase64 } = req.body;
    if (!photoBase64 || typeof photoBase64 !== 'string') {
      return res.status(400).json({ error: 'Фото не передано' });
    }
    try {
      const matches = photoBase64.match(/^data:([A-Za-z-+\/]+);base64,(.+)$/);
      const base64Data = matches ? matches[2] : photoBase64;
      const mime = matches ? matches[1] : 'image/jpeg';
      const ext = mime.includes('png') ? '.png' : mime.includes('webp') ? '.webp' : mime.includes('gif') ? '.gif' : '.jpg';
      const filename = `photo_${Date.now()}_${crypto.randomBytes(4).toString('hex')}${ext}`;
      const filePath = path.join(uploadsDir, filename);
      fs.writeFileSync(filePath, Buffer.from(base64Data, 'base64'));
      const url = `/uploads/${filename}`;
      return res.json({ ok: true, url, filename });
    } catch (err) {
      console.error('Error saving photo:', err);
      return res.status(500).json({ error: 'Не удалось сохранить фото' });
    }
  }
});

// 15.1 Upload Video
app.post('/api/upload-video', authMiddleware, (req, res) => {
  uploadVideoMulter.single('video')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Ошибка загрузки видео' });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'Файл видео не передан' });
    }
    const url = `/uploads/${req.file.filename}`;
    return res.json({
      ok: true,
      url,
      filename: req.file.filename,
      originalName: req.file.originalname,
      size: req.file.size
    });
  });
});

// 15.2 Upload Document / File
app.post('/api/upload-file', authMiddleware, (req, res) => {
  uploadFileMulter.single('file')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message || 'Ошибка загрузки файла' });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'Файл не передан' });
    }
    const url = `/uploads/${req.file.filename}`;
    return res.json({
      ok: true,
      url,
      filename: req.file.filename,
      originalName: req.file.originalname,
      size: req.file.size,
      mimeType: req.file.mimetype
    });
  });
});

// ================= TELEGRAM-COMPATIBLE BOT HTTP API =================

// Helper to extract clean token parameter from either /bot<token>/... or /api/bot<token>/...
const getCleanToken = (tokenParam) => {
  if (!tokenParam) return '';
  return tokenParam.startsWith('bot') ? tokenParam.slice(3) : tokenParam;
};

// 1. getMe
const handleGetMe = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }
  return res.json({
    ok: true,
    result: {
      id: bot.id,
      is_bot: true,
      first_name: bot.first_name,
      username: bot.username,
      description: bot.description
    }
  });
};

app.get(['/bot:token/getMe', '/api/bot:token/getMe'], handleGetMe);

// 2. getUpdates (Long-Polling supported)
const handleGetUpdates = async (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const offset = Number(req.query.offset || req.body?.offset || 0);
  const limit = Math.min(Number(req.query.limit || req.body?.limit || 100), 100);
  const timeout = Math.min(Number(req.query.timeout || req.body?.timeout || 0), 50);

  const fetchFormattedUpdates = () => {
    const rawUpdates = database.getBotUpdates(bot.id, offset, limit);
    return rawUpdates.map(u => {
      let replyMarkup = null;
      if (u.reply_markup) {
        try {
          replyMarkup = typeof u.reply_markup === 'string' ? JSON.parse(u.reply_markup) : u.reply_markup;
        } catch (_) {}
      }

      if (u.update_type === 'callback_query') {
        return {
          update_id: u.update_id,
          callback_query: {
            id: u.callback_id,
            from: {
              id: u.user_id,
              is_bot: false,
              first_name: u.first_name || '',
              last_name: u.last_name || '',
              username: u.username || ''
            },
            message: {
              message_id: u.message_id,
              chat: {
                id: u.chat_id,
                type: 'private'
              },
              date: Math.floor(new Date(u.message_created_at || u.update_created_at).getTime() / 1000),
              text: u.text,
              reply_markup: replyMarkup || undefined
            },
            chat_instance: `portal_chat_${u.chat_id}`,
            data: u.callback_data
          }
        };
      }

      return {
        update_id: u.update_id,
        message: {
          message_id: u.message_id,
          from: {
            id: u.sender_id,
            is_bot: false,
            first_name: u.first_name || '',
            last_name: u.last_name || '',
            username: u.username || ''
          },
          chat: {
            id: u.chat_id,
            type: 'private'
          },
          date: Math.floor(new Date(u.message_created_at || u.update_created_at).getTime() / 1000),
          text: u.text,
          reply_markup: replyMarkup || undefined
        }
      };
    });
  };

  const initial = fetchFormattedUpdates();
  if (initial.length > 0 || timeout <= 0) {
    return res.json({ ok: true, result: initial });
  }

  // Long-polling wait for incoming updates
  let resolved = false;
  const timeoutMs = timeout * 1000;

  const onNewUpdate = (botId) => {
    if ((Number(botId) === Number(bot.id) || !botId) && !resolved) {
      resolved = true;
      botEvents.off('update', onNewUpdate);
      clearTimeout(timer);
      const updates = fetchFormattedUpdates();
      if (!res.headersSent) {
        return res.json({ ok: true, result: updates });
      }
    }
  };

  botEvents.on('update', onNewUpdate);

  const timer = setTimeout(() => {
    if (!resolved) {
      resolved = true;
      botEvents.off('update', onNewUpdate);
      if (!res.headersSent) {
        return res.json({ ok: true, result: [] });
      }
    }
  }, timeoutMs);

  res.on('close', () => {
    if (!resolved) {
      resolved = true;
      botEvents.off('update', onNewUpdate);
      clearTimeout(timer);
    }
  });
};

app.get(['/bot:token/getUpdates', '/api/bot:token/getUpdates'], handleGetUpdates);
app.post(['/bot:token/getUpdates', '/api/bot:token/getUpdates'], handleGetUpdates);

// Helper for validating and sanitizing inline keyboards
function sanitizeReplyMarkup(markup) {
  if (!markup) return null;
  let parsed = markup;
  if (typeof markup === 'string') {
    try {
      parsed = JSON.parse(markup);
    } catch (_) {
      return null;
    }
  }
  if (!parsed || typeof parsed !== 'object') return null;

  if (Array.isArray(parsed.inline_keyboard)) {
    const cleanKeyboard = parsed.inline_keyboard
      .filter(row => Array.isArray(row))
      .map(row => 
        row
          .filter(btn => btn && typeof btn === 'object' && btn.text)
          .map(btn => {
            const cleanBtn = { text: String(btn.text).trim() };
            if (btn.callback_data !== undefined) {
              cleanBtn.callback_data = String(btn.callback_data);
            }
            if (btn.url !== undefined) {
              cleanBtn.url = String(btn.url).trim();
            }
            return cleanBtn;
          })
      )
      .filter(row => row.length > 0);

    return cleanKeyboard.length > 0 ? { inline_keyboard: cleanKeyboard } : null;
  }

  return null;
}

// 3. sendMessage
const handleBotSendMessage = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const { chat_id, text, reply_markup } = req.body;
  if (!chat_id || !text || !String(text).trim()) {
    return res.status(400).json({ ok: false, error_code: 400, description: 'Bad Request: chat_id and text are required' });
  }

  const chatId = Number(chat_id);
  const participants = database.getChatParticipantUserIds(chatId);
  if (!participants.includes(bot.id)) {
    return res.status(403).json({ ok: false, error_code: 403, description: 'Forbidden: bot is not a participant in this chat' });
  }

  const cleanMarkup = sanitizeReplyMarkup(reply_markup);
  const savedMessage = database.saveMessage(chatId, bot.id, String(text).trim(), cleanMarkup);

  // Real-time broadcast to all chat participants
  const payload = {
    type: 'new_message',
    message: savedMessage,
    chatId
  };

  for (const pId of participants) {
    sendToUser(pId, payload);
    const unreadCount = database.getUnreadCountForChat(chatId, pId);
    sendToUser(pId, {
      type: 'chat_updated',
      chatId,
      lastMessage: savedMessage,
      unreadCount
    });

    if (pId !== bot.id) {
      notifyUserNewMessage(pId, savedMessage, chatId, bot.id);
    }
  }

  return res.json({
    ok: true,
    result: {
      message_id: savedMessage.id,
      from: {
        id: bot.id,
        is_bot: true,
        first_name: bot.first_name,
        username: bot.username
      },
      chat: {
        id: chatId,
        type: 'private'
      },
      date: Math.floor(new Date(savedMessage.created_at).getTime() / 1000),
      text: savedMessage.text,
      reply_markup: savedMessage.reply_markup || undefined
    }
  });
};

app.post(['/bot:token/sendMessage', '/api/bot:token/sendMessage'], handleBotSendMessage);

// 3. sendPhoto
const handleBotSendPhoto = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const contentType = req.headers['content-type'] || '';
  const processSend = (chat_id, photoUrl, caption, reply_markup) => {
    if (!chat_id || !photoUrl) {
      return res.status(400).json({ ok: false, error_code: 400, description: 'Bad Request: chat_id and photo are required' });
    }

    const chatId = Number(chat_id);
    const participants = database.getChatParticipantUserIds(chatId);
    if (!participants.includes(bot.id)) {
      return res.status(403).json({ ok: false, error_code: 403, description: 'Forbidden: bot is not a participant of this chat' });
    }

    const cleanMarkup = sanitizeReplyMarkup(reply_markup);
    const photoPayload = `[PORTAL_PHOTO]:${JSON.stringify({ url: photoUrl, caption: caption ? String(caption).trim() : '' })}`;
    const savedMessage = database.saveMessage(chatId, bot.id, photoPayload, cleanMarkup);

    const payload = {
      type: 'new_message',
      message: savedMessage,
      chatId
    };

    for (const pId of participants) {
      sendToUser(pId, payload);
      const unreadCount = database.getUnreadCountForChat(chatId, pId);
      sendToUser(pId, {
        type: 'chat_updated',
        chatId,
        lastMessage: savedMessage,
        unreadCount
      });

      if (pId !== bot.id) {
        notifyUserNewMessage(pId, savedMessage, chatId, bot.id);
      }
    }

    return res.json({
      ok: true,
      result: {
        message_id: savedMessage.id,
        from: {
          id: bot.id,
          is_bot: true,
          first_name: bot.first_name,
          username: bot.username
        },
        chat: {
          id: chatId,
          type: 'private'
        },
        date: Math.floor(new Date(savedMessage.created_at).getTime() / 1000),
        photo: [{ file_id: `file_${savedMessage.id}`, url: photoUrl }],
        caption: caption || undefined,
        reply_markup: savedMessage.reply_markup || undefined
      }
    });
  };

  if (contentType.includes('multipart/form-data')) {
    uploadPhotoMulter.single('photo')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ ok: false, error_code: 400, description: err.message || 'Photo upload failed' });
      }
      const photoUrl = req.file ? `/uploads/${req.file.filename}` : req.body.photo;
      let replyMarkup = req.body.reply_markup;
      if (typeof replyMarkup === 'string') {
        try { replyMarkup = JSON.parse(replyMarkup); } catch (_) {}
      }
      return processSend(req.body.chat_id, photoUrl, req.body.caption, replyMarkup);
    });
  } else {
    const { chat_id, photo, caption, reply_markup } = req.body;
    return processSend(chat_id, photo, caption, reply_markup);
  }
};

app.post(['/bot:token/sendPhoto', '/api/bot:token/sendPhoto'], handleBotSendPhoto);

// 4. editMessageText
const handleBotEditMessageText = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const { chat_id, message_id, text, reply_markup } = req.body;
  if (!chat_id || !message_id || !text || !String(text).trim()) {
    return res.status(400).json({ ok: false, error_code: 400, description: 'Bad Request: chat_id, message_id, and text are required' });
  }

  const chatId = Number(chat_id);
  const messageId = Number(message_id);

  const existingMsg = database.getMessageById(messageId);
  if (!existingMsg || existingMsg.chat_id !== chatId) {
    return res.status(404).json({ ok: false, error_code: 404, description: 'Message not found' });
  }
  if (existingMsg.sender_id !== bot.id) {
    return res.status(403).json({ ok: false, error_code: 403, description: 'Forbidden: bot can only edit its own messages' });
  }

  const cleanMarkup = reply_markup !== undefined ? sanitizeReplyMarkup(reply_markup) : undefined;
  const updatedMsg = database.editMessage(messageId, String(text).trim(), cleanMarkup);

  const participants = database.getChatParticipantUserIds(chatId);
  const payload = {
    type: 'message_edited',
    message: updatedMsg,
    chatId
  };

  for (const pId of participants) {
    sendToUser(pId, payload);
  }

  return res.json({
    ok: true,
    result: {
      message_id: updatedMsg.id,
      from: {
        id: bot.id,
        is_bot: true,
        first_name: bot.first_name,
        username: bot.username
      },
      chat: {
        id: chatId,
        type: 'private'
      },
      date: Math.floor(new Date(updatedMsg.created_at).getTime() / 1000),
      text: updatedMsg.text,
      reply_markup: updatedMsg.reply_markup || undefined
    }
  });
};

app.post(['/bot:token/editMessageText', '/api/bot:token/editMessageText'], handleBotEditMessageText);

// 5. editMessageReplyMarkup
const handleBotEditMessageReplyMarkup = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const { chat_id, message_id, reply_markup } = req.body;
  if (!chat_id || !message_id) {
    return res.status(400).json({ ok: false, error_code: 400, description: 'Bad Request: chat_id and message_id are required' });
  }

  const chatId = Number(chat_id);
  const messageId = Number(message_id);

  const existingMsg = database.getMessageById(messageId);
  if (!existingMsg || existingMsg.chat_id !== chatId) {
    return res.status(404).json({ ok: false, error_code: 404, description: 'Message not found' });
  }
  if (existingMsg.sender_id !== bot.id) {
    return res.status(403).json({ ok: false, error_code: 403, description: 'Forbidden: bot can only edit its own messages' });
  }

  const cleanMarkup = sanitizeReplyMarkup(reply_markup);
  const updatedMsg = database.editMessageReplyMarkup(messageId, cleanMarkup);

  const participants = database.getChatParticipantUserIds(chatId);
  const payload = {
    type: 'message_edited',
    message: updatedMsg,
    chatId
  };

  for (const pId of participants) {
    sendToUser(pId, payload);
  }

  return res.json({
    ok: true,
    result: {
      message_id: updatedMsg.id,
      from: {
        id: bot.id,
        is_bot: true,
        first_name: bot.first_name,
        username: bot.username
      },
      chat: {
        id: chatId,
        type: 'private'
      },
      date: Math.floor(new Date(updatedMsg.created_at).getTime() / 1000),
      text: updatedMsg.text,
      reply_markup: updatedMsg.reply_markup || undefined
    }
  });
};

app.post(['/bot:token/editMessageReplyMarkup', '/api/bot:token/editMessageReplyMarkup'], handleBotEditMessageReplyMarkup);

// 6. answerCallbackQuery
const handleBotAnswerCallbackQuery = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const { callback_query_id, text, show_alert, url } = req.body;
  if (!callback_query_id) {
    return res.status(400).json({ ok: false, error_code: 400, description: 'Bad Request: callback_query_id is required' });
  }

  const active = activeCallbacks.get(callback_query_id);
  if (active) {
    sendToUser(active.userId, {
      type: 'callback_query_answered',
      callbackQueryId: callback_query_id,
      text: text || '',
      showAlert: Boolean(show_alert),
      url: url || ''
    });
    activeCallbacks.delete(callback_query_id);
  }

  return res.json({ ok: true, result: true });
};

app.post(['/bot:token/answerCallbackQuery', '/api/bot:token/answerCallbackQuery'], handleBotAnswerCallbackQuery);

// 7. deleteMessage
const handleBotDeleteMessage = (req, res) => {
  const token = getCleanToken(req.params.token);
  const bot = database.getBotByToken(token);
  if (!bot) {
    return res.status(401).json({ ok: false, error_code: 401, description: 'Unauthorized: invalid bot token' });
  }

  const { chat_id, message_id } = req.body;
  if (!chat_id || !message_id) {
    return res.status(400).json({ ok: false, error_code: 400, description: 'Bad Request: chat_id and message_id are required' });
  }

  const chatId = Number(chat_id);
  const messageId = Number(message_id);

  const existingMsg = database.getMessageById(messageId);
  if (!existingMsg || existingMsg.chat_id !== chatId) {
    return res.status(404).json({ ok: false, error_code: 404, description: 'Message not found' });
  }
  if (existingMsg.sender_id !== bot.id) {
    return res.status(403).json({ ok: false, error_code: 403, description: 'Forbidden: bot can only delete its own messages' });
  }

  database.deleteMessage(messageId);

  const participants = database.getChatParticipantUserIds(chatId);
  for (const pId of participants) {
    sendToUser(pId, {
      type: 'message_deleted',
      chatId,
      messageId
    });
  }

  return res.json({ ok: true, result: true });
};

app.post(['/bot:token/deleteMessage', '/api/bot:token/deleteMessage'], handleBotDeleteMessage);

// REST endpoint for user triggering inline button callback query
app.post('/api/bot/callback-query', authMiddleware, (req, res) => {
  const { chatId, messageId, data, callbackQueryId } = req.body;
  if (!chatId || !messageId) {
    return res.status(400).json({ error: 'chatId and messageId are required' });
  }
  const cbId = callbackQueryId || `cb_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
  const success = handleCallbackQuery({
    userId: req.user.id,
    chatId: Number(chatId),
    messageId: Number(messageId),
    data: String(data || ''),
    callbackQueryId: cbId
  });
  if (!success) {
    return res.status(400).json({ error: 'Failed to process callback query' });
  }
  return res.json({ success: true, callbackQueryId: cbId });
});

// ================= WEB PUSH NOTIFICATION ROUTES =================
app.get('/api/push/vapid-public-key', (req, res) => {
  return res.json({ ok: true, publicKey: VAPID_PUBLIC_KEY });
});

app.post('/api/push/subscribe', authMiddleware, (req, res) => {
  const { subscription } = req.body;
  if (!subscription || !subscription.endpoint) {
    return res.status(400).json({ error: 'Subscription object with endpoint is required' });
  }
  const saved = database.savePushSubscription(req.user.id, subscription);
  if (!saved) {
    return res.status(400).json({ error: 'Failed to save push subscription' });
  }
  return res.json({ ok: true });
});

app.post('/api/push/unsubscribe', optionalAuthMiddleware, (req, res) => {
  const { endpoint } = req.body;
  if (endpoint) {
    database.deletePushSubscription(endpoint);
  }
  return res.json({ ok: true });
});

app.post('/api/push/test', authMiddleware, async (req, res) => {
  await sendPushNotificationToUser(req.user.id, {
    title: 'Portal Messenger',
    body: 'Уведомления успешно подключены! 🎉',
    icon: '/icons/icon-192.png',
    badge: '/icons/badge-72.png',
    tag: 'portal_test_notification',
    data: { url: '/' }
  });
  return res.json({ ok: true, message: 'Тестовое уведомление отправлено' });
});

// ================= WEBSOCKET SERVER =================
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  let authenticatedUserId = null;

  try {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    if (token) {
      const user = database.getUserByToken(token);
      if (user) {
        authenticatedUserId = user.id;
        handleUserSocketConnect(authenticatedUserId, ws);
        ws.send(JSON.stringify({ type: 'authenticated', userId: user.id }));
      }
    }
  } catch (e) {
    // ignore URL parse errors
  }

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());

      if (msg.type === 'auth') {
        const user = database.getUserByToken(msg.token);
        if (user) {
          authenticatedUserId = user.id;
          handleUserSocketConnect(authenticatedUserId, ws);
          ws.send(JSON.stringify({ type: 'authenticated', userId: user.id }));
        } else {
          ws.send(JSON.stringify({ type: 'error', error: 'Auth failed' }));
        }
        return;
      }

      if (msg.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong' }));
        return;
      }

      if (!authenticatedUserId) {
        ws.send(JSON.stringify({ type: 'error', error: 'Unauthorized WebSocket' }));
        return;
      }

      // Heartbeat / activity touch
      database.updateUserLastSeen(authenticatedUserId);

      if (msg.type === 'send_message') {
        const { chatId, text, replyToMessageId } = msg;
        if (!chatId || !text || !text.trim()) return;

        const sender = database.getUserById(authenticatedUserId);
        if (sender && sender.is_frozen) {
          ws.send(JSON.stringify({ type: 'error', error: 'Ваш аккаунт временно заморожен' }));
          return;
        }

        const channel = database.getChannelByChatId(Number(chatId), authenticatedUserId);
        if (channel) {
          if (channel.owner_id !== authenticatedUserId) {
            ws.send(JSON.stringify({ type: 'error', error: 'Только владелец канала может публиковать сообщения' }));
            return;
          }
        } else {
          const participants = database.getChatParticipantUserIds(Number(chatId));
          if (!participants.includes(authenticatedUserId)) {
            ws.send(JSON.stringify({ type: 'error', error: 'Not a member of this chat' }));
            return;
          }
        }

        try {
          handleOutgoingUserMessage({
            chatId: Number(chatId),
            senderId: authenticatedUserId,
            text: text.trim(),
            replyToMessageId: replyToMessageId ? Number(replyToMessageId) : null
          });
        } catch (err) {
          ws.send(JSON.stringify({ type: 'error', error: err.message }));
        }
      }

      if (msg.type === 'edit_message') {
        const { messageId, text } = msg;
        if (!messageId || !text || !text.trim()) return;
        const existing = database.getMessageById(Number(messageId), authenticatedUserId);
        if (!existing) {
          ws.send(JSON.stringify({ type: 'error', error: 'Сообщение не найдено' }));
          return;
        }
        if (existing.sender_id !== authenticatedUserId) {
          ws.send(JSON.stringify({ type: 'error', error: 'Вы можете редактировать только свои сообщения' }));
          return;
        }
        const updated = database.editMessage(Number(messageId), text.trim());
        const participants = database.getChatParticipantUserIds(Number(updated.chat_id));
        const payload = {
          type: 'message_edited',
          chatId: Number(updated.chat_id),
          message: updated
        };
        for (const pId of participants) {
          sendToUser(pId, payload);
        }
      }

      if (msg.type === 'delete_message') {
        const { messageId, chatId } = msg;
        if (!messageId) return;
        const existing = database.getMessageById(Number(messageId), authenticatedUserId);
        if (!existing) return;
        const targetChatId = Number(chatId || existing.chat_id);
        const channel = database.getChannelByChatId(targetChatId);
        const isAuthor = existing.sender_id === authenticatedUserId;
        const isChannelOwner = channel && channel.owner_id === authenticatedUserId;
        if (!isAuthor && !isChannelOwner) {
          ws.send(JSON.stringify({ type: 'error', error: 'Недостаточно прав для удаления' }));
          return;
        }
        database.deleteMessage(Number(messageId));
        const participants = database.getChatParticipantUserIds(targetChatId);
        const payload = {
          type: 'message_deleted',
          chatId: targetChatId,
          messageId: Number(messageId)
        };
        for (const pId of participants) {
          sendToUser(pId, payload);
        }
      }

      if (msg.type === 'pin_message') {
        const { chatId, messageId } = msg;
        if (!chatId) return;
        const targetChatId = Number(chatId);
        const participants = database.getChatParticipantUserIds(targetChatId);
        if (!participants.includes(authenticatedUserId)) {
          ws.send(JSON.stringify({ type: 'error', error: 'Вы не являетесь участником чата' }));
          return;
        }
        const { pinnedMessage, isPinned } = database.pinMessage(targetChatId, messageId ? Number(messageId) : null);
        const payload = {
          type: 'chat_pinned_message',
          chatId: targetChatId,
          pinnedMessage,
          isPinned,
          pinnedMessageId: isPinned ? Number(messageId) : null
        };
        for (const pId of participants) {
          sendToUser(pId, payload);
        }
      }

      if (msg.type === 'sparks_reaction') {
        const { messageId, amount = 1, isAnonymous = false } = msg;
        if (!messageId) return;
        try {
          const result = database.addPostSparksReaction(Number(messageId), authenticatedUserId, amount, isAnonymous);
          sendToUser(authenticatedUserId, {
            type: 'sparks_updated',
            sparks: result.remainingSparks
          });
          if (result.channelOwnerId && result.channelOwnerId !== authenticatedUserId) {
            const ownerUser = database.getUserById(result.channelOwnerId);
            if (ownerUser) {
              sendToUser(result.channelOwnerId, {
                type: 'sparks_updated',
                sparks: Number(ownerUser.sparks)
              });
            }
          }
          const targetMsg = database.getMessageById(Number(messageId));
          if (targetMsg) {
            const participants = database.getChatParticipantUserIds(Number(targetMsg.chat_id));
            const payload = {
              type: 'post_sparks_updated',
              chatId: Number(targetMsg.chat_id),
              messageId: Number(messageId),
              userId: authenticatedUserId,
              addedAmount: result.addedAmount,
              sparksCount: result.sparksCount,
              leaders: result.leaders
            };
            for (const pId of participants) {
              sendToUser(pId, payload);
            }
          }
        } catch (err) {
          ws.send(JSON.stringify({ type: 'error', error: err.message }));
        }
      }

      if (msg.type === 'toggle_reaction') {
        const { messageId, emoji } = msg;
        if (!messageId || !emoji) return;
        try {
          const numMsgId = Number(messageId);
          const targetMsg = database.getMessageById(numMsgId, authenticatedUserId);
          if (!targetMsg) return;
          const chatId = Number(targetMsg.chat_id);
          const channel = database.getChannelByChatId(chatId);
          const participants = database.getChatParticipantUserIds(chatId);
          if (!channel && !participants.includes(authenticatedUserId)) return;

          const reactions = database.toggleMessageReaction(numMsgId, authenticatedUserId, emoji);
          const payload = {
            type: 'message_reaction_updated',
            chatId,
            messageId: numMsgId,
            reactions
          };
          for (const pId of participants) {
            sendToUser(pId, payload);
          }
          if (!participants.includes(authenticatedUserId)) {
            sendToUser(authenticatedUserId, payload);
          }
        } catch (err) {
          console.error('[WS toggle_reaction] error:', err);
        }
      }

      if (msg.type === 'mark_read') {
        const { chatId } = msg;
        if (!chatId) return;
        const participants = database.getChatParticipantUserIds(Number(chatId));
        if (!participants.includes(authenticatedUserId)) return;

        database.markChatAsRead(Number(chatId), authenticatedUserId);

        for (const pId of participants) {
          if (pId !== authenticatedUserId) {
            sendToUser(pId, {
              type: 'messages_read',
              chatId: Number(chatId),
              readerId: authenticatedUserId
            });
          } else {
            sendToUser(pId, {
              type: 'chat_read',
              chatId: Number(chatId),
              unreadCount: 0
            });
          }
        }
      }

      if (msg.type === 'typing') {
        const { chatId, isTyping } = msg;
        const participants = database.getChatParticipantUserIds(Number(chatId));
        for (const pId of participants) {
          if (pId !== authenticatedUserId) {
            sendToUser(pId, {
              type: 'user_typing',
              chatId: Number(chatId),
              userId: authenticatedUserId,
              isTyping: Boolean(isTyping)
            });
          }
        }
      }
      if (msg.type === 'bot_callback_query') {
        const { chatId, messageId, data, callbackQueryId } = msg;
        if (chatId && messageId) {
          handleCallbackQuery({
            userId: authenticatedUserId,
            chatId: Number(chatId),
            messageId: Number(messageId),
            data: String(data || ''),
            callbackQueryId: callbackQueryId || `cb_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`
          });
        }
      }

      // WebRTC Audio/Video Calls & Screen Sharing Signaling
      if (msg.type === 'call_user') {
        const { targetUserId, callId, isVideo = false } = msg;
        const targetId = Number(targetUserId);
        const caller = database.getUserById(authenticatedUserId);
        if (!caller) return;

        console.log(`[CALL] call_user: from ${authenticatedUserId} (${caller.first_name}) to target ${targetId}, callId: ${callId}`);
        console.log(`[CALL] Connected activeSockets:`, Array.from(activeSockets.entries()).map(([uid, set]) => `ID ${uid} (${set.size} sockets)`).join(', ') || 'none');

        const callerPayload = {
          id: caller.id,
          first_name: caller.first_name,
          last_name: caller.last_name,
          username: caller.username,
          avatar: caller.avatar
        };

        const incomingPayload = {
          type: 'incoming_call',
          callId,
          fromUserId: authenticatedUserId,
          fromUser: callerPayload,
          isVideo: Boolean(isVideo)
        };

        // If calling demo accounts (Pavel Durov ID 5 or BotFather ID 6) without an active browser session, auto-answer for test
        const hasTargetSocket = activeSockets.has(targetId) && activeSockets.get(targetId).size > 0;
        if (!hasTargetSocket && (targetId === 5 || targetId === 6)) {
          console.log(`[CALL] Auto-answering for demo contact ID ${targetId}`);
          setTimeout(() => {
            try {
              ws.send(JSON.stringify({
                type: 'call_accepted',
                callId,
                fromUserId: targetId
              }));
            } catch (_) {}
          }, 2500);
          return;
        }

        if (!hasTargetSocket) {
          console.log(`[CALL] Target user ${targetId} is offline (no active sockets). Online: [${Array.from(activeSockets.keys()).join(', ')}]`);
          sendToUser(authenticatedUserId, {
            type: 'call_ended',
            callId,
            fromUserId: targetId,
            reason: 'offline'
          });
          return;
        }

        // Deliver immediately to target if connected
        const delivered = sendToUser(targetId, incomingPayload);
        console.log(`[CALL] incoming_call delivered to target ${targetId}: ${delivered}`);

        // Set 45-second standard ringing timeout (like real phone / Telegram calls)
        const timeoutId = setTimeout(() => {
          if (activeCalls.has(callId)) {
            console.log(`[CALL] Ringing timeout (45s elapsed) for callId: ${callId}`);
            activeCalls.delete(callId);
            sendToUser(authenticatedUserId, {
              type: 'call_ended',
              callId,
              fromUserId: targetId,
              reason: 'no_answer'
            });
            sendToUser(targetId, {
              type: 'call_ended',
              callId,
              fromUserId: authenticatedUserId,
              reason: 'no_answer'
            });
          }
        }, 45000);

        activeCalls.set(callId, {
          callId,
          callerId: authenticatedUserId,
          targetId,
          timeoutId,
          incomingPayload
        });
      }

      if (msg.type === 'call_accept') {
        const { targetUserId, callId } = msg;
        console.log(`[CALL] call_accept: target ${targetUserId}, callId: ${callId}`);
        const callInfo = activeCalls.get(callId);
        if (callInfo) {
          clearTimeout(callInfo.timeoutId);
          activeCalls.delete(callId);
        }
        sendToUser(Number(targetUserId), {
          type: 'call_accepted',
          callId,
          fromUserId: authenticatedUserId
        });
      }

      if (msg.type === 'call_decline') {
        const { targetUserId, callId, reason = 'declined' } = msg;
        console.log(`[CALL] call_decline: target ${targetUserId}, callId: ${callId}, reason: ${reason}`);
        const callInfo = activeCalls.get(callId);
        if (callInfo) {
          clearTimeout(callInfo.timeoutId);
          activeCalls.delete(callId);
        }
        sendToUser(Number(targetUserId), {
          type: 'call_ended',
          callId,
          fromUserId: authenticatedUserId,
          reason
        });
      }

      if (msg.type === 'call_end') {
        const { targetUserId, callId, reason = 'hangup' } = msg;
        console.log(`[CALL] call_end: target ${targetUserId}, callId: ${callId}, reason: ${reason}`);
        const callInfo = activeCalls.get(callId);
        if (callInfo) {
          clearTimeout(callInfo.timeoutId);
          activeCalls.delete(callId);
        }
        sendToUser(Number(targetUserId), {
          type: 'call_ended',
          callId,
          fromUserId: authenticatedUserId,
          reason
        });
      }

      if (msg.type === 'call_signal') {
        const { targetUserId, callId, signal } = msg;
        sendToUser(Number(targetUserId), {
          type: 'call_signal',
          callId,
          fromUserId: authenticatedUserId,
          signal
        });
      }
    } catch (err) {
      console.error('WS message error:', err);
    }
  });

  const handleDisconnect = () => {
    if (authenticatedUserId) {
      handleUserSocketDisconnect(authenticatedUserId, ws);
      authenticatedUserId = null;
    }
  };

  ws.on('close', handleDisconnect);
  ws.on('error', (err) => {
    console.error('WS client error:', err);
    handleDisconnect();
  });
});

// ==========================================================================
// DOMAIN-AWARE STATIC FRONTEND ROUTING
// - portalmsg.ru / www.portalmsg.ru -> Main Landing Site (site/)
// - web.portalmsg.ru / app.portalmsg.ru -> Web Messenger (dist/)
// ==========================================================================
const distPath = path.join(__dirname, '../dist');
const sitePath = path.join(__dirname, '../site');

function isWebClientRequest(req) {
  const host = (req.headers['x-forwarded-host'] || req.headers.host || req.hostname || '').toLowerCase();
  
  // 1. Explicit web/app subdomain (e.g. web.portalmsg.ru, web.portal.ru, web.localhost)
  if (host.startsWith('web.') || host.startsWith('app.')) {
    return true;
  }
  
  // 2. Query param or explicit /web path override (for testing)
  if (req.query?.app !== undefined || req.query?.web !== undefined || req.path === '/web' || req.path.startsWith('/web/')) {
    return true;
  }
  
  // 3. Root domain or www (e.g. portalmsg.ru, www.portalmsg.ru, portal.ru) -> Main Landing Site
  if (host.includes('portalmsg.ru') || host.includes('portal.ru')) {
    return false;
  }
  
  // 4. Default for localhost: if ?site or /site -> Main Landing Site, else default to Web Messenger
  if (req.query?.site !== undefined || req.path === '/site' || req.path.startsWith('/site/')) {
    return false;
  }
  
  return true;
}

// Domain-aware static asset middleware
app.use((req, res, next) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return next();
  if (
    req.path.startsWith('/api') || 
    req.path.startsWith('/uploads') || 
    req.path.startsWith('/bot') || 
    req.path.startsWith('/ws') || 
    req.path.startsWith('/gifts') || 
    req.path.startsWith('/site')
  ) {
    return next();
  }

  if (isWebClientRequest(req)) {
    if (fs.existsSync(distPath)) {
      return express.static(distPath)(req, res, next);
    }
  } else {
    if (fs.existsSync(sitePath)) {
      return express.static(sitePath)(req, res, next);
    }
  }
  next();
});

// Domain-aware HTML fallback middleware
app.use((req, res, next) => {
  if (req.method !== 'GET') return next();
  if (
    req.path.startsWith('/api') || 
    req.path.startsWith('/uploads') || 
    req.path.startsWith('/bot') || 
    req.path.startsWith('/ws')
  ) {
    return next();
  }

  if (isWebClientRequest(req)) {
    if (fs.existsSync(path.join(distPath, 'index.html'))) {
      return res.sendFile(path.join(distPath, 'index.html'));
    }
  } else {
    if (fs.existsSync(path.join(sitePath, 'index.html'))) {
      return res.sendFile(path.join(sitePath, 'index.html'));
    }
  }
  next();
});

server.listen(PORT, () => {
  console.log(`[PORTAL] Server running on http://localhost:${PORT}`);
  console.log(`[PORTAL] WebSocket server active on ws://localhost:${PORT}/ws`);
  console.log(`[PORTAL] Bot API available at https://api.portalmsg.ru/bot<token>/ (local: http://localhost:${PORT}/bot<token>/)`);
});

// touch 1793875773.396341
