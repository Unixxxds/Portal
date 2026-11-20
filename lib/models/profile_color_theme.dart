import 'package:flutter/material.dart';

class ProfileColorTheme {
  final String id;
  final String name;
  final List<Color> previewColors;
  final List<Color> backgroundGradient;
  final List<double> stops;
  final Color ambientGlow;
  final Color cardColor;
  final Color buttonColor;
  final Color tabColor;
  final Color accentColor;

  const ProfileColorTheme({
    required this.id,
    required this.name,
    required this.previewColors,
    required this.backgroundGradient,
    this.stops = const [0.0, 0.20, 0.42, 0.65, 1.0],
    required this.ambientGlow,
    required this.cardColor,
    required this.buttonColor,
    required this.tabColor,
    required this.accentColor,
  });

  bool get isDuoTone => previewColors.length > 1;

  static const ProfileColorTheme defaultTheme = ProfileColorTheme(
    id: 'default',
    name: 'Графит',
    previewColors: [Color(0xFF758494)],
    backgroundGradient: [
      Color(0xFF313335), // Top graphite
      Color(0xFF27292A), // Below avatar
      Color(0xFF1C1E1D), // Behind buttons
      Color(0xFF141615), // Top of cards
      Color(0xFF0D0F0E), // Deep dark base
    ],
    ambientGlow: Color(0x22FFFFFF),
    cardColor: Color(0xFF222222),
    buttonColor: Color(0xFF262626),
    tabColor: Color(0xFF1E1E1E),
    accentColor: Color(0xFF3B98FF),
  );

