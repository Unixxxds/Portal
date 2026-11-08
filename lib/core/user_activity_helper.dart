class UserActivityHelper {
  static String formatActivity({
    required bool isOnline,
    String? lastSeen,
    bool isBot = false,
    bool isChannel = false,
  }) {
    if (isChannel) return 'канал';
    if (isBot) return 'бот';
    if (isOnline) return 'в сети';
    if (lastSeen == null || lastSeen.trim().isEmpty) {
      return 'был(а) недавно';
    }

    try {
      final d = _safeParseDate(lastSeen);
      final now = DateTime.now();
      final diff = now.difference(d);

      if (diff.isNegative || diff.inSeconds < 60) {
        return 'был(а) только что';
      }

      final diffMin = diff.inMinutes;
      if (diffMin < 60) {
        return 'был(а) в сети ${_formatMinutesAgo(diffMin)}';
      }

      final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
      final hoursStr = d.hour.toString().padLeft(2, '0');
      final minsStr = d.minute.toString().padLeft(2, '0');
      final timeStr = '$hoursStr:$minsStr';

      if (isToday) {
        return 'был(а) в сети сегодня в $timeStr';
      }

      final yesterday = now.subtract(const Duration(days: 1));
      final isYesterday = d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
      if (isYesterday) {
        return 'был(а) в сети вчера в $timeStr';
      }

      const months = [
        'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
        'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
      ];
      final dateStr = '${d.day} ${months[d.month - 1]}';

      if (d.year == now.year) {
        return 'был(а) в сети $dateStr в $timeStr';
      }

      return 'был(а) в сети $dateStr ${d.year} г.';
    } catch (_) {
      return 'был(а) недавно';
    }
  }

  static String _formatMinutesAgo(int minutes) {
    final mod10 = minutes % 10;
    final mod100 = minutes % 100;
    if (mod100 >= 11 && mod100 <= 19) return '$minutes минут назад';
    if (mod10 == 1) return '$minutes минуту назад';
    if (mod10 >= 2 && mod10 <= 4) return '$minutes минуты назад';
    return '$minutes минут назад';
  }

  static String formatSubscribers(int count) {
    final n = count.abs();
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 19) return '$n подписчиков';
    if (mod10 == 1) return '$n подписчик';
    if (mod10 >= 2 && mod10 <= 4) return '$n подписчика';
    return '$n подписчиков';
  }

  static DateTime _safeParseDate(String dateInput) {
    var s = dateInput.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}').hasMatch(s)) {
      s = '${s.replaceFirst(' ', 'T')}Z';
    } else if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(s)) {
      s = '${s}Z';
    }
    return DateTime.parse(s).toLocal();
  }
}

