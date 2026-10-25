import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import '../services/chat_store.dart';
import '../services/ai_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.fontSize,
    required this.onFontSizeChanged,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _language = 'English';
  final _store = ChatStore();
  final _feedbackController = TextEditingController();
  bool _sendingFeedback = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _language = p.getString('app_language') ?? 'English');
    }
  }

  Future<void> _setLanguage(String lang) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('app_language', lang);
    if (mounted) setState(() => _language = lang);
  }

  Future<void> _clearChats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear all chats?'),
        content: const Text('This will permanently delete all your chat history and files. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All chats cleared')));
      }
    }
  }

  void _showLanguagePicker() {
    final langs = ['English', 'Spanish', 'French', 'German', 'Chinese', 'Japanese', 'Arabic', 'Tagalog'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: langs.length,
                itemBuilder: (_, i) {
                  final l = langs[i];
                  return ListTile(
                    title: Text(l),
                    trailing: _language == l ? const Icon(Icons.check_circle, color: Colors.green) : null,
                    onTap: () {
                      _setLanguage(l);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _checkForUpdates() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Update Available'),
        content: const Text('A new version of CourseDeep is available on GitHub. Would you like to download it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              launchUrl(Uri.parse('https://github.com/AirMuntsLTC1/CourseDeep/releases'), mode: LaunchMode.externalApplication);
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final text = _feedbackController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingFeedback = true);
    try {
      // Send to AI as a feedback message
      final req = AiRequest();
      final messages = <ChatMessage>[]; // No history needed for feedback
      await for (final event in req.run(messages, search: false)) {
        if (event.type == 'error') throw Exception('Failed');
      }
      if (mounted) {
        Navigator.pop(context); // Close dialog
        _feedbackController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for your feedback!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send feedback. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _sendingFeedback = false);
    }
  }

  void _showFeedbackDialog() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Help & Feedback'),
        content: TextField(
          controller: _feedbackController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Describe your experience or report an error...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: _sendingFeedback ? null : () {
              Navigator.pop(c);
              _sendFeedback();
            },
            child: _sendingFeedback ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'User';

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- ACCOUNT ---
          const _SectionLabel('Account'),
          _SettingsGroup(children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primary,
                child: Text(email[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Signed in via Email'),
            ),
          ]),

          // --- APPEARANCE ---
          const _SectionLabel('Appearance'),
          _SettingsGroup(children: [
            ListTile(
              leading: Icon(widget.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
              title: const Text('Dark Mode'),
              trailing: Switch(
                value: widget.isDark,
                onChanged: (_) => widget.onToggleTheme(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('AI Response Font Size'),
              subtitle: Slider(
                value: widget.fontSize,
                min: 14.0,
                max: 22.0,
                divisions: 8,
                label: widget.fontSize.round().toString(),
                onChanged: widget.onFontSizeChanged,
              ),
            ),
          ]),

          // --- PREFERENCES ---
          const _SectionLabel('Preferences'),
          _SettingsGroup(children: [
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('Language'),
              trailing: Text(_language, style: TextStyle(color: pal.dim)),
              onTap: _showLanguagePicker,
            ),
          ]),

          // --- DATA & PRIVACY ---
          const _SectionLabel('Data & Privacy'),
          _SettingsGroup(children: [
            ListTile(
              leading: Icon(Icons.cleaning_services_rounded, color: cs.error),
              title: Text('Clear All Chats', style: TextStyle(color: cs.error)),
              onTap: _clearChats,
            ),
          ]),

          // --- SUPPORT & ABOUT ---
          const _SectionLabel('Support & About'),
          _SettingsGroup(children: [
            ListTile(
              leading: const Icon(Icons.system_update_rounded),
              title: const Text('Check for Updates'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _checkForUpdates,
            ),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('Help & Feedback'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _showFeedbackDialog,
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Service Agreement'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => launchUrl(Uri.parse('https://github.com/AirMuntsLTC1/CourseDeep'), mode: LaunchMode.externalApplication),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Version'),
              trailing: Text('2.0.0', style: TextStyle(color: pal.dim)),
            ),
          ]),

          // --- LOGOUT ---
          const SizedBox(height: 20),
          _SettingsGroup(children: [
            ListTile(
              leading: Icon(Icons.logout_rounded, color: cs.error),
              title: Text('Log Out Completely', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
              onTap: () async {
                await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
                try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
              },
            ),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border),
      ),
      child: Column(
        children: children.map((c) => c is ListTile ? c : ListTile(title: c)).toList(),
      ),
    );
  }
}
