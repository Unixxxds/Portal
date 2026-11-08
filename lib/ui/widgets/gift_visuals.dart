import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../models/user_gift.dart';

class BackdropOption {
  final String name;
  final String rarity;
  final List<Color> colors;
  final String gradient;

  const BackdropOption({
    required this.name,
    required this.rarity,
    required this.colors,
    required this.gradient,
  });
}

class GiftModelOption {
  final String name;
  final String file;
  final String rarity;

  const GiftModelOption({
    required this.name,
    required this.file,
    required this.rarity,
  });

  bool get isImage =>
      file.toLowerCase().endsWith('.png') ||
      file.toLowerCase().endsWith('.jpg') ||
      file.toLowerCase().endsWith('.webp');

  String get assetPath {
    final clean = file.replaceAll('\\', '/').trim();
    if (clean.startsWith('lib/assets/gifts/')) return clean;
    if (clean.startsWith('assets/gifts/')) return 'lib/$clean';
    if (clean.startsWith('/gifts/')) return 'lib/assets$clean';
    return 'lib/assets/gifts/$clean';
  }
}

class GiftVisuals {
  /// Authentic Telegram NFT Gift Backdrops with exact official color stops (80 backdrops)
  static const Map<String, List<Color>> officialBackdropColors = {
    'amber': [Color(0xFFD9B245), Color(0xFFBC8E31)],
    'aquamarine': [Color(0xFF60B196), Color(0xFF4CACAC)],
    'azure blue': [Color(0xFF5CB0CA), Color(0xFF4B96B4)],
    'battleship grey': [Color(0xFF8B8B84), Color(0xFF75756E)],
    'black': [Color(0xFF353637), Color(0xFF000000)],
    'burgundy': [Color(0xFFA15D65), Color(0xFF7E4A53)],
    'burnt sienna': [Color(0xFFD66F3C), Color(0xFFBF5030)],
    'camo green': [Color(0xFF74934C), Color(0xFF5E7C45)],
    'cappuccino': [Color(0xFFB1907E), Color(0xFF8C7162)],
    'caramel': [Color(0xFFCF9832), Color(0xFFBE7F31)],
    'carmine': [Color(0xFFDF574A), Color(0xFFB94240)],
    'carrot juice': [Color(0xFFDA9666), Color(0xFFCC7B55)],
    'celtic blue': [Color(0xFF45B7ED), Color(0xFF3B93DF)],
    'chestnut': [Color(0xFFBD6E53), Color(0xFFA35440)],
    'chocolate': [Color(0xFFA36D58), Color(0xFF825144)],
    'cobalt blue': [Color(0xFF6087CE), Color(0xFF566DBF)],
    'copper': [Color(0xFFCF8656), Color(0xFFAB6E3B)],
    'coral red': [Color(0xFFD9886A), Color(0xFFCA6F57)],
    'cyberpunk': [Color(0xFF858DF2), Color(0xFF866DDC)],
    'dark lilac': [Color(0xFFB07CA4), Color(0xFF976285)],
    'dark green': [Color(0xFF506341), Color(0xFF354D34)],
    'deep cyan': [Color(0xFF30B4A9), Color(0xFF209E9E)],
    'desert sand': [Color(0xFFB29E81), Color(0xFF8E8167)],
    'electric indigo': [Color(0xFFA67FF2), Color(0xFF7169DF)],
    'electric purple': [Color(0xFFC970C7), Color(0xFFA465D0)],
    'emerald': [Color(0xFF77C585), Color(0xFF51AB76)],
    'english violet': [Color(0xFFAF84B9), Color(0xFF92689D)],
    'fandango': [Color(0xFFE189B5), Color(0xFFB66798)],
    'feldgrau': [Color(0xFF889187), Color(0xFF6A756C)],
    'fire engine': [Color(0xFFEF5E4F), Color(0xFFD0434B)],
    'french blue': [Color(0xFF5B9AC3), Color(0xFF427EA5)],
    'french violet': [Color(0xFFC160E6), Color(0xFF9F53DC)],
    'grape': [Color(0xFF9C73C0), Color(0xFF8258A9)],
    'gunmetal': [Color(0xFF4B5C62), Color(0xFF36434B)],
    'gunship green': [Color(0xFF548964), Color(0xFF44715B)],
    'hunter green': [Color(0xFF8DAC77), Color(0xFF5E8E63)],
    'indigo dye': [Color(0xFF537890), Color(0xFF466880)],
    'ivory white': [Color(0xFFBAB6B0), Color(0xFFA8A59E)],
    'jade green': [Color(0xFF54C39B), Color(0xFF43A683)],
    'khaki green': [Color(0xFFABAE6F), Color(0xFF7D8B5D)],
    'lavender': [Color(0xFFB688E3), Color(0xFF9766C8)],
    'lemongrass': [Color(0xFFACB85A), Color(0xFF6F9E4B)],
    'light olive': [Color(0xFFC1AE64), Color(0xFF988C4E)],
    'malachite': [Color(0xFF94B457), Color(0xFF549F54)],
    'marine blue': [Color(0xFF4D679A), Color(0xFF405384)],
    'midnight blue': [Color(0xFF5B6884), Color(0xFF414D65)],
    'mexican pink': [Color(0xFFE26591), Color(0xFFD05182)],
    'mint green': [Color(0xFF7ECB82), Color(0xFF56AB66)],
    'moonstone': [Color(0xFF7DB0B3), Color(0xFF63909A)],
    'mystic pearl': [Color(0xFFD08A6D), Color(0xFFB9666E)],
    'mustard': [Color(0xFFD3970D), Color(0xFFC98111)],
    'navy blue': [Color(0xFF6B9DDC), Color(0xFF627BCE)],
    'neon blue': [Color(0xFF7494F8), Color(0xFF6C71EA)],
    'onyx black': [Color(0xFF4C5153), Color(0xFF393D3F)],
    'old gold': [Color(0xFFB58C38), Color(0xFF9E7229)],
    'orange': [Color(0xFFD0993A), Color(0xFFC67B44)],
    'pacific cyan': [Color(0xFF59BCA6), Color(0xFF459FB5)],
    'pacific green': [Color(0xFF6DC692), Color(0xFF4AA888)],
    'persimmon': [Color(0xFFE6A55A), Color(0xFFCE7A5D)],
    'pine green': [Color(0xFF6AA87C), Color(0xFF4B8574)],
    'pistachio': [Color(0xFF96AF7B), Color(0xFF6A8F5A)],
    'platinum': [Color(0xFFB0ACA5), Color(0xFF95908A)],
    'pure gold': [Color(0xFFCBAA40), Color(0xFFA78936)],
    'ranger green': [Color(0xFF5F7849), Color(0xFF455B40)],
    'rifle green': [Color(0xFF64695C), Color(0xFF535948)],
    'purple': [Color(0xFFAD6BAD), Color(0xFF915191)],
    'raspberry': [Color(0xFFDE7A85), Color(0xFFC36381)],
    'roman silver': [Color(0xFFA3A8B5), Color(0xFF878B96)],
    'rosewood': [Color(0xFFB67976), Color(0xFF90595D)],
    'sapphire': [Color(0xFF58A3C8), Color(0xFF5485C4)],
    'seal brown': [Color(0xFF664D45), Color(0xFF503C34)],
    'satin gold': [Color(0xFFBE9B47), Color(0xFF9A803D)],
    'shamrock green': [Color(0xFF89B062), Color(0xFF639C4E)],
    'silver blue': [Color(0xFF7FA3B7), Color(0xFF69879C)],
    'sky blue': [Color(0xFF58B2C8), Color(0xFF5497C4)],
    'steel grey': [Color(0xFF96A1AB), Color(0xFF72808A)],
    'strawberry': [Color(0xFFDD8D6F), Color(0xFFC36865)],
    'tactical pine': [Color(0xFF43816A), Color(0xFF356C69)],
    'tomato': [Color(0xFFE6783E), Color(0xFFD85B40)],
    'turquoise': [Color(0xFF5DBEB6), Color(0xFF469F9A)],
  };

