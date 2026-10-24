import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/chat_store.dart';
import 'webview_page.dart';

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
  final _picker = ImagePicker();

  List<ChatSession> _sessions = [];
  ChatSession? _current;
  bool _busy = false;
  bool _loaded = false;
  String? _selectedImageBase64;

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
    final s = ChatSession(id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'New chat');
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
      if (_current == s) _current = _sessions.isNotEmpty ? _sessions.first : null;
    });
    _persist();
  }

  Future<void> _persist() => _store.save(_sessions);


  String? _attachedFileName;
  String? _attachedFileText;

  bool _isTextFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['txt', 'md', 'dart', 'py', 'js', 'html', 'css', 'json', 'csv', 'cpp', 'c', 'java', 'ts', 'rs', 'go', 'php', 'sh', 'yaml', 'yml', 'xml'].contains(ext);
  }

  Future<void> _pickFile() async {
    final List<PlatformFile> result = await FilePicker.pickFiles(type: FileType.any);
    if (result.isNotEmpty && result.first.path != null) {
      final file = File(result.first.path!);
      final fileName = result.first.name;

      if (fileName.toLowerCase().endsWith('.zip')) {
        // Extract text from ZIP files
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final buffer = StringBuffer();
        buffer.writeln("[ZIP File Contents: $fileName]");
        int count = 0;
        for (final entry in archive.files) {
          if (entry.isFile && _isTextFile(entry.name)) {
            try {
              final content = utf8.decode(entry.content);
              buffer.writeln("\n--- File: ${entry.name} ---\n$content\n");
              count++;
            } catch (_) {}
          }
        }
        if (count == 0) buffer.writeln("No readable text/code files found in this ZIP.");
        
        setState(() {
          _attachedFileName = fileName;
          _attachedFileText = buffer.toString();
        });
      } else if (_isTextFile(fileName)) {
        // Read standard text files
        final text = await file.readAsString();
        setState(() {
          _attachedFileName = fileName;
          _attachedFileText = text;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Only text/code or ZIP files are supported. Use the image button for photos.')),
          );
        }
      }
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _selectedImageBase64 = base64Encode(bytes));
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if ((text.isEmpty && _selectedImageBase64 == null) || _busy) return;

    final s = _current ?? _createSession();
    final currentImage = _selectedImageBase64;
    final currentFileText = _attachedFileText;
    
    // Combine typed text with the file content
    String finalText = text;
    if (currentFileText != null) {
      finalText = "$text\n\n[Attached File: $_attachedFileName]\n$currentFileText";
    }

    setState(() {
      _current = s;
      if (s.messages.isEmpty) s.title = text.isNotEmpty ? (text.length > 40 ? '${text.substring(0, 40)}…' : text) : 'Image Analysis';
      s.messages.add(ChatMessage(role: 'user', text: finalText, imageBase64: currentImage));
      s.updated = DateTime.now();
      _busy = true;
      _selectedImageBase64 = null; // Clear image preview
      _attachedFileName = null;
      _attachedFileText = null;
    });
    
    _input.clear();
    _scrollToEnd();

    ChatMessage reply;
    try {
      final result = await _ai.send(s.messages);
      reply = ChatMessage(
        role: 'assistant',
        text: result['reply'],
        sources: (result['sources'] as List).map((e) => Source.fromJson(Map<String, dynamic>.from(e))).toList(),
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
        _scroll.animateTo(_scroll.position.maxScrollExtent + 120, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      }
    });
  }

  void _openLink(String url) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewPage(url: url, title: 'CourseDeep Source')));
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1C1C1A) : const Color(0xFFFBFBF9);
    final cs = Theme.of(context).colorScheme;
    final messages = _current?.messages ?? const <ChatMessage>[];

    return Scaffold(
      backgroundColor: bgColor,
      key: _scaffoldKey,
      drawer: _buildDrawer(cs),
      appBar: AppBar(
        backgroundColor: bgColor,
        title: Row(children: [
          Icon(Icons.auto_awesome, color: cs.primary, size: 20),
          const SizedBox(width: 8),
          const Text('CourseDeep', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.add_comment_outlined, size: 20), onPressed: _newChat),
          IconButton(icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20), onPressed: widget.onToggleTheme),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: messages.length,
                        scrollCacheExtent: 1000, // Improves scrolling performance
                        itemBuilder: (_, i) => RepaintBoundary(
                          child: _MessageRow(msg: messages[i], onCopy: () => _copy(messages[i].text), onOpenLink: _openLink),
                        ),
                      ),
          ),
          if (_busy) const _ThinkingPill(),
          
          // File Attachment Chip
          if (_attachedFileName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.insert_drive_file, size: 16),
                label: Text(_attachedFileName!, style: const TextStyle(fontSize: 12)),
                onDeleted: () => setState(() {
                  _attachedFileName = null;
                  _attachedFileText = null;
                }),
              ),
            ),

          // Image Preview Area
          if (_selectedImageBase64 != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(base64Decode(_selectedImageBase64!), width: 60, height: 60, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 0, right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedImageBase64 = null),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          _InputBar(
            controller: _input,
            busy: _busy,
            onSend: () => _send(),
            onPickImage: _pickImage,
            onPickFile: _pickFile,
            hasImage: _selectedImageBase64 != null,
            hasFile: _attachedFileName != null,
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
                const Text('CourseDeep', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.add), label: const Text('New chat')),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _sessions.isEmpty
                  ? Center(child: Text('No chats yet', style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (_, i) {
                        final s = _sessions[i];
                        return ListTile(
                          selected: s == _current,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: const Icon(Icons.chat_bubble_outline, size: 18),
                          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteChat(s)),
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

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.msg, required this.onCopy, required this.onOpenLink});
  final ChatMessage msg;
  final VoidCallback onCopy;
  final Function(String) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.isUser;
    final isErr = msg.isError;
    const aiFontSize = 17.0;
    const userFontSize = 16.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 28, height: 28,
              decoration: BoxDecoration(color: isErr ? cs.error : cs.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(isErr ? Icons.error_outline : Icons.auto_awesome, size: 16, color: isErr ? cs.onError : cs.primary),
            ),
            const SizedBox(width: 16),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (isUser)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (msg.imageBase64 != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(base64Decode(msg.imageBase64!), width: 200),
                            ),
                          ),
                        if (msg.text.isNotEmpty)
                          Text(msg.text, style: TextStyle(color: cs.onSurface, fontSize: userFontSize, height: 1.4)),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.sources.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Wrap(
                            spacing: 8, runSpacing: 8,
                            children: msg.sources.map((source) {
                              final domain = Uri.tryParse(source.url)?.host.replaceAll('www.', '') ?? 'Source';
                              return InkWell(
                                onTap: () => onOpenLink(source.url),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(2), child: Image.network('https://www.google.com/s2/favicons?domain=$domain&sz=32', width: 14, height: 14, errorBuilder: (_, __, ___) => Icon(Icons.language, size: 14, color: cs.primary))),
                                      const SizedBox(width: 6),
                                      Text(domain, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      MarkdownBody(
                        data: msg.text,
                        selectable: true,
                        onTapLink: (text, href, title) { if (href != null) onOpenLink(href); },
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: cs.onSurface, height: 1.6, fontSize: aiFontSize, letterSpacing: 0.1),
                          h1: TextStyle(color: cs.onSurface, fontSize: aiFontSize + 6, fontWeight: FontWeight.bold),
                          h2: TextStyle(color: cs.onSurface, fontSize: aiFontSize + 4, fontWeight: FontWeight.bold),
                          h3: TextStyle(color: cs.onSurface, fontSize: aiFontSize + 2, fontWeight: FontWeight.bold),
                          listBullet: TextStyle(color: cs.onSurface, fontSize: aiFontSize),
                          a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
                          code: TextStyle(backgroundColor: cs.surfaceContainerHighest, color: cs.primary, fontFamily: 'monospace', fontSize: aiFontSize - 2),
                          codeblockDecoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                          blockquoteDecoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.3), border: Border(left: BorderSide(color: cs.primary, width: 4))),
                        ),
                      ),
                      if (!isErr)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: onCopy,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy, size: 14, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text('Copy', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingPill extends StatelessWidget {
  const _ThinkingPill();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 16, top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
              const SizedBox(width: 10),
              Text('CourseDeep is thinking...', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});
  final ValueChanged<String> onPick;

  static const _suggestions = ['Explain photosynthesis simply', 'Help me make a study schedule', 'Write a short poem about the ocean', 'Summarize the causes of World War I'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome, color: cs.primary, size: 32),
            ),
            const SizedBox(height: 20),
            Text("How can I help you today?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 13)),
                    backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onPressed: () => onPick(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.busy, required this.onSend, required this.onPickImage, required this.onPickFile, required this.hasImage, required this.hasFile});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final bool hasImage;
  final bool hasFile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.add_photo_alternate_outlined, color: hasImage ? cs.primary : cs.onSurfaceVariant),
            onPressed: onPickImage,
          ),
          IconButton(
            icon: Icon(Icons.attach_file, color: hasFile ? cs.primary : cs.onSurfaceVariant),
            onPressed: onPickFile,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1, maxLines: 5,
              style: const TextStyle(fontSize: 16),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: hasImage ? 'Ask about this image...' : 'Reply to CourseDeep...',
                hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                border: InputBorder.none, isDense: true,
              ),
            ),
          ),
          IconButton(
            onPressed: busy ? null : onSend,
            icon: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: busy ? cs.surfaceContainerHighest : cs.primary, shape: BoxShape.circle),
              child: Icon(Icons.arrow_upward, size: 18, color: busy ? cs.onSurfaceVariant : cs.onPrimary),
            ),
          ),
        ]),
      ),
    );
  }
}
