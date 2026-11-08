class UserGift {
  final int id;
  final int userId;
  final String giftId;
  final String giftName;
  final String modelName;
  final String modelFile;
  final String backdropName;
  final String backdropGradient;
  final String patternName;
  final String patternSvg;
  final int nftNumber;
  final int senderId;
  final String senderFirstName;
  final String senderLastName;
  final String senderUsername;
  final String senderAvatar;
  final int recipientId;
  final String recipientFirstName;
  final String recipientLastName;
  final String recipientUsername;
  final String recipientAvatar;
  final String createdAt;
  final bool isUpgraded;
  final bool isPinned;
  final bool isHidden;
  final String? comment;

  UserGift({
    required this.id,
    required this.userId,
    required this.giftId,
    required this.giftName,
    required this.modelName,
    required this.modelFile,
    this.backdropName = '',
    this.backdropGradient = '',
    this.patternName = '',
    this.patternSvg = '',
    this.nftNumber = 0,
    this.senderId = 0,
    this.senderFirstName = '',
    this.senderLastName = '',
    this.senderUsername = '',
    this.senderAvatar = '',
    this.recipientId = 0,
    this.recipientFirstName = '',
    this.recipientLastName = '',
    this.recipientUsername = '',
    this.recipientAvatar = '',
    this.createdAt = '',
    this.isUpgraded = false,
    this.isPinned = false,
    this.isHidden = false,
    this.comment,
  });

  String get senderDisplayName {
    if (senderFirstName.isNotEmpty) {
      return '$senderFirstName $senderLastName'.trim();
    }
    if (senderUsername.isNotEmpty) {
      return senderUsername.startsWith('@')
          ? senderUsername
          : '@$senderUsername';
    }
    return 'Пользователь';
  }

  String get ownerDisplayName {
    if (recipientFirstName.isNotEmpty || recipientLastName.isNotEmpty) {
      return '$recipientFirstName $recipientLastName'.trim();
    }
    if (recipientUsername.isNotEmpty) {
      return recipientUsername.startsWith('@')
          ? recipientUsername
          : '@$recipientUsername';
    }
    return 'Пользователь';
  }

  String get ownerAvatar => recipientAvatar;

  bool get isImage =>
      modelFile.toLowerCase().endsWith('.png') ||
      modelFile.toLowerCase().endsWith('.jpg') ||
      modelFile.toLowerCase().endsWith('.webp');

  String get assetPath {
    final clean = modelFile.replaceAll('\\', '/').trim();
    if (clean.startsWith('lib/assets/gifts/')) return clean;
    if (clean.startsWith('assets/gifts/')) return 'lib/$clean';

    final fileName = clean.split('/').last.trim();
    final lower = fileName.toLowerCase();

    const allFiles = [
      'lib/assets/gifts/cars/bmw-model-m4.png',
      'lib/assets/gifts/cars/lada-model-priora.png',
      'lib/assets/gifts/cars/mercedes-model-gle.png',
      'lib/assets/gifts/cars/tesla-model-roadster.png',
      'lib/assets/gifts/gargona/bluemeggera.json',
      'lib/assets/gifts/gargona/Chrome-Gorgon.json',
      'lib/assets/gifts/gargona/Cleopatra Gargonna.json',
      'lib/assets/gifts/gargona/Cleopatra-Gargonna.json',
      'lib/assets/gifts/gargona/CuteGorgona.json',
      'lib/assets/gifts/gargona/discogargona.json',
      'lib/assets/gifts/gargona/extraterrestrial.json',
      'lib/assets/gifts/gargona/field-gorgonna.json',
      'lib/assets/gifts/gargona/Gorgon-Knight.json',
      'lib/assets/gifts/gargona/Hand-drawn Gorgon.json',
      'lib/assets/gifts/gargona/Hand-drawn-Gorgon.json',
      'lib/assets/gifts/gargona/hellish-gorgon.json',
      'lib/assets/gifts/gargona/Khitayategargona.json',
      'lib/assets/gifts/gargona/pepe-gargona.json',
      'lib/assets/gifts/gargona/Queen-Gorgona.json',
      'lib/assets/gifts/gargona/The-Gazeo-of-Eternity.json',
      'lib/assets/gifts/gargona/Turtle-Gorgon.json',
      'lib/assets/gifts/gargona/wolf-gargonna.json',
      'lib/assets/gifts/girl/###girl.json',
      'lib/assets/gifts/girl/animegirl.json',
      'lib/assets/gifts/girl/coolgilrl.json',
      'lib/assets/gifts/girl/darkcat.json',
      'lib/assets/gifts/girl/girldepravity.json',
      'lib/assets/gifts/girl/Japanesegirl.json',
      'lib/assets/gifts/girl/KIM5splusom.json',
      'lib/assets/gifts/girl/Ladybuggirl.json',
      'lib/assets/gifts/girl/nursegirl.json',
      'lib/assets/gifts/girl/Rapunzelgirl.json',
      'lib/assets/gifts/girl/schoolgirl.json',
      'lib/assets/gifts/girl/Screamgirl.json',
      'lib/assets/gifts/girl/secretgirl.json',
      'lib/assets/gifts/girl/webcamgirl.json',
      'lib/assets/gifts/theel/antiquity.json',
      'lib/assets/gifts/theel/Bumblebee.json',
      'lib/assets/gifts/theel/cola.json',
      'lib/assets/gifts/theel/column.json',
      'lib/assets/gifts/theel/Compressed-frame.json',
      'lib/assets/gifts/theel/condom.json',
      'lib/assets/gifts/theel/cookie.json',
      'lib/assets/gifts/theel/dino.json',
      'lib/assets/gifts/theel/droid.json',
      'lib/assets/gifts/theel/fiery.json',
      'lib/assets/gifts/theel/plate.json',
      'lib/assets/gifts/theel/projector.json',
      'lib/assets/gifts/theel/Sonic.json',
      'lib/assets/gifts/theel/web.json',
      'lib/assets/gifts/theel/Yin-Yang.json',
    ];

    for (final path in allFiles) {
      final base = path.split('/').last.toLowerCase();
      if (base == lower ||
          lower.contains(base.replaceAll('.json', '').replaceAll('.png', ''))) {
        return path;
      }
    }

    if (lower.contains('bmw') || lower.contains('m4'))
      return 'lib/assets/gifts/cars/bmw-model-m4.png';
    if (lower.contains('priora') || lower.contains('lada'))
      return 'lib/assets/gifts/cars/lada-model-priora.png';
    if (lower.contains('gle') || lower.contains('mercedes'))
      return 'lib/assets/gifts/cars/mercedes-model-gle.png';
    if (lower.contains('tesla'))
      return 'lib/assets/gifts/cars/tesla-model-roadster.png';
    if (lower.contains('condom') ||
        lower.contains('balloon') ||
        giftName.toLowerCase().contains('balloon')) {
      return 'lib/assets/gifts/theel/condom.json';
    }

    return 'lib/assets/gifts/theel/condom.json';
  }

  factory UserGift.fromJson(Map<String, dynamic> json, {int? fallbackUserId}) {
    final giftNum = json['nft_number'] is int
        ? json['nft_number'] as int
        : int.tryParse(json['nft_number']?.toString() ?? '') ??
            (json['nftNumber'] is int
                ? json['nftNumber'] as int
                : int.tryParse(json['nftNumber']?.toString() ?? '') ??
                    (json['gift_num'] is int
                        ? json['gift_num'] as int
                        : int.tryParse(json['gift_num']?.toString() ?? '') ??
                            0));

    final parsedId = json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '') ??
            (json['user_gift_id'] is int
                ? json['user_gift_id'] as int
                : int.tryParse(json['user_gift_id']?.toString() ?? '') ??
                    (json['userGiftId'] is int
                        ? json['userGiftId'] as int
                        : int.tryParse(json['userGiftId']?.toString() ?? '') ??
                            (json['gift_id'] is int
                                ? json['gift_id'] as int
                                : int.tryParse(
                                        json['gift_id']?.toString() ?? '') ??
                                    (json['gift_db_id'] is int
                                        ? json['gift_db_id'] as int
                                        : int.tryParse(json['gift_db_id']
                                                    ?.toString() ??
                                                '') ??
                                            0))));

    // If id is 0 but we have nftNumber, use nftNumber as fallback ID so it is unique
    final finalId = parsedId > 0 ? parsedId : giftNum;

    int parsedUserId =
        (fallbackUserId != null && fallbackUserId > 0) ? fallbackUserId : 0;
    if (parsedUserId == 0) {
      if (json['recipient_id'] != null) {
        parsedUserId = int.tryParse(json['recipient_id'].toString()) ?? 0;
      } else if (json['recipientId'] != null) {
        parsedUserId = int.tryParse(json['recipientId'].toString()) ?? 0;
      } else if (json['user_id'] != null) {
        parsedUserId = int.tryParse(json['user_id'].toString()) ?? 0;
      } else if (json['userId'] != null) {
        parsedUserId = int.tryParse(json['userId'].toString()) ?? 0;
      }
    }

    final bName = json['backdrop_name']?.toString() ??
        json['backdropName']?.toString() ??
        json['backdrop']?.toString() ??
        json['bg_name']?.toString() ??
        '';

    final bGrad = json['backdrop_gradient']?.toString() ??
        json['backdropGradient']?.toString() ??
        json['gradient']?.toString() ??
        json['backdrop_bg']?.toString() ??
        json['bg_gradient']?.toString() ??
        '';

    final pName = json['pattern_name']?.toString() ??
        json['patternName']?.toString() ??
        json['pattern']?.toString() ??
        '';

    final pSvg = json['pattern_svg']?.toString() ??
        json['patternSvg']?.toString() ??
        json['svg']?.toString() ??
        '';

    final mFile = json['model_file']?.toString() ??
        json['modelFile']?.toString() ??
        json['gift_file']?.toString() ??
        json['giftFile']?.toString() ??
        json['file']?.toString() ??
        '';

    final gName = json['gift_name']?.toString() ??
        json['giftName']?.toString() ??
        json['name']?.toString() ??
        json['title']?.toString() ??
        'Подарок';

    final mName = json['model_name']?.toString() ??
        json['modelName']?.toString() ??
        gName;

    final sId = json['sender_id'] is int
        ? json['sender_id'] as int
        : int.tryParse(json['sender_id']?.toString() ?? '') ??
            (json['senderId'] is int
                ? json['senderId'] as int
                : int.tryParse(json['senderId']?.toString() ?? '0') ?? 0);

    final sFirst = json['sender_first_name']?.toString() ??
        json['senderFirstName']?.toString() ??
        json['sender_name']?.toString() ??
        json['senderName']?.toString() ??
        '';

    final sLast = json['sender_last_name']?.toString() ??
        json['senderLastName']?.toString() ??
        '';
    final sUser = json['sender_username']?.toString() ??
        json['senderUsername']?.toString() ??
        '';
    final sAvatar = json['sender_avatar']?.toString() ??
        json['senderAvatar']?.toString() ??
        '';

    final rId = parsedUserId > 0
        ? parsedUserId
        : (json['recipient_id'] is int
            ? json['recipient_id'] as int
            : int.tryParse(json['recipient_id']?.toString() ?? '') ??
                (json['recipientId'] is int
                    ? json['recipientId'] as int
                    : int.tryParse(json['recipientId']?.toString() ?? '') ?? 0));

    final rFirst = json['recipient_first_name']?.toString() ??
        json['recipientFirstName']?.toString() ??
        json['recipient_name']?.toString() ??
        json['recipientName']?.toString() ??
        '';

    final rLast = json['recipient_last_name']?.toString() ??
        json['recipientLastName']?.toString() ??
        '';

    final rUser = json['recipient_username']?.toString() ??
        json['recipientUsername']?.toString() ??
        '';

    final rAvatar = json['recipient_avatar']?.toString() ??
        json['recipientAvatar']?.toString() ??
        '';

    final created = json['created_at']?.toString() ??
        json['createdAt']?.toString() ??
        json['date']?.toString() ??
        '';

    final isUp = json['is_upgraded'] == 1 ||
        json['is_upgraded'] == true ||
        json['isUpgraded'] == 1 ||
        json['isUpgraded'] == true ||
        giftNum > 0 ||
        bGrad.isNotEmpty ||
        bName.isNotEmpty;

    final isPin = json['is_pinned'] == 1 ||
        json['is_pinned'] == true ||
        json['isPinned'] == 1 ||
        json['isPinned'] == true;
    final isHid = json['is_hidden'] == 1 ||
        json['is_hidden'] == true ||
        json['isHidden'] == 1 ||
        json['isHidden'] == true;

    return UserGift(
      id: finalId,
      userId: parsedUserId,
      giftId: json['gift_id']?.toString() ??
          json['giftId']?.toString() ??
          json['slug']?.toString() ??
          'gift',
      giftName: gName,
      modelName: mName,
      modelFile: mFile,
      backdropName: bName,
      backdropGradient: bGrad,
      patternName: pName,
      patternSvg: pSvg,
      nftNumber: giftNum,
      senderId: sId,
      senderFirstName: sFirst,
      senderLastName: sLast,
      senderUsername: sUser,
      senderAvatar: sAvatar,
      recipientId: rId,
      recipientFirstName: rFirst,
      recipientLastName: rLast,
      recipientUsername: rUser,
      recipientAvatar: rAvatar,
      createdAt: created,
      isUpgraded: isUp,
      isPinned: isPin,
      isHidden: isHid,
      comment: json['comment']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'user_id': userId,
      'gift_id': giftId,
      'gift_name': giftName,
      'model_name': modelName,
      'model_file': modelFile,
      'backdrop_name': backdropName,
      'backdrop_gradient': backdropGradient,
      'pattern_name': patternName,
      'pattern_svg': patternSvg,
      'nft_number': nftNumber,
      'sender_id': senderId,
      'sender_first_name': senderFirstName,
      'sender_last_name': senderLastName,
      'sender_username': senderUsername,
      'sender_avatar': senderAvatar,
      'created_at': createdAt,
      'is_upgraded': isUpgraded ? 1 : 0,
      'is_pinned': isPinned ? 1 : 0,
      'is_hidden': isHidden ? 1 : 0,
      'comment': comment ?? '',
    };
    if (id > 0) {
      map['id'] = id;
    }
    return map;
  }

  factory UserGift.fromMap(Map<String, dynamic> map) {
    return UserGift(
      id: map['id'] as int? ?? 0,
      userId: map['user_id'] as int? ?? 0,
      giftId: map['gift_id']?.toString() ?? '',
      giftName: map['gift_name']?.toString() ?? 'Подарок',
      modelName: map['model_name']?.toString() ?? 'Подарок',
      modelFile: map['model_file']?.toString() ?? '',
      backdropName: map['backdrop_name']?.toString() ?? '',
      backdropGradient: map['backdrop_gradient']?.toString() ?? '',
      patternName: map['pattern_name']?.toString() ?? '',
      patternSvg: map['pattern_svg']?.toString() ?? '',
      nftNumber: map['nft_number'] as int? ?? 0,
      senderId: map['sender_id'] as int? ?? 0,
      senderFirstName: map['sender_first_name']?.toString() ?? '',
      senderLastName: map['sender_last_name']?.toString() ?? '',
      senderUsername: map['sender_username']?.toString() ?? '',
      senderAvatar: map['sender_avatar']?.toString() ?? '',
      recipientId: map['recipient_id'] as int? ?? (map['user_id'] as int? ?? 0),
      recipientFirstName: map['recipient_first_name']?.toString() ?? '',
      recipientLastName: map['recipient_last_name']?.toString() ?? '',
      recipientUsername: map['recipient_username']?.toString() ?? '',
      recipientAvatar: map['recipient_avatar']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? '',
      isUpgraded: (map['is_upgraded'] as int? ?? 0) == 1,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isHidden: (map['is_hidden'] as int? ?? 0) == 1,
      comment: map['comment']?.toString(),
    );
  }

  UserGift copyWith({
    int? id,
    int? userId,
    String? giftId,
    String? giftName,
    String? modelName,
    String? modelFile,
    String? backdropName,
    String? backdropGradient,
    String? patternName,
    String? patternSvg,
    int? nftNumber,
    int? senderId,
    String? senderFirstName,
    String? senderLastName,
    String? senderUsername,
    String? senderAvatar,
    int? recipientId,
    String? recipientFirstName,
    String? recipientLastName,
    String? recipientUsername,
    String? recipientAvatar,
    String? createdAt,
    bool? isUpgraded,
    bool? isPinned,
    bool? isHidden,
    String? comment,
  }) {
    return UserGift(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      giftId: giftId ?? this.giftId,
      giftName: giftName ?? this.giftName,
      modelName: modelName ?? this.modelName,
      modelFile: modelFile ?? this.modelFile,
      backdropName: backdropName ?? this.backdropName,
      backdropGradient: backdropGradient ?? this.backdropGradient,
      patternName: patternName ?? this.patternName,
      patternSvg: patternSvg ?? this.patternSvg,
      nftNumber: nftNumber ?? this.nftNumber,
      senderId: senderId ?? this.senderId,
      senderFirstName: senderFirstName ?? this.senderFirstName,
      senderLastName: senderLastName ?? this.senderLastName,
      senderUsername: senderUsername ?? this.senderUsername,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      recipientId: recipientId ?? this.recipientId,
      recipientFirstName: recipientFirstName ?? this.recipientFirstName,
      recipientLastName: recipientLastName ?? this.recipientLastName,
      recipientUsername: recipientUsername ?? this.recipientUsername,
      recipientAvatar: recipientAvatar ?? this.recipientAvatar,
      createdAt: createdAt ?? this.createdAt,
      isUpgraded: isUpgraded ?? this.isUpgraded,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
      comment: comment ?? this.comment,
    );
  }
}