  /// All 80 official backdrops with rarities and gradients
  static const List<BackdropOption> allBackdropOptions = [
    BackdropOption(name: 'Amber', rarity: '2.5%', colors: [Color(0xFFD9B245), Color(0xFFBC8E31)], gradient: 'radial-gradient(circle, #d9b245 0%, #bc8e31 100%)'),
    BackdropOption(name: 'Aquamarine', rarity: '3.0%', colors: [Color(0xFF60B196), Color(0xFF4CACAC)], gradient: 'radial-gradient(circle, #60b196 0%, #4cacac 100%)'),
    BackdropOption(name: 'Azure Blue', rarity: '2.8%', colors: [Color(0xFF5CB0CA), Color(0xFF4B96B4)], gradient: 'radial-gradient(circle, #5cb0ca 0%, #4b96b4 100%)'),
    BackdropOption(name: 'Battleship Grey', rarity: '4.0%', colors: [Color(0xFF8B8B84), Color(0xFF75756E)], gradient: 'radial-gradient(circle, #8b8b84 0%, #75756e 100%)'),
    BackdropOption(name: 'Black', rarity: '1.5%', colors: [Color(0xFF353637), Color(0xFF000000)], gradient: 'radial-gradient(circle, #353637 0%, #000000 100%)'),
    BackdropOption(name: 'Burgundy', rarity: '3.5%', colors: [Color(0xFFA15D65), Color(0xFF7E4A53)], gradient: 'radial-gradient(circle, #a15d65 0%, #7e4a53 100%)'),
    BackdropOption(name: 'Burnt Sienna', rarity: '3.2%', colors: [Color(0xFFD66F3C), Color(0xFFBF5030)], gradient: 'radial-gradient(circle, #d66f3c 0%, #bf5030 100%)'),
    BackdropOption(name: 'Camo Green', rarity: '4.5%', colors: [Color(0xFF74934C), Color(0xFF5E7C45)], gradient: 'radial-gradient(circle, #74934c 0%, #5e7c45 100%)'),
    BackdropOption(name: 'Cappuccino', rarity: '2.0%', colors: [Color(0xFFB1907E), Color(0xFF8C7162)], gradient: 'radial-gradient(circle, #b1907e 0%, #8c7162 100%)'),
    BackdropOption(name: 'Caramel', rarity: '3.8%', colors: [Color(0xFFCF9832), Color(0xFFBE7F31)], gradient: 'radial-gradient(circle, #cf9832 0%, #be7f31 100%)'),
    BackdropOption(name: 'Carmine', rarity: '3.1%', colors: [Color(0xFFDF574A), Color(0xFFB94240)], gradient: 'radial-gradient(circle, #df574a 0%, #b94240 100%)'),
    BackdropOption(name: 'Carrot Juice', rarity: '2.4%', colors: [Color(0xFFDA9666), Color(0xFFCC7B55)], gradient: 'radial-gradient(circle, #da9666 0%, #cc7b55 100%)'),
    BackdropOption(name: 'Celtic Blue', rarity: '2.9%', colors: [Color(0xFF45B7ED), Color(0xFF3B93DF)], gradient: 'radial-gradient(circle, #45b7ed 0%, #3b93df 100%)'),
    BackdropOption(name: 'Chestnut', rarity: '2.5%', colors: [Color(0xFFBD6E53), Color(0xFFA35440)], gradient: 'radial-gradient(circle, #bd6e53 0%, #a35440 100%)'),
    BackdropOption(name: 'Chocolate', rarity: '2.2%', colors: [Color(0xFFA36D58), Color(0xFF825144)], gradient: 'radial-gradient(circle, #a36d58 0%, #825144 100%)'),
    BackdropOption(name: 'Cobalt Blue', rarity: '2.7%', colors: [Color(0xFF6087CE), Color(0xFF566DBF)], gradient: 'radial-gradient(circle, #6087ce 0%, #566dbf 100%)'),
    BackdropOption(name: 'Copper', rarity: '1.8%', colors: [Color(0xFFCF8656), Color(0xFFAB6E3B)], gradient: 'radial-gradient(circle, #cf8656 0%, #ab6e3b 100%)'),
    BackdropOption(name: 'Coral Red', rarity: '2.1%', colors: [Color(0xFFD9886A), Color(0xFFCA6F57)], gradient: 'radial-gradient(circle, #d9886a 0%, #ca6f57 100%)'),
    BackdropOption(name: 'Cyberpunk', rarity: '1.8%', colors: [Color(0xFF858DF2), Color(0xFF866DDC)], gradient: 'radial-gradient(circle, #858df2 0%, #866ddc 100%)'),
    BackdropOption(name: 'Dark Lilac', rarity: '4.2%', colors: [Color(0xFFB07CA4), Color(0xFF976285)], gradient: 'radial-gradient(circle, #b07ca4 0%, #976285 100%)'),
    BackdropOption(name: 'Dark Green', rarity: '1.9%', colors: [Color(0xFF506341), Color(0xFF354D34)], gradient: 'radial-gradient(circle, #506341 0%, #354d34 100%)'),
    BackdropOption(name: 'Deep Cyan', rarity: '3.3%', colors: [Color(0xFF30B4A9), Color(0xFF209E9E)], gradient: 'radial-gradient(circle, #30b4a9 0%, #209e9e 100%)'),
    BackdropOption(name: 'Desert Sand', rarity: '2.0%', colors: [Color(0xFFB29E81), Color(0xFF8E8167)], gradient: 'radial-gradient(circle, #b29e81 0%, #8e8167 100%)'),
    BackdropOption(name: 'Electric Indigo', rarity: '1.4%', colors: [Color(0xFFA67FF2), Color(0xFF7169DF)], gradient: 'radial-gradient(circle, #a67ff2 0%, #7169df 100%)'),
    BackdropOption(name: 'Electric Purple', rarity: '1.6%', colors: [Color(0xFFC970C7), Color(0xFFA465D0)], gradient: 'radial-gradient(circle, #c970c7 0%, #a465d0 100%)'),
    BackdropOption(name: 'Emerald', rarity: '2.2%', colors: [Color(0xFF77C585), Color(0xFF51AB76)], gradient: 'radial-gradient(circle, #77c585 0%, #51ab76 100%)'),
    BackdropOption(name: 'English Violet', rarity: '1.7%', colors: [Color(0xFFAF84B9), Color(0xFF92689D)], gradient: 'radial-gradient(circle, #af84b9 0%, #92689d 100%)'),
    BackdropOption(name: 'Fandango', rarity: '1.5%', colors: [Color(0xFFE189B5), Color(0xFFB66798)], gradient: 'radial-gradient(circle, #e189b5 0%, #b66798 100%)'),
    BackdropOption(name: 'Feldgrau', rarity: '2.3%', colors: [Color(0xFF889187), Color(0xFF6A756C)], gradient: 'radial-gradient(circle, #889187 0%, #6a756c 100%)'),
    BackdropOption(name: 'Fire Engine', rarity: '2.0%', colors: [Color(0xFFEF5E4F), Color(0xFFD0434B)], gradient: 'radial-gradient(circle, #ef5e4f 0%, #d0434b 100%)'),
    BackdropOption(name: 'French Blue', rarity: '2.2%', colors: [Color(0xFF5B9AC3), Color(0xFF427EA5)], gradient: 'radial-gradient(circle, #5b9ac3 0%, #427ea5 100%)'),
    BackdropOption(name: 'French Violet', rarity: '1.4%', colors: [Color(0xFFC160E6), Color(0xFF9F53DC)], gradient: 'radial-gradient(circle, #c160e6 0%, #9f53dc 100%)'),
    BackdropOption(name: 'Grape', rarity: '1.8%', colors: [Color(0xFF9C73C0), Color(0xFF8258A9)], gradient: 'radial-gradient(circle, #9c73c0 0%, #8258a9 100%)'),
    BackdropOption(name: 'Gunmetal', rarity: '2.0%', colors: [Color(0xFF4B5C62), Color(0xFF36434B)], gradient: 'radial-gradient(circle, #4b5c62 0%, #36434b 100%)'),
    BackdropOption(name: 'Gunship Green', rarity: '2.2%', colors: [Color(0xFF548964), Color(0xFF44715B)], gradient: 'radial-gradient(circle, #548964 0%, #44715b 100%)'),
    BackdropOption(name: 'Hunter Green', rarity: '2.0%', colors: [Color(0xFF8DAC77), Color(0xFF5E8E63)], gradient: 'radial-gradient(circle, #8dac77 0%, #5e8e63 100%)'),
    BackdropOption(name: 'Indigo Dye', rarity: '2.1%', colors: [Color(0xFF537890), Color(0xFF466880)], gradient: 'radial-gradient(circle, #537890 0%, #466880 100%)'),
    BackdropOption(name: 'Ivory White', rarity: '1.2%', colors: [Color(0xFFBAB6B0), Color(0xFFA8A59E)], gradient: 'radial-gradient(circle, #bab6b0 0%, #a8a59e 100%)'),
    BackdropOption(name: 'Jade Green', rarity: '1.6%', colors: [Color(0xFF54C39B), Color(0xFF43A683)], gradient: 'radial-gradient(circle, #54c39b 0%, #43a683 100%)'),
    BackdropOption(name: 'Khaki Green', rarity: '2.4%', colors: [Color(0xFFABAE6F), Color(0xFF7D8B5D)], gradient: 'radial-gradient(circle, #abae6f 0%, #7d8b5d 100%)'),
    BackdropOption(name: 'Lavender', rarity: '1.5%', colors: [Color(0xFFB688E3), Color(0xFF9766C8)], gradient: 'radial-gradient(circle, #b688e3 0%, #9766c8 100%)'),
    BackdropOption(name: 'Lemongrass', rarity: '2.2%', colors: [Color(0xFFACB85A), Color(0xFF6F9E4B)], gradient: 'radial-gradient(circle, #acb85a 0%, #6f9e4b 100%)'),
    BackdropOption(name: 'Light Olive', rarity: '2.3%', colors: [Color(0xFFC1AE64), Color(0xFF988C4E)], gradient: 'radial-gradient(circle, #c1ae64 0%, #988c4e 100%)'),
    BackdropOption(name: 'Malachite', rarity: '1.9%', colors: [Color(0xFF94B457), Color(0xFF549F54)], gradient: 'radial-gradient(circle, #94b457 0%, #549f54 100%)'),
    BackdropOption(name: 'Marine Blue', rarity: '2.1%', colors: [Color(0xFF4D679A), Color(0xFF405384)], gradient: 'radial-gradient(circle, #4d679a 0%, #405384 100%)'),
    BackdropOption(name: 'Midnight Blue', rarity: '3.0%', colors: [Color(0xFF5B6884), Color(0xFF414D65)], gradient: 'radial-gradient(circle, #5b6884 0%, #414d65 100%)'),
    BackdropOption(name: 'Mexican Pink', rarity: '1.3%', colors: [Color(0xFFE26591), Color(0xFFD05182)], gradient: 'radial-gradient(circle, #e26591 0%, #d05182 100%)'),
    BackdropOption(name: 'Mint Green', rarity: '2.2%', colors: [Color(0xFF7ECB82), Color(0xFF56AB66)], gradient: 'radial-gradient(circle, #7ecb82 0%, #56ab66 100%)'),
    BackdropOption(name: 'Moonstone', rarity: '2.0%', colors: [Color(0xFF7DB0B3), Color(0xFF63909A)], gradient: 'radial-gradient(circle, #7db0b3 0%, #63909a 100%)'),
    BackdropOption(name: 'Mystic Pearl', rarity: '1.6%', colors: [Color(0xFFD08A6D), Color(0xFFB9666E)], gradient: 'radial-gradient(circle, #d08a6d 0%, #b9666e 100%)'),
    BackdropOption(name: 'Mustard', rarity: '2.2%', colors: [Color(0xFFD3970D), Color(0xFFC98111)], gradient: 'radial-gradient(circle, #d3970d 0%, #c98111 100%)'),
    BackdropOption(name: 'Navy Blue', rarity: '2.4%', colors: [Color(0xFF6B9DDC), Color(0xFF627BCE)], gradient: 'radial-gradient(circle, #6b9ddc 0%, #627bce 100%)'),
    BackdropOption(name: 'Neon Blue', rarity: '1.7%', colors: [Color(0xFF7494F8), Color(0xFF6C71EA)], gradient: 'radial-gradient(circle, #7494f8 0%, #6c71ea 100%)'),
    BackdropOption(name: 'Onyx Black', rarity: '1.2%', colors: [Color(0xFF4C5153), Color(0xFF393D3F)], gradient: 'radial-gradient(circle, #4c5153 0%, #393d3f 100%)'),
    BackdropOption(name: 'Old Gold', rarity: '1.5%', colors: [Color(0xFFB58C38), Color(0xFF9E7229)], gradient: 'radial-gradient(circle, #b58c38 0%, #9e7229 100%)'),
    BackdropOption(name: 'Orange', rarity: '2.5%', colors: [Color(0xFFD0993A), Color(0xFFC67B44)], gradient: 'radial-gradient(circle, #d0993a 0%, #c67b44 100%)'),
    BackdropOption(name: 'Pacific Cyan', rarity: '1.8%', colors: [Color(0xFF59BCA6), Color(0xFF459FB5)], gradient: 'radial-gradient(circle, #59bca6 0%, #459fb5 100%)'),
    BackdropOption(name: 'Pacific Green', rarity: '1.9%', colors: [Color(0xFF6DC692), Color(0xFF4AA888)], gradient: 'radial-gradient(circle, #6dc692 0%, #4aa888 100%)'),
    BackdropOption(name: 'Persimmon', rarity: '2.0%', colors: [Color(0xFFE6A55A), Color(0xFFCE7A5D)], gradient: 'radial-gradient(circle, #e6a55a 0%, #ce7a5d 100%)'),
    BackdropOption(name: 'Pine Green', rarity: '2.1%', colors: [Color(0xFF6AA87C), Color(0xFF4B8574)], gradient: 'radial-gradient(circle, #6aa87c 0%, #4b8574 100%)'),
    BackdropOption(name: 'Pistachio', rarity: '2.2%', colors: [Color(0xFF96AF7B), Color(0xFF6A8F5A)], gradient: 'radial-gradient(circle, #96af7b 0%, #6a8f5a 100%)'),
    BackdropOption(name: 'Platinum', rarity: '1.4%', colors: [Color(0xFFB0ACA5), Color(0xFF95908A)], gradient: 'radial-gradient(circle, #b0aca5 0%, #95908a 100%)'),
    BackdropOption(name: 'Pure Gold', rarity: '0.8%', colors: [Color(0xFFCBAA40), Color(0xFFA78936)], gradient: 'radial-gradient(circle, #cbaa40 0%, #a78936 100%)'),
    BackdropOption(name: 'Ranger Green', rarity: '0.7%', colors: [Color(0xFF5F7849), Color(0xFF455B40)], gradient: 'radial-gradient(circle, #5f7849 0%, #455b40 100%)'),
    BackdropOption(name: 'Rifle Green', rarity: '2.3%', colors: [Color(0xFF64695C), Color(0xFF535948)], gradient: 'radial-gradient(circle, #64695c 0%, #535948 100%)'),
    BackdropOption(name: 'Purple', rarity: '3.6%', colors: [Color(0xFFAD6BAD), Color(0xFF915191)], gradient: 'radial-gradient(circle, #ad6bad 0%, #915191 100%)'),
    BackdropOption(name: 'Raspberry', rarity: '1.5%', colors: [Color(0xFFDE7A85), Color(0xFFC36381)], gradient: 'radial-gradient(circle, #de7a85 0%, #c36381 100%)'),
    BackdropOption(name: 'Roman Silver', rarity: '2.0%', colors: [Color(0xFFA3A8B5), Color(0xFF878B96)], gradient: 'radial-gradient(circle, #a3a8b5 0%, #878b96 100%)'),
    BackdropOption(name: 'Rosewood', rarity: '1.8%', colors: [Color(0xFFB67976), Color(0xFF90595D)], gradient: 'radial-gradient(circle, #b67976 0%, #90595d 100%)'),
    BackdropOption(name: 'Sapphire', rarity: '2.4%', colors: [Color(0xFF58A3C8), Color(0xFF5485C4)], gradient: 'radial-gradient(circle, #58a3c8 0%, #5485c4 100%)'),
    BackdropOption(name: 'Seal Brown', rarity: '2.1%', colors: [Color(0xFF664D45), Color(0xFF503C34)], gradient: 'radial-gradient(circle, #664d45 0%, #503c34 100%)'),
    BackdropOption(name: 'Satin Gold', rarity: '1.6%', colors: [Color(0xFFBE9B47), Color(0xFF9A803D)], gradient: 'radial-gradient(circle, #be9b47 0%, #9a803d 100%)'),
    BackdropOption(name: 'Shamrock Green', rarity: '2.0%', colors: [Color(0xFF89B062), Color(0xFF639C4E)], gradient: 'radial-gradient(circle, #89b062 0%, #639c4e 100%)'),
    BackdropOption(name: 'Silver Blue', rarity: '2.1%', colors: [Color(0xFF7FA3B7), Color(0xFF69879C)], gradient: 'radial-gradient(circle, #7fa3b7 0%, #69879c 100%)'),
    BackdropOption(name: 'Sky Blue', rarity: '3.4%', colors: [Color(0xFF58B2C8), Color(0xFF5497C4)], gradient: 'radial-gradient(circle, #58b2c8 0%, #5497c4 100%)'),
    BackdropOption(name: 'Steel Grey', rarity: '2.3%', colors: [Color(0xFF96A1AB), Color(0xFF72808A)], gradient: 'radial-gradient(circle, #96a1ab 0%, #72808a 100%)'),
    BackdropOption(name: 'Strawberry', rarity: '1.6%', colors: [Color(0xFFDD8D6F), Color(0xFFC36865)], gradient: 'radial-gradient(circle, #dd8d6f 0%, #c36865 100%)'),
    BackdropOption(name: 'Tactical Pine', rarity: '2.1%', colors: [Color(0xFF43816A), Color(0xFF356C69)], gradient: 'radial-gradient(circle, #43816a 0%, #356c69 100%)'),
    BackdropOption(name: 'Tomato', rarity: '1.9%', colors: [Color(0xFFE6783E), Color(0xFFD85B40)], gradient: 'radial-gradient(circle, #e6783e 0%, #d85b40 100%)'),
    BackdropOption(name: 'Turquoise', rarity: '2.6%', colors: [Color(0xFF5DBEB6), Color(0xFF469F9A)], gradient: 'radial-gradient(circle, #5dbeb6 0%, #469f9a 100%)'),
  ];

