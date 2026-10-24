import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/chat_store.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.isDark, required this.onToggleTheme});
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _store = ChatStore();
  final _ai = AiService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<ChatSession> _sessions = [];
  ChatSession? _current;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sessions = await _store.load();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _current = sessions.isNotEmpty ? sessions.first : null;
      _loaded = true;
    });
  }

  ChatSession _createSession() {
    final s = ChatSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'New chat',
    );
    _sessions.insert(0, s);
    return s;
  }

  void _newChat() {
    setState(() => _current = _createSession());
    _persist();
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectChat(ChatSession s) {
    setState(() => _current = s);
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _deleteChat(ChatSession s) {
    setState(() {
      _sessions.remove(s);
      if (_current == s) {
        _current = _sessions.isNotEmpty ? _sessions.first : null;
      }
    });
    _persist();
  }

  Future<void> _persist() => _store.save(_sessions);

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;

    final s = _current ?? _createSession();
    setState(() {
      _current = s;
      if (s.messages.isEmpty) {
        s.title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      }
      s.messages.add(ChatMessage(role: 'user', text: text));
      s.updated = DateTime.now();
      _busy = true;
    });
    _input.clear();
    _scrollToEnd();

    ChatMessage reply;
    try {
      final result = await _ai.send(s.messages);
      reply = ChatMessage(
        role: 'assistant',
        text: result['reply'],
        sources: (result['sources'] as List)
            .map((e) => Source.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } on AiException catch (e) {
      reply = ChatMessage(role: 'error', text: e.message);
    } catch (e) {
      reply = ChatMessage(role: 'error', text: 'Unexpected error: $e');
    }

    if (!mounted) return;
    setState(() {
      s.messages.add(reply);
      s.updated = DateTime.now();
      _busy = false;
    });
    _sessions.sort((a, b) => b.updated.compareTo(a.updated));
    _persist();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied to clipboard'),
      duration: Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final messages = _current?.messages ?? const <ChatMessage>[];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(cs),
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.auto_awesome, color: cs.primary),
          const SizedBox(width: 8),
          const Text('CourseDeep',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        ]),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(widget.isDark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? _EmptyState(onPick: (t) => _send(t))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _Bubble(
                          msg: messages[i],
                          onCopy: () => _copy(messages[i].text),
                        ),
                      ),
          ),
          if (_busy) const _Thinking(),
          _InputBar(
            controller: _input,
            busy: _busy,
            onSend: () => _send(),
          ),
        ]),
      ),
    );
  }

  Widget _buildDrawer(ColorScheme cs) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [
                Icon(Icons.auto_awesome, color: cs.primary),
                const SizedBox(width: 8),
                const Text('CourseDeep',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add),
                label: const Text('New chat'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _sessions.isEmpty
                  ? Center(
                      child: Text('No chats yet',
                          style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (_, i) {
                        final s = _sessions[i];
                        return ListTile(
                          selected: s == _current,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(s.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: 'Delete chat',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteChat(s),
                          ),
                          onTap: () => _selectChat(s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.onCopy});
  final ChatMessage msg;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.isUser;
    final isErr = msg.isError;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Source Chips (Only show if there are sources and it's not a user message)
          if (!isUser && msg.sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: msg.sources.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final source = msg.sources[i];
                    final domain = Uri.tryParse(source.url)?.host ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          if (domain.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                'https://www.google.com/s2/favicons?domain=$domain&sz=32',
                                width: 16,
                                height: 16,
                                errorBuilder: (_, __, ___) => Icon(Icons.language, size: 16, color: cs.primary),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            domain.replaceAll('www.', ''),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

          // Message Text
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isErr ? cs.error : cs.primary,
                  child: Icon(
                    isErr ? Icons.error_outline : Icons.auto_awesome,
                    size: 16,
                    color: isErr ? cs.onError : cs.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (isUser)
                      // User message gets a very subtle background block, not a bubble
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(msg.text, style: TextStyle(color: cs.onSurface, height: 1.4, fontSize: 15)),
                      )
                    else
                      // AI message is flat text (like ChatGPT/Perplexity)
                      MarkdownBody(
                        data: msg.text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: cs.onSurface, height: 1.5, fontSize: 15),
                          code: TextStyle(backgroundColor: cs.surface, color: cs.primary, fontFamily: 'monospace'),
                          codeblockDecoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                        ),
                      ),
                    
                    // Copy button for AI
                    if (!isUser && !isErr)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          tooltip: 'Copy',
                          onPressed: onCopy,
                          icon: Icon(Icons.copy_rounded, color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});
  final ValueChanged<String> onPick;

  static const _suggestions = [
    'Explain photosynthesis simply',
    'Help me make a study schedule',
    'Write a short poem about the ocean',
    'Summarize the causes of World War I',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            Text("Hi, I'm CourseDeep",
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Ask me anything: study help, writing, ideas, or code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in _suggestions)
                  ActionChip(label: Text(s), onPressed: () => onPick(s)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Text('CourseDeep is thinking…',
            style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ask CourseDeep...',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ]),
      ),
    );
  }
}
