
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/app_settings.dart';
import '../services/chat_store.dart';
import '../theme/app_theme.dart';
import '../services/update_service.dart';
import '../widgets/logo.dart';
import '../widgets/update_dialog.dart';

const _languages = ['English', 'Spanish', 'French', 'German', 'Portuguese', 'Chinese', 'Japanese', 'Korean', 'Arabic', 'Hindi', 'Tagalog', 'Indonesian'];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onChatsCleared});
  final VoidCallback onChatsCleared;

  User? get _user => Supabase.instance.client.auth.currentUser;

  void _toast(BuildContext c, String t) {
    final m = ScaffoldMessenger.of(c);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));
  }

  Future<void> _clearChats(BuildContext c) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Clear all chats?'),
        content: const Text('Every conversation and attached file on this device will be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ChatStore().clear();
    onChatsCleared();
    if (c.mounted) _toast(c, 'All chats cleared');
  }

  Future<void> _logout(BuildContext c) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign back in any time with a new email code. Your chats stay on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true || !c.mounted) return;
    // Close Settings first, otherwise it would stay on top of the login screen.
    Navigator.of(c).popUntil((r) => r.isFirst);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    }
  }

  Future<void> _checkUpdates(BuildContext c) async {
    _toast(c, 'Checking for updates…');
    try {
      final info = await UpdateService.fetchLatest();
      if (!c.mounted) return;
      if (info == null) {
        _toast(c, 'You are on the latest version ($kAppVersion).');
        return;
      }
      await showDialog<void>(context: c, barrierDismissible: false, builder: (_) => UpdateDialog(info: info));
    } catch (_) {
      if (c.mounted) _toast(c, 'Could not check for updates. Check your connection.');
    }
  }

  void _pickLanguage(BuildContext c) {
    showModalBottomSheet<void>(
      context: c,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('AI answer language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final l in _languages)
                  ListTile(
                    title: Text(l),
                    trailing: AppSettings.I.language == l ? Icon(Icons.check_circle_rounded, color: Theme.of(ctx).colorScheme.primary) : null,
                    onTap: () {
                      AppSettings.I.setLanguage(l);
                      Navigator.pop(ctx);
                    },
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _feedback(BuildContext c) {
    showModalBottomSheet<void>(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FeedbackSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.I,
      builder: (context, _) {
        final s = AppSettings.I;
        final pal = Pal.of(context);
        final cs = Theme.of(context).colorScheme;
        final email = _user?.email ?? 'Signed in';

        return Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, title: const Text('Settings'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              // profile card
              _Group(children: [
                ListTile(
                  leading: const CourseDeepLogo(size: 44, round: true),
                  title: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Signed in with email code'),
                  trailing: IconButton(
                    tooltip: 'Copy email',
                    icon: const Icon(Icons.content_copy_rounded, size: 19),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: email));
                      _toast(context, 'Email copied');
                    },
                  ),
                ),
              ]),

              const _Label('Appearance'),
              _Group(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded, size: 18), label: Text('Auto')),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18), label: Text('Light')),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18), label: Text('Dark')),
                      ],
                      selected: {s.themeMode},
                      onSelectionChanged: (v) => s.setThemeMode(v.first),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: const Text('Answer font size'),
                  trailing: Text('${s.fontSize.round()}', style: TextStyle(color: pal.dim, fontWeight: FontWeight.w700)),
                  subtitle: Slider(value: s.fontSize.clamp(14.0, 22.0), min: 14, max: 22, divisions: 8, onChanged: s.setFontSize),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text('This is how AI answers will look.', style: TextStyle(color: pal.text, fontSize: s.fontSize, height: 1.5)),
                ),
              ]),

              const _Label('Chat'),
              _Group(children: [
                SwitchListTile(
                  secondary: const Icon(Icons.public_rounded),
                  title: const Text('Web search by default'),
                  subtitle: const Text('Look up current facts for new questions'),
                  value: s.searchDefault,
                  onChanged: s.setSearchDefault,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.psychology_alt_outlined),
                  title: const Text('DeepThink by default'),
                  subtitle: const Text('Reason step by step before answering'),
                  value: s.thinkDefault,
                  onChanged: s.setThinkDefault,
                ),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Answer language'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(s.language, style: TextStyle(color: pal.dim)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: pal.dim),
                  ]),
                  onTap: () => _pickLanguage(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_rounded),
                  title: const Text('Haptic feedback'),
                  value: s.haptics,
                  onChanged: s.setHaptics,
                ),
              ]),

              const _Label('Data & privacy'),
              _Group(children: [
                ListTile(
                  leading: Icon(Icons.delete_sweep_rounded, color: cs.error),
                  title: Text('Clear all chats', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Deletes history stored on this device'),
                  onTap: () => _clearChats(context),
                ),
              ]),

              const _Label('Support & about'),
              _Group(children: [
                ListTile(
                  leading: const Icon(Icons.system_update_rounded),
                  title: const Text('Check for updates'),
                  trailing: Icon(Icons.chevron_right_rounded, color: pal.dim),
                  onTap: () => _checkUpdates(context),
                ),
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: const Text('Help & feedback'),
                  trailing: Icon(Icons.chevron_right_rounded, color: pal.dim),
                  onTap: () => _feedback(context),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Project on GitHub'),
                  trailing: Icon(Icons.open_in_new_rounded, size: 18, color: pal.dim),
                  onTap: () => launchUrl(Uri.parse('https://github.com/AirMuntsLTC1/CourseDeep'), mode: LaunchMode.externalApplication),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Version'),
                  trailing: Text(kAppVersion, style: TextStyle(color: pal.dim)),
                ),
              ]),

              const SizedBox(height: 18),
              _Group(children: [
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: cs.error),
                  title: Text('Log out', style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                  onTap: () => _logout(context),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();
  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _c = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Please write a few words first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final u = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('feedback').insert({'message': text, 'email': u?.email, 'app_version': kAppVersion});
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you! Your feedback was sent.')));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Help & feedback', style: TextStyle(color: pal.text, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Report a problem or tell us what to improve.', style: TextStyle(color: pal.dim)),
        const SizedBox(height: 14),
        TextField(
          controller: _c,
          maxLines: 5,
          maxLength: 2000,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Describe your experience or the error you saw…',
            filled: true,
            fillColor: pal.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: _sending ? null : _send,
          child: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)) : const Text('Send feedback'),
        ),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Theme.of(context).colorScheme.primary)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