  /// Collections of upgrade models
  static const Map<String, List<GiftModelOption>> giftCollections = {
    'cars': [
      GiftModelOption(name: 'Mercedes-Benz GLE', file: 'lib/assets/gifts/cars/mercedes-model-gle.png', rarity: '30.0%'),
      GiftModelOption(name: 'Tesla Roadster', file: 'lib/assets/gifts/cars/tesla-model-roadster.png', rarity: '25.0%'),
      GiftModelOption(name: 'Lada Priora', file: 'lib/assets/gifts/cars/lada-model-priora.png', rarity: '15.0%'),
      GiftModelOption(name: 'BMW M4 Competition', file: 'lib/assets/gifts/cars/bmw-model-m4.png', rarity: '30.0%'),
    ],
    'girl': [
      GiftModelOption(name: 'Anime Girl', file: 'lib/assets/gifts/girl/animegirl.json', rarity: '14.0%'),
      GiftModelOption(name: 'Secret Girl', file: 'lib/assets/gifts/girl/secretgirl.json', rarity: '0.8%'),
      GiftModelOption(name: 'Cyberpunk Girl', file: 'lib/assets/gifts/girl/girldepravity.json', rarity: '1.1%'),
      GiftModelOption(name: 'Dark Cat Girl', file: 'lib/assets/gifts/girl/darkcat.json', rarity: '2.2%'),
      GiftModelOption(name: 'Gamer Girl', file: 'lib/assets/gifts/girl/webcamgirl.json', rarity: '3.5%'),
      GiftModelOption(name: 'Japanese Girl', file: 'lib/assets/gifts/girl/Japanesegirl.json', rarity: '7.0%'),
      GiftModelOption(name: 'Rapunzel Girl', file: 'lib/assets/gifts/girl/Rapunzelgirl.json', rarity: '5.2%'),
      GiftModelOption(name: 'Scream Girl', file: 'lib/assets/gifts/girl/Screamgirl.json', rarity: '4.0%'),
      GiftModelOption(name: 'Cool Girl', file: 'lib/assets/gifts/girl/coolgilrl.json', rarity: '8.5%'),
      GiftModelOption(name: 'Nurse Girl', file: 'lib/assets/gifts/girl/nursegirl.json', rarity: '6.5%'),
      GiftModelOption(name: 'School Girl', file: 'lib/assets/gifts/girl/schoolgirl.json', rarity: '9.0%'),
      GiftModelOption(name: 'Kim Girl', file: 'lib/assets/gifts/girl/KIM5splusom.json', rarity: '6.0%'),
      GiftModelOption(name: 'Ladybug Girl', file: 'lib/assets/gifts/girl/Ladybuggirl.json', rarity: '8.0%'),
      GiftModelOption(name: 'Neon Girl', file: 'lib/assets/gifts/girl/###girl.json', rarity: '3.5%'),
    ],
    'theel': [
      GiftModelOption(name: 'Bumblebee', file: 'lib/assets/gifts/theel/Bumblebee.json', rarity: '15.0%'),
      GiftModelOption(name: 'Quantum Frame', file: 'lib/assets/gifts/theel/Compressed-frame.json', rarity: '0.7%'),
      GiftModelOption(name: 'Spider Web', file: 'lib/assets/gifts/theel/web.json', rarity: '1.0%'),
      GiftModelOption(name: 'Fiery', file: 'lib/assets/gifts/theel/fiery.json', rarity: '1.5%'),
      GiftModelOption(name: 'Sonic', file: 'lib/assets/gifts/theel/Sonic.json', rarity: '3.0%'),
      GiftModelOption(name: 'Holo Projector', file: 'lib/assets/gifts/theel/projector.json', rarity: '3.8%'),
      GiftModelOption(name: 'Yin-Yang', file: 'lib/assets/gifts/theel/Yin-Yang.json', rarity: '2.2%'),
      GiftModelOption(name: 'Antiquity', file: 'lib/assets/gifts/theel/antiquity.json', rarity: '6.5%'),
      GiftModelOption(name: 'Cola Can', file: 'lib/assets/gifts/theel/cola.json', rarity: '8.0%'),
      GiftModelOption(name: 'Marble Column', file: 'lib/assets/gifts/theel/column.json', rarity: '6.0%'),
      GiftModelOption(name: 'Party Balloon', file: 'lib/assets/gifts/theel/condom.json', rarity: '4.5%'),
      GiftModelOption(name: 'Fortune Cookie', file: 'lib/assets/gifts/theel/cookie.json', rarity: '7.5%'),
      GiftModelOption(name: 'Dino', file: 'lib/assets/gifts/theel/dino.json', rarity: '5.8%'),
      GiftModelOption(name: 'Droid', file: 'lib/assets/gifts/theel/droid.json', rarity: '5.0%'),
      GiftModelOption(name: 'Golden Plate', file: 'lib/assets/gifts/theel/plate.json', rarity: '8.5%'),
    ],
    'gargona': [
      GiftModelOption(name: 'Chrome Gorgon', file: 'lib/assets/gifts/gargona/Chrome-Gorgon.json', rarity: '12.0%'),
      GiftModelOption(name: 'Queen Gorgon', file: 'lib/assets/gifts/gargona/Queen-Gorgona.json', rarity: '0.9%'),
      GiftModelOption(name: 'Gorgon Knight', file: 'lib/assets/gifts/gargona/Gorgon-Knight.json', rarity: '4.5%'),
      GiftModelOption(name: 'Cleopatra Gorgon', file: 'lib/assets/gifts/gargona/Cleopatra-Gargonna.json', rarity: '3.2%'),
      GiftModelOption(name: 'The Gaze of Eternity', file: 'lib/assets/gifts/gargona/The-Gazeo-of-Eternity.json', rarity: '1.5%'),
      GiftModelOption(name: 'Cute Gorgon', file: 'lib/assets/gifts/gargona/CuteGorgona.json', rarity: '8.0%'),
      GiftModelOption(name: 'Disco Gorgon', file: 'lib/assets/gifts/gargona/discogargona.json', rarity: '6.0%'),
      GiftModelOption(name: 'Extraterrestrial', file: 'lib/assets/gifts/gargona/extraterrestrial.json', rarity: '2.5%'),
      GiftModelOption(name: 'Hellish Gorgon', file: 'lib/assets/gifts/gargona/hellish-gorgon.json', rarity: '3.0%'),
      GiftModelOption(name: 'Pepe Gorgon', file: 'lib/assets/gifts/gargona/pepe-gargona.json', rarity: '1.2%'),
      GiftModelOption(name: 'Wolf Gorgon', file: 'lib/assets/gifts/gargona/wolf-gargonna.json', rarity: '5.0%'),
      GiftModelOption(name: 'Turtle Gorgon', file: 'lib/assets/gifts/gargona/Turtle-Gorgon.json', rarity: '7.0%'),
      GiftModelOption(name: 'Blue Meggera', file: 'lib/assets/gifts/gargona/bluemeggera.json', rarity: '6.5%'),
      GiftModelOption(name: 'Field Gorgon', file: 'lib/assets/gifts/gargona/field-gorgonna.json', rarity: '7.5%'),
      GiftModelOption(name: 'Eastern Gorgon', file: 'lib/assets/gifts/gargona/Khitayategargona.json', rarity: '8.5%'),
      GiftModelOption(name: 'Hand-drawn Gorgon', file: 'lib/assets/gifts/gargona/Hand-drawn-Gorgon.json', rarity: '5.5%'),
    ],
  };