  static const List<ProfileColorTheme> allPresets = [
    // --- ROW 1: Single Base Colors ---
    ProfileColorTheme(
      id: 'blue',
      name: 'Синий',
      previewColors: [Color(0xFF2A82E4)],
      backgroundGradient: [
        Color(0xFF1B3855),
        Color(0xFF152C44),
        Color(0xFF102235),
        Color(0xFF0C1927),
        Color(0xFF07101A),
      ],
      ambientGlow: Color(0x352A82E4),
      cardColor: Color(0xFF18314B),
      buttonColor: Color(0xFF1E3C5C),
      tabColor: Color(0xFF122538),
      accentColor: Color(0xFF2A82E4),
    ),
    ProfileColorTheme(
      id: 'green',
      name: 'Зеленый',
      previewColors: [Color(0xFF3DB346)],
      backgroundGradient: [
        Color(0xFF1A3D22),
        Color(0xFF14301B),
        Color(0xFF0F2615),
        Color(0xFF0B1C10),
        Color(0xFF07120A),
      ],
      ambientGlow: Color(0x353DB346),
      cardColor: Color(0xFF16341D),
      buttonColor: Color(0xFF1C4124),
      tabColor: Color(0xFF102615),
      accentColor: Color(0xFF3DB346),
    ),
    ProfileColorTheme(
      id: 'caramel',
      name: 'Янтарный',
      previewColors: [Color(0xFFD6791E)],
      backgroundGradient: [
        Color(0xFF6B3D1B),
        Color(0xFF593316),
        Color(0xFF472811),
        Color(0xFF361E0D),
        Color(0xFF261408),
      ],
      ambientGlow: Color(0x35D6791E),
      cardColor: Color(0xFF563015),
      buttonColor: Color(0xFF683A19),
      tabColor: Color(0xFF40230F),
      accentColor: Color(0xFFD6791E),
    ),
    ProfileColorTheme(
      id: 'coral',
      name: 'Коралловый',
      previewColors: [Color(0xFFE14F44)],
      backgroundGradient: [
        Color(0xFF592320),
        Color(0xFF481C19),
        Color(0xFF381513),
        Color(0xFF2A0F0E),
        Color(0xFF1D0908),
      ],
      ambientGlow: Color(0x35E14F44),
      cardColor: Color(0xFF4A1C19),
      buttonColor: Color(0xFF5A221E),
      tabColor: Color(0xFF361412),
      accentColor: Color(0xFFE14F44),
    ),
    ProfileColorTheme(
      id: 'purple',
      name: 'Фиолетовый',
      previewColors: [Color(0xFF8E52DC)],
      backgroundGradient: [
        Color(0xFF3A2158),
        Color(0xFF2E1A47),
        Color(0xFF241437),
        Color(0xFF1A0E29),
        Color(0xFF12091D),
      ],
      ambientGlow: Color(0x358E52DC),
      cardColor: Color(0xFF311C4C),
      buttonColor: Color(0xFF3C235D),
      tabColor: Color(0xFF25153A),
      accentColor: Color(0xFF8E52DC),
    ),
    ProfileColorTheme(
      id: 'cyan',
      name: 'Морской',
      previewColors: [Color(0xFF2DB3B9)],
      backgroundGradient: [
        Color(0xFF1C434E),
        Color(0xFF16363F),
        Color(0xFF112A32),
        Color(0xFF0D2026),
        Color(0xFF09161B),
      ],
      ambientGlow: Color(0x352DB3B9),
      cardColor: Color(0xFF1C3C46),
      buttonColor: Color(0xFF224A56),
      tabColor: Color(0xFF142C33),
      accentColor: Color(0xFF2DB3B9),
    ),
    ProfileColorTheme(
      id: 'pink',
      name: 'Розовый',
      previewColors: [Color(0xFFCE3E75)],
      backgroundGradient: [
        Color(0xFF541E34),
        Color(0xFF441729),
        Color(0xFF361120),
        Color(0xFF2A0C18),
        Color(0xFF1E0711),
      ],
      ambientGlow: Color(0x35CE3E75),
      cardColor: Color(0xFF46172A),
      buttonColor: Color(0xFF551C33),
      tabColor: Color(0xFF33101E),
      accentColor: Color(0xFFCE3E75),
    ),
    ProfileColorTheme(
      id: 'slate',
      name: 'Графит',
      previewColors: [Color(0xFF708191)],
      backgroundGradient: [
        Color(0xFF313335),
        Color(0xFF27292A),
        Color(0xFF1C1E1D),
        Color(0xFF141615),
        Color(0xFF0D0F0E),
      ],
      ambientGlow: Color(0x22FFFFFF),
      cardColor: Color(0xFF222222),
      buttonColor: Color(0xFF262626),
      tabColor: Color(0xFF1E1E1E),
      accentColor: Color(0xFF708191),
    ),

    // --- ROW 2: Duo-tone Gradients ---
    ProfileColorTheme(
      id: 'duo_blue',
      name: 'Небесный градиент',
      previewColors: [Color(0xFF65B4EE), Color(0xFF1D71BA)],
      backgroundGradient: [
        Color(0xFF1C3C56),
        Color(0xFF162F44),
        Color(0xFF112435),
        Color(0xFF0C1B28),
        Color(0xFF08111A),
      ],
      ambientGlow: Color(0x3565B4EE),
      cardColor: Color(0xFF19354C),
      buttonColor: Color(0xFF1F415E),
      tabColor: Color(0xFF13283A),
      accentColor: Color(0xFF65B4EE),
    ),
    ProfileColorTheme(
      id: 'duo_lime',
      name: 'Лесной градиент',
      previewColors: [Color(0xFF93D254), Color(0xFF368D32)],
      backgroundGradient: [
        Color(0xFF224326),
        Color(0xFF1B361E),
        Color(0xFF152A17),
        Color(0xFF0F1F11),
        Color(0xFF09130A),
      ],
      ambientGlow: Color(0x3593D254),
      cardColor: Color(0xFF1D3B21),
      buttonColor: Color(0xFF244829),
      tabColor: Color(0xFF142B18),
      accentColor: Color(0xFF93D254),
    ),
    ProfileColorTheme(
      id: 'duo_sunset',
      name: 'Закатный градиент',
      previewColors: [Color(0xFFFBB841), Color(0xFFD96716)],
      backgroundGradient: [
        Color(0xFF633816),
        Color(0xFF512D11),
        Color(0xFF40230D),
        Color(0xFF2F1909),
        Color(0xFF1F1005),
      ],
      ambientGlow: Color(0x35FBB841),
      cardColor: Color(0xFF502C12),
      buttonColor: Color(0xFF613516),
      tabColor: Color(0xFF3C210D),
      accentColor: Color(0xFFFBB841),
    ),
    ProfileColorTheme(
      id: 'duo_peach',
      name: 'Персиковый градиент',
      previewColors: [Color(0xFFF9886E), Color(0xFFCE3F2D)],
      backgroundGradient: [
        Color(0xFF58231C),
        Color(0xFF461B16),
        Color(0xFF371511),
        Color(0xFF290E0C),
        Color(0xFF1B0907),
      ],
      ambientGlow: Color(0x35F9886E),
      cardColor: Color(0xFF471C16),
      buttonColor: Color(0xFF57231B),
      tabColor: Color(0xFF351410),
      accentColor: Color(0xFFF9886E),
    ),
    ProfileColorTheme(
      id: 'duo_violet',
      name: 'Неоновый градиент',
      previewColors: [Color(0xFFD86CD8), Color(0xFF7634B8)],
      backgroundGradient: [
        Color(0xFF3F1F50),
        Color(0xFF321841),
        Color(0xFF261232),
        Color(0xFF1C0C25),
        Color(0xFF120718),
      ],
      ambientGlow: Color(0x35D86CD8),
      cardColor: Color(0xFF351A44),
      buttonColor: Color(0xFF422055),
      tabColor: Color(0xFF271333),
      accentColor: Color(0xFFD86CD8),
    ),
    ProfileColorTheme(
      id: 'duo_mint',
      name: 'Мятный градиент',
      previewColors: [Color(0xFF48D5B5), Color(0xFF15939E)],
      backgroundGradient: [
        Color(0xFF194145),
        Color(0xFF133438),
        Color(0xFF0F282C),
        Color(0xFF0A1E21),
        Color(0xFF061416),
      ],
      ambientGlow: Color(0x3548D5B5),
      cardColor: Color(0xFF183B3F),
      buttonColor: Color(0xFF1E494E),
      tabColor: Color(0xFF122C2F),
      accentColor: Color(0xFF48D5B5),
    ),
    ProfileColorTheme(
      id: 'duo_berry',
      name: 'Ягодный градиент',
      previewColors: [Color(0xFFF77685), Color(0xFFC82C5A)],
      backgroundGradient: [
        Color(0xFF511E32),
        Color(0xFF421728),
        Color(0xFF34111F),
        Color(0xFF260B17),
        Color(0xFF19060E),
      ],
      ambientGlow: Color(0x35F77685),
      cardColor: Color(0xFF431829),
      buttonColor: Color(0xFF531E33),
      tabColor: Color(0xFF32111E),
      accentColor: Color(0xFFF77685),
    ),
    ProfileColorTheme(
      id: 'duo_denim',
      name: 'Стальной синий',
      previewColors: [Color(0xFFA0AFB7), Color(0xFF465764)],
      backgroundGradient: [
        Color(0xFF384450),
        Color(0xFF2D3742),
        Color(0xFF232C35),
        Color(0xFF1B222A),
        Color(0xFF131920),
      ],
      ambientGlow: Color(0x35A0AFB7),
      cardColor: Color(0xFF303B46),
      buttonColor: Color(0xFF3A4755),
      tabColor: Color(0xFF242D36),
      accentColor: Color(0xFFA0AFB7),
    ),
  ];

  static ProfileColorTheme fromId(String? id) {
    if (id == null || id.isEmpty || id == 'default') {
      return defaultTheme;
    }
    for (final preset in allPresets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return defaultTheme;
  }
}

