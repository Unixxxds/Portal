import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes = List.generate(6, (_) => FocusNode());
  final _cloudPasswordController = TextEditingController();

  bool _obscureCloudPassword = true;
  int _countdown = 0;
  Timer? _timer;
  String? _localError;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 6; i++) {
      final index = i;
      _digitControllers[index].addListener(() {
        if (_digitControllers[index].text.length > 1) {
          _handlePastedCode(_digitControllers[index].text, index);
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
      _handleVerifyCode();
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

  Future<void> _handleSendCode() async {
    setState(() => _localError = null);
    final email = _emailController.text.trim().toLowerCase();
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (email.isEmpty || !emailRegex.hasMatch(email)) {
      setState(() => _localError = 'Введите корректный адрес электронной почты');
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.sendCode(email);
    if (!mounted) return;

    if (success) {
      for (final c in _digitControllers) {
        c.clear();
      }
      _startCountdown();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _digitFocusNodes[0].requestFocus();
      });
    } else {
      setState(() => _localError = auth.errorMessage ?? 'Не удалось отправить код');
    }
  }

  Future<void> _handleVerifyCode() async {
    setState(() => _localError = null);
    final code = _getCode();
    if (code.length < 6) {
      setState(() => _localError = 'Введите полный 6-значный код');
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final auth = context.read<AuthProvider>();
    final success = await auth.verifyCode(email, code);
    if (!mounted) return;

    if (!success) {
      setState(() => _localError = auth.errorMessage ?? 'Неверный код подтверждения');
    }
  }

  Future<void> _handleVerifyCloudPassword() async {
    setState(() => _localError = null);
    final password = _cloudPasswordController.text.trim();
    if (password.isEmpty) {
      setState(() => _localError = 'Введите облачный пароль');
      return;
    }

    final auth = context.read<AuthProvider>();
    final email = _emailController.text.trim().toLowerCase();
    final success = await auth.verifyCloudPassword(email, password);
    if (!mounted) return;

    if (!success) {
      setState(() => _localError = auth.errorMessage ?? 'Неверный облачный пароль');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final errorMessage = _localError ?? auth.errorMessage;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              decoration: BoxDecoration(
                color: AppTheme.authCardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.authCardBorder, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xCC000000),
                    blurRadius: 50,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Portal Brand Logo
                  Image.asset(
                    'assets/images/portal-logo.png',
                    height: 48,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.accentBlue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.flash_on, color: Colors.white, size: 28),
                    ),
                  ),
                  const SizedBox(height: 22),

                  if (auth.step == AuthStep.cloudPassword) ...[
                    _buildCloudPasswordView(auth, errorMessage),
                  ] else if (auth.step == AuthStep.code) ...[
                    _buildCodeView(auth, errorMessage),
                  ] else ...[
                    _buildEmailInputView(auth, errorMessage),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailInputView(AuthProvider auth, String? errorMessage) {
    return Column(
      children: [
        const Text(
          'Вход в Portal',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Введите ваш e-mail для входа или быстрой регистрации',
          style: TextStyle(
            fontSize: 13.5,
            color: Color(0xFF8E8E93),
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Input label
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'ЭЛЕКТРОННАЯ ПОЧТА',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: Color(0xFF71717A),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Email textfield
        Container(
          decoration: BoxDecoration(
            color: AppTheme.authInputBg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: errorMessage != null ? const Color(0xFFFF453A) : AppTheme.authInputBorder,
              width: 1,
            ),
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: const InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(color: Color(0xFF636366), fontSize: 16),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: Icon(Icons.mail_outline_rounded, color: Color(0xFF636366), size: 19),
            ),
            onSubmitted: (_) => _handleSendCode(),
          ),
        ),
        const SizedBox(height: 16),

        if (errorMessage != null) ...[
          Text(
            errorMessage,
            style: const TextStyle(
              color: Color(0xFFFF453A),
              fontSize: 12.5,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],

        // Submit Button (iOS White Button style)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : _handleSendCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Продолжить',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeView(AuthProvider auth, String? errorMessage) {
    final email = _emailController.text.trim();

    return Column(
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {
              setState(() => _localError = null);
              auth.resetToEmailStep();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, color: Color(0xFF8E8E93), size: 20),
                  SizedBox(width: 2),
                  Text(
                    'Назад',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        const Text(
          'Код подтверждения',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93), height: 1.45),
            children: [
              const TextSpan(text: 'Мы отправили проверочный код на\n'),
              TextSpan(
                text: email,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 6 digit code boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            final hasValue = _digitControllers[index].text.isNotEmpty;
            return Container(
              width: 44,
              height: 52,
              margin: EdgeInsets.only(right: index == 5 ? 0 : 7),
              decoration: BoxDecoration(
                color: AppTheme.authInputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: errorMessage != null
                      ? const Color(0xFFFF453A)
                      : (hasValue ? Colors.white : AppTheme.authInputBorder),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: TextField(
                  controller: _digitControllers[index],
                  focusNode: _digitFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (val) {
                    setState(() {});
                    if (val.isNotEmpty) {
                      if (index < 5) {
                        _digitFocusNodes[index + 1].requestFocus();
                      } else {
                        _digitFocusNodes[index].unfocus();
                        _handleVerifyCode();
                      }
                    } else if (val.isEmpty && index > 0) {
                      _digitFocusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),

        if (errorMessage != null) ...[
          Text(
            errorMessage,
            style: const TextStyle(
              color: Color(0xFFFF453A),
              fontSize: 12.5,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],

        // Submit button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: auth.isLoading || _getCode().length < 6 ? null : _handleVerifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withOpacity(0.35),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Войти',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Resend countdown
        if (_countdown > 0)
          Text(
            'Повторно через $_countdown с',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          )
        else
          TextButton(
            onPressed: auth.isLoading ? null : _handleSendCode,
            child: const Text(
              'Отправить код повторно',
              style: TextStyle(
                color: AppTheme.accentBlue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCloudPasswordView(AuthProvider auth, String? errorMessage) {
    return Column(
      children: [
        // Back button to code
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {
              setState(() => _localError = null);
              auth.returnToCodeStep();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, color: Color(0xFF8E8E93), size: 20),
                  SizedBox(width: 2),
                  Text(
                    'Назад к коду',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Key icon badge (52x52 rounded)
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x1FFFFFFF), width: 1),
          ),
          child: const Center(
            child: Icon(Icons.key_rounded, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 18),

        const Text(
          'Облачный пароль',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Для вашего аккаунта настроена двухэтапная аутентификация. Введите облачный пароль.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF8E8E93),
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),

        // Password hint pill if provided
        if (auth.cloudPasswordHint != null && auth.cloudPasswordHint!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF14161D),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFF222530), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF8E8E93)),
                      children: [
                        const TextSpan(text: 'Подсказка: '),
                        TextSpan(
                          text: auth.cloudPasswordHint,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        // Password input
        Container(
          decoration: BoxDecoration(
            color: AppTheme.authInputBg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: errorMessage != null ? const Color(0xFFFF453A) : AppTheme.authInputBorder,
              width: 1,
            ),
          ),
          child: TextField(
            controller: _cloudPasswordController,
            obscureText: _obscureCloudPassword,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Введите пароль',
              hintStyle: const TextStyle(color: Color(0xFF636366), fontSize: 15),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCloudPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF8E8E93),
                  size: 19,
                ),
                onPressed: () => setState(() => _obscureCloudPassword = !_obscureCloudPassword),
              ),
            ),
            onSubmitted: (_) => _handleVerifyCloudPassword(),
          ),
        ),
        const SizedBox(height: 16),

        if (errorMessage != null) ...[
          Text(
            errorMessage,
            style: const TextStyle(
              color: Color(0xFFFF453A),
              fontSize: 12.5,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],

        // Verify button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : _handleVerifyCloudPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white.withOpacity(0.35),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text(
                    'Войти в Portal',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