  /// Returns the available models for this gift's collection
  static List<GiftModelOption> getModelsForGift(UserGift gift) {
    final lowerId = gift.giftId.toLowerCase().trim();
    final lowerName = gift.giftName.toLowerCase().trim();
    final lowerFile = gift.modelFile.toLowerCase().trim();

    if (lowerId.contains('girl') || lowerName.contains('girl') || lowerFile.contains('girl')) {
      return giftCollections['girl']!;
    }
    if (lowerId.contains('car') || lowerId.contains('bmw') || lowerId.contains('lada') ||
        lowerName.contains('bmw') || lowerName.contains('priora') || lowerName.contains('gle') || lowerName.contains('tesla') || lowerFile.contains('cars')) {
      return giftCollections['cars']!;
    }
    if (lowerId.contains('theel') || lowerName.contains('bumblebee') || lowerFile.contains('theel')) {
      return giftCollections['theel']!;
    }
    return giftCollections['gargona']!;
  }

  /// Resolves the gradient decoration based on backdropName, backdropGradient or gift type
  static BoxDecoration getBackdropDecoration({
    required String backdropName,
    String? backdropGradient,
    String? giftName,
    String? giftId,
    BorderRadius? borderRadius,
  }) {
    final cleanBackdrop = backdropName.trim().toLowerCase();

    // 1. Direct match with official Telegram NFT backdrops
    if (cleanBackdrop.isNotEmpty && officialBackdropColors.containsKey(cleanBackdrop)) {
      return BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: officialBackdropColors[cleanBackdrop]!,
        ),
        borderRadius: borderRadius,
      );
    }

    // 2. Parse CSS gradient if provided
    final parsedGrad = _parseCssGradient(backdropGradient);
    if (parsedGrad != null) {
      return BoxDecoration(
        gradient: parsedGrad,
        borderRadius: borderRadius,
      );
    }

    // 3. Fallback named gradient for partial or custom names
    if (cleanBackdrop.isNotEmpty) {
      return BoxDecoration(
        gradient: _getNamedGradient(cleanBackdrop),
        borderRadius: borderRadius,
      );
    }

    // 4. Default for non-upgraded standard gifts: distinctive aesthetic gradient per gift
    return BoxDecoration(
      gradient: _getStandardGiftGradient(giftName, giftId),
      borderRadius: borderRadius,
    );
  }

  /// Ambient glow color for bloom behind gift model
  static Color getAmbientGlowColor(String backdropName, String giftName, [String? backdropGradient]) {
    final cleanBackdrop = backdropName.trim().toLowerCase();

    // 1. Direct match from official backdrops
    if (cleanBackdrop.isNotEmpty && officialBackdropColors.containsKey(cleanBackdrop)) {
      if (cleanBackdrop == 'black' || cleanBackdrop == 'onyx black') {
        return const Color(0x66606670);
      }
      return officialBackdropColors[cleanBackdrop]!.first.withOpacity(0.55);
    }

    // 2. Try to extract vibrant accent color directly from backdropGradient
    if (backdropGradient != null && backdropGradient.isNotEmpty) {
      final parsedColors = _extractColors(backdropGradient);
      for (final c in parsedColors) {
        final brightness = (c.red * 299 + c.green * 587 + c.blue * 114) / 1000;
        if (brightness > 30) {
          return c.withOpacity(0.55);
        }
      }
    }

    // 3. Fallback by keywords
    final lower = '$backdropName $giftName'.toLowerCase();
    if (lower.contains('fire') || lower.contains('red') || lower.contains('balloon') || lower.contains('crimson') || lower.contains('carmine')) {
      return const Color(0x99FF2D55);
    }
    if (lower.contains('blue') || lower.contains('electric') || lower.contains('ocean') || lower.contains('bmw') || lower.contains('cobalt') || lower.contains('azure') || lower.contains('sapphire') || lower.contains('celtic')) {
      return const Color(0x993B98FF);
    }
    if (lower.contains('sunset') || lower.contains('amber') || lower.contains('orange') || lower.contains('caramel') || lower.contains('bumblebee') || lower.contains('theel')) {
      return const Color(0x99F59E0B);
    }
    if (lower.contains('purple') || lower.contains('amethyst') || lower.contains('violet') || lower.contains('lavender') || lower.contains('lilac') || lower.contains('girl')) {
      return const Color(0x99A855F7);
    }
    if (lower.contains('berry') || lower.contains('pink') || lower.contains('rose') || lower.contains('ruby')) {
      return const Color(0x99EC4899);
    }
    if (lower.contains('emerald') || lower.contains('green') || lower.contains('mint') || lower.contains('gorgon') || lower.contains('gargona')) {
      return const Color(0x9910B981);
    }
    if (lower.contains('gold') || lower.contains('yellow') || lower.contains('lemon')) {
      return const Color(0x99EAB308);
    }
    if (lower.contains('cyan') || lower.contains('ice') || lower.contains('turquoise') || lower.contains('aquamarine')) {
      return const Color(0x9906B6D4);
    }
    return const Color(0x6638BDF8);
  }

  static Gradient _getStandardGiftGradient(String? giftName, String? giftId) {
    final key = '${giftName ?? ''} ${giftId ?? ''}'.toLowerCase();
    if (key.contains('gargona') || key.contains('gorgon')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF234433), Color(0xFF13231B), Color(0xFF09120E)],
      );
    }
    if (key.contains('girl') || key.contains('anime')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF4A2542), Color(0xFF281324), Color(0xFF120810)],
      );
    }
    if (key.contains('theel') || key.contains('bumblebee')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF4A3816), Color(0xFF2B200A), Color(0xFF140F05)],
      );
    }
    if (key.contains('bmw') || key.contains('m4') || key.contains('cars')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF1D3557), Color(0xFF101E31), Color(0xFF080F19)],
      );
    }
    if (key.contains('priora') || key.contains('lada')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF2E333B), Color(0xFF1B1E23), Color(0xFF0D0F11)],
      );
    }
    if (key.contains('condom') || key.contains('balloon')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF4C1828), Color(0xFF290C15), Color(0xFF120509)],
      );
    }
    return const RadialGradient(
      center: Alignment.center,
      radius: 0.95,
      colors: [Color(0xFF2C3240), Color(0xFF191C24), Color(0xFF0F1117)],
    );
  }

  static List<Color> _extractColors(String css) {
    final colors = <Color>[];
    final s = css.trim().toLowerCase();

    final hexMatches = RegExp(r'#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})').allMatches(s);
    for (final m in hexMatches) {
      var hex = m.group(0)!.replaceFirst('#', '');
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      if (hex.length == 6) {
        hex = 'FF$hex';
      } else if (hex.length == 8) {
        final r = hex.substring(0, 2);
        final g = hex.substring(2, 4);
        final b = hex.substring(4, 6);
        final a = hex.substring(6, 8);
        hex = '$a$r$g$b';
      }
      final val = int.tryParse(hex, radix: 16);
      if (val != null) colors.add(Color(val));
    }

    final rgbMatches = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)').allMatches(s);
    for (final m in rgbMatches) {
      final r = int.tryParse(m.group(1) ?? '0') ?? 0;
      final g = int.tryParse(m.group(2) ?? '0') ?? 0;
      final b = int.tryParse(m.group(3) ?? '0') ?? 0;
      final aStr = m.group(4);
      final a = aStr != null ? ((double.tryParse(aStr) ?? 1.0) * 255).round().clamp(0, 255) : 255;
      colors.add(Color.fromARGB(a, r, g, b));
    }

    return colors;
  }

  static Gradient? _parseCssGradient(String? css) {
    if (css == null || css.trim().isEmpty) return null;
    final s = css.trim().toLowerCase();

    final colors = _extractColors(s);
    if (colors.length >= 2) {
      final stopMatches = RegExp(r'(\d+(?:\.\d+)?)%').allMatches(s).map((m) {
        final pct = double.tryParse(m.group(1) ?? '');
        return pct != null ? (pct / 100.0).clamp(0.0, 1.0) : null;
      }).whereType<double>().toList();

      List<double>? stops;
      if (stopMatches.length == colors.length) {
        stops = stopMatches;
      }

      if (s.contains('radial')) {
        return RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: colors,
          stops: stops,
        );
      } else {
        Alignment begin = Alignment.topLeft;
        Alignment end = Alignment.bottomRight;
        if (s.contains('to bottom') || s.contains('180deg')) {
          begin = Alignment.topCenter;
          end = Alignment.bottomCenter;
        } else if (s.contains('to right') || s.contains('90deg')) {
          begin = Alignment.centerLeft;
          end = Alignment.centerRight;
        }

        return LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
          stops: stops,
        );
      }
    } else if (colors.length == 1) {
      return LinearGradient(
        colors: [colors.first, colors.first],
      );
    }
    return null;
  }

  static Gradient _getNamedGradient(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('fire') || lower.contains('red') || lower.contains('crimson') || lower.contains('carmine')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFFEF5E4F), Color(0xFFD0434B)],
      );
    }

    if (lower.contains('blue') || lower.contains('electric') || lower.contains('ocean') || lower.contains('cobalt') || lower.contains('azure')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF5CB0CA), Color(0xFF4B96B4)],
      );
    }

    if (lower.contains('amethyst') || lower.contains('purple') || lower.contains('violet') || lower.contains('lavender') || lower.contains('lilac')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFFB07CA4), Color(0xFF976285)],
      );
    }

    if (lower.contains('sunset') || lower.contains('amber') || lower.contains('orange') || lower.contains('caramel')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFFD9B245), Color(0xFFBC8E31)],
      );
    }

    if (lower.contains('berry') || lower.contains('pink') || lower.contains('rose') || lower.contains('ruby')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFFFF2D78), Color(0xFFC2185B)],
      );
    }

    if (lower.contains('emerald') || lower.contains('green') || lower.contains('mint')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF77C585), Color(0xFF51AB76)],
      );
    }

    if (lower.contains('gold') || lower.contains('yellow') || lower.contains('lemon')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFFCBAA40), Color(0xFFA78936)],
      );
    }

    if (lower.contains('cyber') || lower.contains('neon')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF858DF2), Color(0xFF866DDC)],
      );
    }

    if (lower.contains('cyan') || lower.contains('ice') || lower.contains('turquoise') || lower.contains('aquamarine')) {
      return const RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: [Color(0xFF5DBEB6), Color(0xFF469F9A)],
      );
    }

    return const RadialGradient(
      center: Alignment.center,
      radius: 0.95,
      colors: [Color(0xFF2C3240), Color(0xFF191C24), Color(0xFF0F1117)],
    );
  }
}

