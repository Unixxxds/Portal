import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selectedLanguageCode = 'ru';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('portal_language') ?? 'ru';
      });
    }
  }

  Future<void> _selectLanguage(String code) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('portal_language', code);
    if (mounted) {
      setState(() => _selectedLanguageCode = code);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выбран русский язык'),
          duration: Duration(milliseconds: 1400),
          backgroundColor: Color(0xFF1E222D),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Язык',
          style: TextStyle(
            fontFamily: AppTheme.fontDisplay,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 14, bottom: 8),
            child: Text(
              'ДОСТУПНЫЕ ЯЗЫКИ',
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
            ),
            child: InkWell(
              onTap: () => _selectLanguage('ru'),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Русский',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Russian',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedLanguageCode == 'ru')
                      const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF007AFF),
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'В приложении Portal в настоящее время поддерживается русский язык интерфейса.',
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 13,
                color: Color(0xFF8E8E93),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

