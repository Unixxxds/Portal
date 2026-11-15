import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/account_session.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/multi_account_service.dart';
import '../theme.dart';

enum AddAccountStep { email, code, cloudPassword }

class AddAccountModal extends StatefulWidget {
  const AddAccountModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddAccountModal(),
    );
  }

  @override
  State<AddAccountModal> createState() => _AddAccountModalState();
}

class _AddAccountModalState extends State<AddAccountModal> {
  AddAccountStep _step = AddAccountStep.email;
  final _emailController = TextEditingController();
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes = List.generate(6, (_) => FocusNode());
  final _cloudPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  int _countdown = 0;
  Timer? _timer;

  String? _tempToken;
  String? _cloudPasswordHint;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 6; i++) {
      final index = i;
      _digitControllers[index].addListener(() {
        final text = _digitControllers[index].text;
        if (text.length > 1) {
          _handlePastedCode(text, index);
        } else if (text.length == 1 && index < 5) {
          _digitFocusNodes[index + 1].requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    _cloudPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _handlePastedCode(String text, int fromIndex) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    for (int i = 0; i < 6; i++) {
      if (i < digits.length) {
        _digitControllers[i].text = digits[i];
      }
    }
    final nextFocus = digits.length < 6 ? digits.length : 5;
    _digitFocusNodes[nextFocus].requestFocus();

    if (digits.length >= 6) {
      _verifyCode();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 45);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  String _getCode() {
    return _digitControllers.map((c) => c.text.trim()).join();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim().toLowerCase();
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (email.isEmpty || !emailRegex.hasMatch(email)) {
      setState(() => _error = 'Введите корректный адрес электронной почты');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await ApiService.instance.sendCode(email);
      if (res['success'] == true) {
        setState(() {
          _isLoading = false;
          _step = AddAccountStep.code;
        });
        for (final c in _digitControllers) {
          c.clear();
        }
        _startCountdown();
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) _digitFocusNodes[0].requestFocus();
        });
      } else {
        throw Exception(res['message'] ?? 'Не удалось отправить код');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _verifyCode() async {
    final code = _getCode();
    if (code.length < 6) {
      setState(() => _error = 'Введите полный 6-значный код');
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await ApiService.instance.verifyCode(email, code);
      if (res['success'] == true) {
        // Проверка 2FA
        if (res['requiresCloudPassword'] == true) {
          setState(() {
            _tempToken = res['tempToken']?.toString();
            _cloudPasswordHint = res['hint']?.toString();
            _step = AddAccountStep.cloudPassword;
            _isLoading = false;
          });
          return;
        }

        // Успешный вход
        if (res['token'] != null && res['user'] != null) {
          await _finishLogin(
            token: res['token'].toString(),
            userData: res['user'] as Map<String, dynamic>,
          );
        }
      } else {
        throw Exception(res['error'] ?? res['message'] ?? 'Неверный код подтверждения');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _verifyCloudPassword() async {
    if (_tempToken == null) return;
    final password = _cloudPasswordController.text.trim();
    if (password.isEmpty) {
      setState(() => _error = 'Введите облачный пароль');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await ApiService.instance.verifyCloudPassword(_tempToken!, password);
      if (res['success'] == true && res['token'] != null && res['user'] != null) {
        await _finishLogin(
          token: res['token'].toString(),
          userData: res['user'] as Map<String, dynamic>,
        );
      } else {
        throw Exception(res['error'] ?? 'Неверный облачный пароль');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _finishLogin({
    required String token,
    required Map<String, dynamic> userData,
  }) async {
    final newUser = User.fromJson(userData);
    final newSession = AccountSession(
      userId: newUser.id,
      token: token,
      user: newUser,
      lastActive: DateTime.now(),
    );

    // Save into multi-account service
    await MultiAccountService.instance.saveAccount(newSession);

    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();

    // Switch to new account immediately
    await authProvider.switchAccount(newSession, context);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 20),
              const SizedBox(width: 10),
              Text(
                'Вы вошли как ${newUser.fullName.isNotEmpty ? newUser.fullName : newUser.username}',
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Добавить аккаунт',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Step Content
            if (_step == AddAccountStep.email) _buildEmailStep(),
            if (_step == AddAccountStep.code) _buildCodeStep(),
            if (_step == AddAccountStep.cloudPassword) _buildCloudPasswordStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Введите адрес электронной почты вашего второго аккаунта Portal.',
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 13.5,
            color: Color(0xFF8E8E93),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),

        // Email field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Colors.white,
              fontSize: 16,
            ),
            decoration: const InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(
                fontFamily: AppTheme.fontText,
                color: Color(0xFF636366),
              ),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _sendCode(),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Color(0xFFFF3B30),
              fontSize: 13,
            ),
          ),
        ],

        const SizedBox(height: 22),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              disabledBackgroundColor: const Color(0x33007AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Text(
                    'Получить код',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Код подтверждения отправлен на ${_emailController.text}',
          style: const TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 13.5,
            color: Color(0xFF8E8E93),
          ),
        ),
        const SizedBox(height: 18),

        // 6 Digits Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: _digitControllers[index],
                focusNode: _digitFocusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                style: const TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF2C2C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) {
                  if (val.isEmpty && index > 0) {
                    _digitFocusNodes[index - 1].requestFocus();
                  }
                  if (_getCode().length == 6) {
                    _verifyCode();
                  }
                },
              ),
            );
          }),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Color(0xFFFF3B30),
              fontSize: 13,
            ),
          ),
        ],

        const SizedBox(height: 18),

        // Countdown or Resend button
        Center(
          child: _countdown > 0
              ? Text(
                  'Отправить повторно через $_countdown сек',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                  ),
                )
              : TextButton(
                  onPressed: _sendCode,
                  child: const Text(
                    'Отправить код повторно',
                    style: TextStyle(
                      color: Color(0xFF007AFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
        ),

        const SizedBox(height: 12),

        // Verify button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              disabledBackgroundColor: const Color(0x33007AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Text(
                    'Войти',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloudPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Для этого аккаунта включена двухфакторная аутентификация. Введите ваш облачный пароль.',
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 13.5,
            color: Color(0xFF8E8E93),
            height: 1.35,
          ),
        ),
        if (_cloudPasswordHint != null && _cloudPasswordHint!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Подсказка: $_cloudPasswordHint',
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 12.5,
              color: Color(0xFF007AFF),
            ),
          ),
        ],
        const SizedBox(height: 18),

        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _cloudPasswordController,
            obscureText: true,
            autofocus: true,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Colors.white,
              fontSize: 16,
            ),
            decoration: const InputDecoration(
              hintText: 'Облачный пароль',
              hintStyle: TextStyle(
                fontFamily: AppTheme.fontText,
                color: Color(0xFF636366),
              ),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _verifyCloudPassword(),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Color(0xFFFF3B30),
              fontSize: 13,
            ),
          ),
        ],

        const SizedBox(height: 22),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyCloudPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              disabledBackgroundColor: const Color(0x33007AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Text(
                    'Подтвердить',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

