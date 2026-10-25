import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailCodeLoginPage extends StatefulWidget {
  const EmailCodeLoginPage({super.key});

  @override
  State<EmailCodeLoginPage> createState() => _EmailCodeLoginPageState();
}

class _EmailCodeLoginPageState extends State<EmailCodeLoginPage> {
  static const _endpoint =
      'https://zbwmmmstzlgjmhhoceiv.supabase.co/functions/v1/email-code';

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The server returned an unexpected response.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['error']?.toString() ?? 'Request failed. Please try again.',
      );
    }
    return data;
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();

    if (!_emailController.text.trim().contains('@') ||
        !_emailController.text.trim().contains('.')) {
      setState(() {
        _error = 'Enter a valid email address.';
        _notice = null;
      });
      return;
    }

    if (_cooldown > 0) return;

    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });

    try {
      final result = await _request({
        'action': 'send',
        'email': _email,
      });

      if (!mounted) return;
      setState(() {
        _codeSent = result['success'] == true;
        _notice = result['message']?.toString() ??
            'Check your inbox for your verification code.';
      });
      _startCooldown();
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'Request timed out. Check your connection.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Enter the complete six-digit code.';
        _notice = null;
      });
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
      _notice = null;
    });

    try {
      final result = await _request({
        'action': 'verify',
        'email': _email,
        'code': code,
      });

      if (result['success'] != true || result['verified'] != true) {
        throw Exception('The code could not be verified.');
      }

      final tokenHash = result['token_hash']?.toString().trim();
      if (tokenHash == null || tokenHash.isEmpty) {
        throw Exception('The server did not return a sign-in token. Please try again.');
      }

      await Supabase.instance.client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.magiclink,
      );
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'Verification timed out. Try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = Color(0xFF7967F8);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'CourseDeep',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your AI learning companion',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 42),
                  Text(
                    _codeSent ? 'Check your email' : 'Welcome back',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent
                        ? 'Enter the six-digit code sent to your email address.'
                        : 'Sign in securely using a six-digit email verification code. No password needed.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    controller: _emailController,
                    enabled: !_sending && !_verifying && !_codeSent,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeController,
                      enabled: !_verifying,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      onSubmitted: (_) => _verifyCode(),
                      decoration: const InputDecoration(
                        labelText: 'Six-digit verification code',
                        hintText: '000000',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _message(_error!, Colors.red.shade700),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 14),
                    _message(
                      _notice!,
                      dark ? Colors.greenAccent : Colors.green.shade800,
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _sending || _verifying
                          ? null
                          : (_codeSent ? _verifyCode : _sendCode),
                      child: (_sending || _verifying)
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _codeSent
                                  ? 'Verify and continue'
                                  : 'Send verification code',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _sending ||
                              _verifying ||
                              _cooldown > 0
                          ? null
                          : _sendCode,
                      child: Text(
                        _cooldown > 0
                            ? 'Resend code in ${_cooldown}s'
                            : 'Resend verification code',
                      ),
                    ),
                    TextButton(
                      onPressed: _sending || _verifying
                          ? null
                          : () {
                              setState(() {
                                _codeSent = false;
                                _codeController.clear();
                                _error = null;
                                _notice = null;
                              });
                            },
                      child: const Text('Use a different email'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'By continuing, you confirm that you can access this email address.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.4)),
    );
  }
}