/// Custom painter for tiled background patterns (Crown, Ace Of Hearts, Snowflake, etc.)
class GiftPatternPainter extends CustomPainter {
  final String patternName;

  GiftPatternPainter({required this.patternName});

  @override
  void paint(Canvas canvas, Size size) {
    final lower = patternName.toLowerCase();
    if (lower.isEmpty) return; // User instruction: no pattern during upgrade

    final strokePaint = Paint()
      ..color = Colors.white.withOpacity(0.085)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final fillPaint = Paint()
      ..color = Colors.white.withOpacity(0.075)
      ..style = PaintingStyle.fill;

    if (lower.contains('crown')) {
      _paintCrowns(canvas, size, strokePaint, fillPaint);
    } else if (lower.contains('diamond')) {
      _paintDiamonds(canvas, size, strokePaint, fillPaint);
    } else if (lower.contains('snow')) {
      _paintSnowflakes(canvas, size, strokePaint);
    } else if (lower.contains('star')) {
      _paintStars(canvas, size, fillPaint);
    } else if (lower.contains('hex')) {
      _paintHexagons(canvas, size, strokePaint);
    } else if (lower.contains('rap') || lower.contains('sign') || lower.contains('hand') || lower.contains('westside')) {
      _paintRapSign(canvas, size, strokePaint, fillPaint);
    } else if (lower.contains('ace')) {
      _paintAceOfHearts(canvas, size, strokePaint, fillPaint);
    } else if (lower.contains('heart')) {
      _paintHearts(canvas, size, fillPaint);
    } else {
      _paintAceOfHearts(canvas, size, strokePaint, fillPaint);
    }
  }

