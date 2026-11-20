import '../data/database_helper.dart';
import '../models/chat.dart';
import '../models/user.dart';
import '../models/user_gift.dart';

class CachedUserProfile {
  final User? user;
  final List<UserGift> gifts;
  final Chat? pinnedChannel;
  final DateTime cachedAt;

  const CachedUserProfile({
    this.user,
    this.gifts = const [],
    this.pinnedChannel,
    required this.cachedAt,
  });

  CachedUserProfile copyWith({
    User? user,
    List<UserGift>? gifts,
    Chat? pinnedChannel,
    DateTime? cachedAt,
  }) {
    return CachedUserProfile(
      user: user ?? this.user,
      gifts: gifts ?? this.gifts,
      pinnedChannel: pinnedChannel ?? this.pinnedChannel,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }
}

/// In-memory and persistent cache service for user profiles and gifts.
/// Ensures 0 ms instant opening of previously viewed profiles without frame drops or lag.
class ProfileCacheService {
  ProfileCacheService._();
  static final ProfileCacheService instance = ProfileCacheService._();

  static final Map<int, CachedUserProfile> _cache = {};
  static final Map<String, int> _usernameToId = {};

  /// Instant synchronous memory lookup (0 ms)
  static CachedUserProfile? get(int userId) {
    if (userId <= 0) return null;
    return _cache[userId];
  }

  static User? getUser(int userId) => get(userId)?.user;
  static List<UserGift>? getGifts(int userId) => get(userId)?.gifts;
  static Chat? getPinnedChannel(int userId) => get(userId)?.pinnedChannel;

  /// Find userId by username
  static int? getIdForUsername(String username) {
    final clean = username.replaceFirst(RegExp(r'^@+'), '').trim().toLowerCase();
    return _usernameToId[clean];
  }

  /// Update memory cache and write through to SQLite in background
  static void set(
    int userId, {
    User? user,
    List<UserGift>? gifts,
    Chat? pinnedChannel,
  }) {
    if (userId <= 0) return;
    final existing = _cache[userId];
    final updated = CachedUserProfile(
      user: user ?? existing?.user,
      gifts: gifts ?? existing?.gifts ?? const [],
      pinnedChannel: pinnedChannel ?? existing?.pinnedChannel,
      cachedAt: DateTime.now(),
    );
    _cache[userId] = updated;

    // Index username for reverse lookup
    final u = updated.user?.username;
    if (u != null && u.isNotEmpty) {
      final clean = u.replaceFirst(RegExp(r'^@+'), '').trim().toLowerCase();
      _usernameToId[clean] = userId;
    }
  }

  /// Update a single gift in cache (e.g. after upgrade)
  static void updateGift(int userId, UserGift upgradedGift) {
    if (userId <= 0) return;
    final cached = _cache[userId];
    if (cached == null) return;
    final list = List<UserGift>.from(cached.gifts);
    final idx = list.indexWhere((g) => g.id == upgradedGift.id);
    if (idx != -1) {
      list[idx] = upgradedGift;
      set(userId, gifts: list);
    }
  }

  /// Prepend a newly sent gift to recipient's cache
  static void addGift(int userId, UserGift newGift) {
    if (userId <= 0) return;
    final cached = _cache[userId];
    final list = cached != null ? List<UserGift>.from(cached.gifts) : <UserGift>[];
    // Avoid duplicate
    final existingIdx = list.indexWhere((g) => g.id == newGift.id);
    if (existingIdx != -1) {
      list[existingIdx] = newGift;
    } else {
      list.insert(0, newGift);
    }
    set(userId, gifts: list);
  }

  /// Preload from SQLite into memory cache if not present
  static Future<CachedUserProfile?> preloadFromDb(int userId) async {
    if (userId <= 0) return null;
    final mem = get(userId);
    if (mem != null && mem.user != null && mem.gifts.isNotEmpty) {
      return mem;
    }

    User? dbUser = mem?.user;
    List<UserGift> dbGifts = mem?.gifts ?? [];

    try {
      dbUser ??= await DatabaseHelper.instance.getUser(userId);
      if (dbGifts.isEmpty) {
        dbGifts = await DatabaseHelper.instance.getUserGifts(userId);
      }
    } catch (_) {}

    if (dbUser != null || dbGifts.isNotEmpty) {
      set(userId, user: dbUser, gifts: dbGifts);
      return get(userId);
    }
    return null;
  }

  /// Fast comparison to prevent unnecessary Flutter setState() re-renders
  static bool areGiftsEqual(List<UserGift> a, List<UserGift> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ga = a[i];
      final gb = b[i];
      if (ga.id != gb.id ||
          ga.isUpgraded != gb.isUpgraded ||
          ga.modelFile != gb.modelFile ||
          ga.backdropName != gb.backdropName ||
          ga.patternName != gb.patternName ||
          ga.nftNumber != gb.nftNumber) {
        return false;
      }
    }
    return true;
  }

  /// Fast user comparison
  static bool areUsersEqual(User? a, User? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.id == b.id &&
        a.username == b.username &&
        a.displayName == b.displayName &&
        a.avatar == b.avatar &&
        a.description == b.description &&
        a.isPremium == b.isPremium &&
        a.effectiveVerification == b.effectiveVerification &&
        a.isOnline == b.isOnline &&
        a.lastSeen == b.lastSeen &&
        a.pinnedChannelId == b.pinnedChannelId;
  }
}
