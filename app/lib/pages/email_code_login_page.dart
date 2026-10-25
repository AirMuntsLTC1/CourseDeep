import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Passwordless login: email -> six-digit code -> signed in.
/// The server checks the code and returns a ready session, the app just stores it.
class EmailCodeLoginPage extends StatefulWidget {
  const EmailCodeLoginPage({super.key});

  @override
  State<EmailCodeLoginPage> createState() => _EmailCodeLoginPageState();
}

class _EmailCodeLoginPageState extends State<EmailCodeLoginPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();

  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _codeFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _code.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (_code.text.length == 6 && !_verifying && _codeSent) _verify();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String get _mail => _email.text.trim().toLowerCase();
  bool get _busy => _sending || _verifying;

  Future<http.Response> _post(Map<String, dynamic> payload) async {
    try {
      return await http
          .post(Uri.parse(kEmailCodeUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const _LoginError('The request timed out. Check your connection and try again.');
    } catch (_) {
      throw const _LoginError('Could not reach CourseDeep. Check your internet connection.');
    }
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final r = await _post(payload);
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      throw const _LoginError('The server sent an unexpected answer. Please try again.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw _LoginError(data['error']?.toString() ?? 'Request failed. Please try again.');
    }
    return data;
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_mail)) {
      setState(() {
        _error = 'Enter a valid email address.';
        _notice = null;
      });
      return;
    }
    if (_cooldown > 0 && _codeSent) return;
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await _call({'action': 'send', 'email': _mail});
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _code.clear();
        _notice = r['message']?.toString() ?? 'We sent a six-digit code to your email.';
      });
      _startCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
    } on _LoginError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _error = 'Enter the complete six-digit code.';
        _notice = null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await _call({'action': 'verify', 'email': _mail, 'code': code});
      final refresh = r['refresh_token']?.toString() ?? '';
      if (r['verified'] != true || refresh.isEmpty) {
        throw const _LoginError('Sign-in could not be completed. Please request a new code.');
      }
      // The auth gate in main.dart switches to the chat screen as soon as the session exists.
      await Supabase.instance.client.auth.setSession(refresh);
    } on _LoginError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _code.clear();
        });
        _codeFocus.requestFocus();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: ${e.message}. Please request a new code.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please request a new code.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (d?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6) _code.text = digits.substring(0, 6);
  }

  void _changeEmail() {
    setState(() {
      _codeSent = false;
      _code.clear();
      _error = null;
      _notice = null;
    });
    _emailFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (pal.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: pal.bg),
      child: Scaffold(
        backgroundColor: pal.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: AiOrb(size: 76)),
                  const SizedBox(height: 4),
                  Center(
                    child: ShaderMask(
                      shaderCallback: (r) => Brand.gradient.createShader(r),
                      child: const Text('CourseDeep',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.8)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Your AI learning companion', textAlign: TextAlign.center, style: TextStyle(color: pal.dim, fontSize: 14.5)),
                  const SizedBox(height: 30),

                  // card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: pal.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: pal.border),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _codeSent ? 'Check your email' : 'Sign in or sign up',
                          key: ValueKey(_codeSent),
                          style: TextStyle(color: pal.text, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _codeSent ? 'Enter the six-digit code we sent to $_mail' : 'No password needed. We email you a six-digit code.',
                        style: TextStyle(color: pal.dim, fontSize: 14, height: 1.45),
                      ),
                      const SizedBox(height: 18),
                      if (!_codeSent) _emailField(pal, cs) else _otpBoxes(pal, cs),
                      if (_error != null) _banner(_error!, cs.error, Icons.error_outline_rounded),
                      if (_notice != null && _error == null) _banner(_notice!, const Color(0xFF34D399), Icons.mark_email_read_outlined),
                      const SizedBox(height: 18),
                      _primaryButton(),
                      if (_codeSent) ...[
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          TextButton(onPressed: _busy ? null : _changeEmail, child: const Text('Change email')),
                          TextButton(onPressed: _busy ? null : _paste, child: const Text('Paste code')),
                          TextButton(
                            onPressed: (_busy || _cooldown > 0) ? null : _send,
                            child: Text(_cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend code'),
                          ),
                        ]),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 22),
                  Text('By continuing, you confirm that you can access this email address.',
                      textAlign: TextAlign.center, style: TextStyle(color: pal.dim.withValues(alpha: 0.8), fontSize: 12, height: 1.5)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailField(Pal pal, ColorScheme cs) => Container(
        decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(18)),
        child: TextField(
          controller: _email,
          focusNode: _emailFocus,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _send(),
          style: TextStyle(color: pal.text, fontSize: 16.5),
          cursorColor: cs.primary,
          decoration: InputDecoration(
            hintText: 'you@example.com',
            hintStyle: TextStyle(color: pal.dim.withValues(alpha: 0.7)),
            prefixIcon: Icon(Icons.alternate_email_rounded, color: pal.dim),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      );

  Widget _otpBoxes(Pal pal, ColorScheme cs) {
    final text = _code.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _codeFocus.requestFocus(),
      child: Stack(children: [
        Row(children: [
          for (var i = 0; i < 6; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pal.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: i == text.length && _codeFocus.hasFocus ? cs.primary : (i < text.length ? cs.primary.withValues(alpha: 0.4) : Colors.transparent),
                    width: 1.6,
                  ),
                ),
                child: Text(i < text.length ? text[i] : '', style: TextStyle(color: pal.text, fontSize: 24, fontWeight: FontWeight.w700)),
              ),
            ),
            if (i < 5) const SizedBox(width: 8),
          ],
        ]),
        // real input, invisible: gives us the keyboard, paste and OS one-time-code autofill
        Positioned.fill(
          child: Opacity(
            opacity: 0.0,
            child: TextField(
              controller: _code,
              focusNode: _codeFocus,
              enabled: !_verifying,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent),
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _banner(String text, Color color, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.28))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13.5, height: 1.4))),
          ]),
        ),
      );

  Widget _primaryButton() {
    final enabled = !_busy && (_codeSent ? _code.text.length == 6 : true);
    return GestureDetector(
      onTap: enabled ? (_codeSent ? _verify : _send) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled || _busy ? 1 : 0.5,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(18)),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(_codeSent ? 'Verify and continue' : 'Continue with email',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _LoginError implements Exception {
  const _LoginError(this.message);
  final String message;
}