  void _paintAceOfHearts(Canvas canvas, Size size, Paint stroke, Paint fill) {
    const cardWidth = 32.0;
    const cardHeight = 44.0;
    const stepX = 54.0;
    const stepY = 64.0;

    for (double y = 8; y < size.height + stepY; y += stepY) {
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 8.0 : (8.0 + stepX / 2);

      for (double x = startX - stepX; x < size.width + stepX; x += stepX) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: cardWidth, height: cardHeight),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, stroke);
        _drawHeart(canvas, Offset(x, y), 5.5, fill);
      }
    }
  }

  void _paintHearts(Canvas canvas, Size size, Paint fill) {
    const stepX = 40.0;
    const stepY = 44.0;
    for (double y = 12; y < size.height + stepY; y += stepY) {
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 10.0 : (10.0 + stepX / 2);
      for (double x = startX - stepX; x < size.width + stepX; x += stepX) {
        _drawHeart(canvas, Offset(x, y), 5.0, fill);
      }
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double s, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy + s * 0.7);
    path.cubicTo(
      center.dx - s * 1.2, center.dy - s * 0.2,
      center.dx - s * 1.0, center.dy - s * 1.0,
      center.dx, center.dy - s * 0.4,
    );
    path.cubicTo(
      center.dx + s * 1.0, center.dy - s * 1.0,
      center.dx + s * 1.2, center.dy - s * 0.2,
      center.dx, center.dy + s * 0.7,
    );
    canvas.drawPath(path, paint);
  }

  void _paintCrowns(Canvas canvas, Size size, Paint stroke, Paint fill) {
    const stepX = 48.0;
    const stepY = 48.0;
    for (double y = 12; y < size.height + stepY; y += stepY) {
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 10.0 : (10.0 + stepX / 2);
      for (double x = startX - stepX; x < size.width + stepX; x += stepX) {
        final path = Path();
        final cx = x;
        final cy = y;
        path.moveTo(cx - 7, cy + 4);
        path.lineTo(cx + 7, cy + 4);
        path.lineTo(cx + 6, cy - 3);
        path.lineTo(cx + 2.5, cy + 1);
        path.lineTo(cx, cy - 5);
        path.lineTo(cx - 2.5, cy + 1);
        path.lineTo(cx - 6, cy - 3);
        path.close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      }
    }
  }

  void _paintDiamonds(Canvas canvas, Size size, Paint stroke, Paint fill) {
    const stepX = 42.0;
    const stepY = 42.0;
    for (double y = 10; y < size.height + stepY; y += stepY) {
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 10.0 : (10.0 + stepX / 2);
      for (double x = startX - stepX; x < size.width + stepX; x += stepX) {
        final path = Path();
        path.moveTo(x, y - 6);
        path.lineTo(x + 5.5, y);
        path.lineTo(x, y + 6);
        path.lineTo(x - 5.5, y);
        path.close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      }
    }
  }

  void _paintSnowflakes(Canvas canvas, Size size, Paint stroke) {
    const step = 46.0;
    for (double y = 12; y < size.height + step; y += step) {
      for (double x = 12; x < size.width + step; x += step) {
        for (int i = 0; i < 3; i++) {
          final angle = i * (math.pi / 3);
          final dx = 5.0 * math.cos(angle);
          final dy = 5.0 * math.sin(angle);
          canvas.drawLine(Offset(x - dx, y - dy), Offset(x + dx, y + dy), stroke);
        }
      }
    }
  }

  void _paintStars(Canvas canvas, Size size, Paint fill) {
    const step = 44.0;
    for (double y = 10; y < size.height + step; y += step) {
      for (double x = 10; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 2.2, fill);
        canvas.drawCircle(Offset(x + step / 2, y + step / 2), 1.2, fill);
      }
    }
  }

  void _paintHexagons(Canvas canvas, Size size, Paint stroke) {
    const r = 9.0;
    const h = 15.588;
    const stepX = 27.0;
    const stepY = h;

    for (double y = 0; y < size.height + stepY; y += stepY) {
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 0.0 : 13.5;
      for (double x = startX - stepX; x < size.width + stepX; x += stepX) {
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = i * (math.pi / 3);
          final px = x + r * math.cos(angle);
          final py = y + r * math.sin(angle);
          if (i == 0) path.moveTo(px, py);
          else path.lineTo(px, py);
        }
        path.close();
        canvas.drawPath(path, stroke);
      }
    }
  }

  void _paintRapSign(Canvas canvas, Size size, Paint stroke, Paint fill) {
    const stepX = 46.0;
    const stepY = 46.0;
    for (double y = 12; y < size.height + stepY; y += stepY) {
      final isOddRow = ((y ~/ stepY) % 2) == 1;
      final startX = isOddRow ? 10.0 : (10.0 + stepX / 2);
      for (double x = startX - stepX; x < size.width + stepX; x += stepX) {
        final path = Path();
        path.moveTo(x - 5, y - 4);
        path.lineTo(x - 3, y + 4);
        path.lineTo(x, y - 2);
        path.lineTo(x + 3, y + 4);
        path.lineTo(x + 5, y - 4);
        canvas.drawPath(path, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GiftPatternPainter oldDelegate) {
    return oldDelegate.patternName != patternName;
  }
}

/// Widget that displays the gift 3D/Lottie animation or static image
class GiftModelWidget extends StatelessWidget {
  final UserGift gift;
  final double size;
  final bool animate;

  const GiftModelWidget({
    super.key,
    required this.gift,
    this.size = 140,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final path = gift.assetPath;

    if (gift.isImage) {
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    return Lottie.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      animate: animate,
      errorBuilder: (_, __, ___) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return Icon(
      Icons.card_giftcard_rounded,
      size: size * 0.6,
      color: Colors.white70,
    );
  }
}
