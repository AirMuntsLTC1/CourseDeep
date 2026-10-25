
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/app_settings.dart';
import '../services/chat_store.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import '../widgets/home_view.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../theme/app_theme.dart';
import '../util/segments.dart';
import '../widgets/brand.dart';
import '../widgets/composer.dart';
import '../widgets/message_view.dart';
import 'webview_page.dart';
import 'settings_page.dart';
import 'projects_page.dart';

const int _kMaxAttachments = 6;

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _store = ChatStore();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _showJump = ValueNotifier<bool>(false);

  List<ChatSession> _sessions = [];
  ChatSession? _current;
  bool _loaded = false;
  bool _busy = false;
  bool _search = AppSettings.I.searchDefault;
  bool _think = AppSettings.I.thinkDefault;
  bool _stick = true; // auto-scroll only while the user is at the bottom
  final List<Attachment> _pending = [];

  AiRequest? _req;
  Timer? _flush;
  bool _dirty = false;

  late final MessageActions _actions = MessageActions(
    openLink: _openLink,
    copy: _copy,
    regenerate: _regenerate,
    openImage: _openImage,
    more: _moreSheet,
    saveGenerated: _saveGenerated,
    shareFile: _shareFile,
    shareImage: _shareImage,
    shareZip: _shareZip,
    previewFile: _previewFile,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    AppSettings.I.addListener(_onSettings);
    _load();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  String get _userName {
    final e = Supabase.instance.client.auth.currentUser?.email ?? '';
    final n = e.split('@').first.replaceAll(RegExp(r'[._\-0-9]+'), ' ').trim();
    return n.isEmpty ? '' : n[0].toUpperCase() + n.substring(1).split(' ').first;
  }

  bool get _isDark => AppSettings.I.isDark(context);
  void _toggleTheme() => AppSettings.I.toggleTheme(context);

  @override
  void dispose() {
    AppSettings.I.removeListener(_onSettings);
    _req?.cancel();
    _flush?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _showJump.dispose();
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────
  Future<void> _load() async {
    List<ChatSession> list = [];
    try {
      list = await _store.load();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _current = list.isNotEmpty ? list.first : null;
      _loaded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(animate: false));
  }

  ChatSession _newSession() {
    final s = ChatSession(id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'New chat');
    _sessions.insert(0, s);
    return s;
  }

  void _newChat() {
    if (_busy) return;
    final cur = _current;
    if (cur != null && cur.messages.isEmpty) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    setState(() {
      _current = null;
      _pending.clear();
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectChat(ChatSession s) {
    setState(() => _current = s);
    _scaffoldKey.currentState?.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(animate: false));
  }

  void _deleteChat(ChatSession s) {
    if (_busy && _current == s) return;
    setState(() {
      _sessions.remove(s);
      if (_current == s) _current = _sessions.isNotEmpty ? _sessions.first : null;
    });
    _store.delete(s);
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m
        .showSnackBar(SnackBar(
          content: const Text('Chat deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() {
                _sessions.add(s);
                _sessions.sort((a, b) => b.updated.compareTo(a.updated));
                _current ??= s;
              });
              _store.save(s, now: true);
            },
          ),
        ))
        .closed
        .then((r) {
      if (r != SnackBarClosedReason.action) _store.purgeAttachments(s);
    });
  }

  // ───────────────────────── scrolling ─────────────────────────
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final d = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    // Only the USER scrolling up stops auto-follow (a big new chunk of text must not).
    if (d < 60) {
      _stick = true;
    } else if (_scroll.position.userScrollDirection == ScrollDirection.forward) {
      _stick = false;
    }
    final show = d > 360;
    if (_showJump.value != show) _showJump.value = show;
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  void _jumpIfStuck() {
    if (!_stick || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  // ───────────────────────── attachments ─────────────────────────
  void _toast(String t) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  Future<void> _attach() async {
    if (_pending.length >= _kMaxAttachments) {
      _toast('You can attach up to $_kMaxAttachments files per message.');
      return;
    }
    FocusScope.of(context).unfocus();
    final c = await showAttachSheet(context);
    if (c == null) return;
    switch (c) {
      case AttachChoice.photo:
        return _pickPhoto(ImageSource.gallery);
      case AttachChoice.camera:
        return _pickPhoto(ImageSource.camera);
      case AttachChoice.file:
        return _pickFile();
    }
  }

  Future<void> _pickPhoto(ImageSource src) async {
    XFile? x;
    try {
      x = await _picker.pickImage(source: src, maxWidth: 1600, imageQuality: 85);
    } catch (e) {
      _toast('Could not open ${src == ImageSource.camera ? 'the camera' : 'photos'}.');
      return;
    }
    if (x == null) return;
    final picked = x;
    await _processAttachment(picked.name, () => FileService.image(picked.path, picked.name), AttachKind.image);
  }

  Future<void> _pickFile() async {
    List<PlatformFile> res;
    try {
      res = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      _toast('Could not open the file picker.');
      return;
    }
    if (res.isEmpty || res.first.path == null) return;
    final f = res.first;
    await _processAttachment(f.name, () => FileService.file(f.path!, f.name), AttachKind.text);
  }

  Future<void> _processAttachment(String name, Future<Attachment> Function() job, AttachKind guess) async {
    final placeholder = Attachment(name: name, kind: guess, loading: true);
    setState(() => _pending.add(placeholder));
    try {
      final a = await job();
      if (!mounted) return;
      setState(() {
        final i = _pending.indexOf(placeholder);
        if (i >= 0) {
          _pending[i] = a;
        } else {
          _pending.add(a);
        }
      });
      if (a.kind != AttachKind.image && a.kind != AttachKind.pdf && (a.text == null || a.text!.isEmpty) && a.note != null) _toast(a.note!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        placeholder.loading = false;
        placeholder.failed = true;
        placeholder.note = e.toString();
      });
      _toast(e.toString());
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _pending.remove(placeholder));
      });
    }
  }

  // ───────────────────────── send / stream ─────────────────────────
  Future<void> _send([String? preset]) async {
    if (_busy) return;
    final text = (preset ?? _input.text).trim();
    if (_pending.any((a) => a.loading)) {
      _toast('Still reading your file…');
      return;
    }
    final atts = _pending.where((a) => !a.failed).toList();
    if (text.isEmpty && atts.isEmpty) return;

    haptic(HapticFeedback.selectionClick);
    final s = _current ?? _newSession();
    if (s.messages.isEmpty) {
      s.title = text.isNotEmpty ? (text.length > 42 ? '${text.substring(0, 42)}…' : text) : (atts.first.name);
    }
    s.messages.add(ChatMessage(role: 'user', text: text, attachments: atts));
    s.updated = DateTime.now();
    setState(() {
      _current = s;
      _pending.clear();
    });
    _input.clear();
    await _generate(s);
  }

  Future<void> _generate(ChatSession s) async {
    final reply = ChatMessage(role: 'assistant', streaming: true)..status = 'Thinking';
    final history = List<ChatMessage>.of(s.messages);
    setState(() {
      _current = s;
      s.messages.add(reply);
      _busy = true;
    });
    _stick = true;
    _scrollToEnd();

    final req = AiRequest();
    _req = req;
    _dirty = false;
    _flush?.cancel();
    _flush = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_dirty) return;
      _dirty = false;
      reply.update();
      _jumpIfStuck();
    });

    String? failure;
    try {
      await for (final e in req.run(history, search: _search, think: _think, lang: AppSettings.I.language)) {
        switch (e.type) {
          case 'status':
            reply.status = e.text;
            break;
          case 'sources':
            reply.sources = e.sources;
            break;
          case 'delta':
            reply.append(e.text);
            break;
          case 'image':
            try {
              final bytes = base64Decode(e.data);
              final f = await FileService.storeImageBytes(bytes, e.name);
              reply.attachments.add(Attachment(name: e.name, kind: AttachKind.image, mime: DownloadService.mimeOf(e.name), path: f.path, size: bytes.length));
            } catch (_) {}
            break;
          case 'done':
            reply.provider = e.provider;
            break;
        }
        _dirty = true;
      }
    } on AiException catch (e) {
      failure = e.message;
    } catch (e) {
      failure = 'Something went wrong. Please try again.';
    }

    _flush?.cancel();
    _req = null;
    reply.streaming = false;
    reply.status = '';

    if (req.cancelled) {
      if (reply.text.trim().isEmpty) s.messages.remove(reply);
    } else if (failure != null) {
      if (reply.text.trim().isEmpty) {
        reply.role = 'error';
        reply.text = failure;
      } else {
        reply.append('\n\n_…${failure}_');
      }
    } else if (reply.text.trim().isEmpty) {
      reply.role = 'error';
      reply.text = 'The AI returned an empty answer. Please try again.';
    }

    reply.update();
    s.updated = DateTime.now();
    _sessions.sort((a, b) => b.updated.compareTo(a.updated));
    _store.save(s);
    if (mounted) {
      setState(() => _busy = false);
      _jumpIfStuck();
      haptic(HapticFeedback.lightImpact);
    }
  }

  void _stop() {
    haptic(HapticFeedback.mediumImpact);
    _req?.cancel();
  }

  void _regenerate() {
    final s = _current;
    if (s == null || _busy || s.messages.isEmpty) return;
    final last = s.messages.last;
    if (!last.isUser) s.messages.removeLast();
    if (s.messages.isEmpty || !s.messages.last.isUser) return;
    _generate(s);
  }

  // ───────────────────────── actions ─────────────────────────
  void _openLink(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return;
    if (u.scheme == 'http' || u.scheme == 'https' || u.scheme.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebViewPage(url: url)));
    } else {
      launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) {
        _toast('Could not open this link');
        return false;
      });
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    haptic(HapticFeedback.lightImpact);
    _toast('Copied');
  }

  void _openImage(String path) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, a, __) => FadeTransition(
        opacity: a,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: Hero(tag: path, child: InteractiveViewer(maxScale: 5, child: Image.file(File(path)))),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _shareImage(ImageSeg img) async {
    try {
      final where = await FileService.saveImage(img);
      _toast('Saved to $where');
    } catch (e) {
      _toast('Could not save image.');
    }
  }


  Future<void> _saveGenerated(Attachment a) async {
    try {
      final where = await FileService.saveGeneratedImage(a.path!, a.name);
      _toast('Saved to $where');
    } catch (e) {
      _toast('Could not save the image.');
    }
  }

  Future<void> _shareFile(FileSeg f) async {
    try {
      final where = await FileService.saveFile(f);
      _toast('Saved to $where');
    } catch (e) {
      _toast('Could not share this file.');
    }
  }

  Future<void> _shareZip(List<FileSeg> files) async {
    try {
      final where = await FileService.saveZip(files);
      _toast('Saved to $where');
    } catch (e) {
      _toast('Could not create the ZIP.');
    }
  }

  void _previewFile(FileSeg f) {
    final pal = Pal.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
          Text(f.name, style: TextStyle(color: pal.text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SelectableText(f.content, style: TextStyle(color: pal.text, fontFamily: 'monospace', fontSize: 13, height: 1.5)),
        ]),
      ),
    );
  }

  void _moreSheet(ChatMessage m) {
    final pal = Pal.of(context);
    final text = m.isUser ? m.text : plainText(m.text);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.content_copy_rounded, color: pal.text),
            title: const Text('Copy'),
            onTap: () {
              Navigator.pop(ctx);
              _copy(text);
            },
          ),
          ListTile(
            leading: Icon(Icons.text_fields_rounded, color: pal.text),
            title: const Text('Select text'),
            onTap: () {
              Navigator.pop(ctx);
              _selectText(text);
            },
          ),
          if (!m.isUser && m.sources.isNotEmpty)
            ListTile(
              leading: Icon(Icons.travel_explore_rounded, color: pal.text),
              title: Text('Open first source (${m.sources.first.host})'),
              onTap: () {
                Navigator.pop(ctx);
                _openLink(m.sources.first.url);
              },
            ),
        ]),
      ),
    );
  }

  void _selectText(String text) {
    final pal = Pal.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
          SelectableText(text, style: TextStyle(color: pal.text, fontSize: 16, height: 1.55)),
        ]),
      ),
    );
  }


  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          onChatsCleared: () {
            if (!mounted) return;
            setState(() {
              _sessions.clear();
              _current = null;
              _pending.clear();
            });
          },
        ),
      ),
    );
  }

  // ───────────────────────── build ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final messages = _current?.messages ?? const <ChatMessage>[];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (pal.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: pal.bg,
        systemNavigationBarIconBrightness: pal.isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: pal.bg,
        drawer: _buildDrawer(pal),
        body: SafeArea(
          child: Column(children: [
            _buildHeader(pal),
            Expanded(
              child: !_loaded
                  ? const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)))
                  : messages.isEmpty
                      ? HomeView(onPick: _send, name: _userName)
                      : Stack(children: [
                          ListView.builder(
                            controller: _scroll,
                            physics: const ClampingScrollPhysics(),
                            addAutomaticKeepAlives: false,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: messages.length,
                            itemBuilder: (_, i) => MessageView(
                              key: ValueKey(messages[i].id),
                              msg: messages[i],
                              isLast: i == messages.length - 1,
                              actions: _actions,
                              fontSize: AppSettings.I.fontSize,
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: _showJump,
                                builder: (_, show, __) => AnimatedScale(
                                  scale: show ? 1 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Material(
                                    color: pal.surface2,
                                    shape: CircleBorder(side: BorderSide(color: pal.border)),
                                    elevation: 3,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        _stick = true;
                                        _scrollToEnd();
                                      },
                                      child: Padding(padding: const EdgeInsets.all(9), child: Icon(Icons.arrow_downward_rounded, size: 20, color: pal.text)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
            ),
            Composer(
              controller: _input,
              focus: _focus,
              busy: _busy,
              attachments: _pending,
              searchOn: _search,
              thinkOn: _think,
              onToggleSearch: () => setState(() => _search = !_search),
              onToggleThink: () => setState(() => _think = !_think),
              onAttach: _attach,
              onSend: () => _send(),
              onStop: _stop,
              onRemove: (a) => setState(() => _pending.remove(a)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(Pal pal) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Row(children: [
        IconButton(icon: Icon(Icons.menu_rounded, color: pal.text), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
        const AiMark(size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            (_current == null || _current!.messages.isEmpty) ? 'CourseDeep' : _current!.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: pal.text, fontSize: 17.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
        ),
        IconButton(tooltip: 'New chat', icon: Icon(Icons.add_comment_outlined, color: pal.text, size: 22), onPressed: _newChat),
        IconButton(
          tooltip: 'Theme',
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => RotationTransition(turns: a, child: FadeTransition(opacity: a, child: c)),
            child: Icon(_isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, key: ValueKey(_isDark), color: pal.text, size: 22),
          ),
          onPressed: _toggleTheme,
        ),
      ]),
    );
  }

  String _group(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 8) return 'Previous 7 days';
    return 'Older';
  }

  Widget _buildDrawer(Pal pal) {
    final cs = Theme.of(context).colorScheme;
    final items = <Object>[];
    String? last;
    for (final s in _sessions) {
      if (s.messages.isEmpty) continue;
      final g = _group(s.updated);
      if (g != last) {
        items.add(g);
        last = g;
      }
      items.add(s);
    }
    return Drawer(
      width: 310,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: cs.primary,
                child: Text(
                  (Supabase.instance.client.auth.currentUser?.email ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  Supabase.instance.client.auth.currentUser?.email ?? 'User',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.text, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Log Out',
                icon: Icon(Icons.logout_rounded, color: pal.dim, size: 20),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsPage()));
              },
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: pal.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: pal.border),
                ),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(Icons.folder_special_rounded, color: pal.text, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Projects',
                        style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 14.5)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: pal.dim, size: 20),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: _newChat,
              child: Container(
                height: 48,
                decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_rounded, color: Colors.white),
                  SizedBox(width: 6),
                  Text('New chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('No chats yet', style: TextStyle(color: pal.dim)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      if (it is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                          child: Text(it, style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        );
                      }
                      final s = it as ChatSession;
                      final sel = s == _current;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: sel ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _selectChat(s),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
                              child: Row(children: [
                                Expanded(
                                  child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 14.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.delete_outline_rounded, size: 19, color: pal.dim),
                                  onPressed: () => _deleteChat(s),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: pal.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(_isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: pal.text),
                    title: Text(_isDark ? 'Light mode' : 'Dark mode', style: TextStyle(color: pal.text)),
                    onTap: _toggleTheme,
                  ),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: Icon(Icons.settings_outlined, color: pal.text),
                  onPressed: () {
                    Navigator.pop(context); // Close drawer first
                    _openSettings();
                  },
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
