import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../models/project.dart';
import '../services/ai_service.dart';
import '../services/app_settings.dart';
import '../services/file_service.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import '../util/segments.dart';
import '../widgets/brand.dart';
import '../widgets/message_view.dart';
import 'webview_page.dart';

class ProjectChatPage extends StatefulWidget {
  const ProjectChatPage({super.key, required this.project});
  final Project project;
  @override
  State<ProjectChatPage> createState() => _ProjectChatPageState();
}

class _ProjectChatPageState extends State<ProjectChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  AiRequest? _req;
  Timer? _flush;
  bool _dirty = false;
  bool _busy = false;
  bool _stick = true;

  late final MessageActions _actions = MessageActions(
    openLink: _openLink,
    copy: _copy,
    regenerate: _regen,
    openImage: _openImage,
    more: _more,
    saveGenerated: _saveGen,
    shareFile: _shareFile,
    shareImage: _shareImage,
    shareZip: _shareZip,
    previewFile: _previewFile,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final d = _scroll.position.maxScrollExtent - _scroll.position.pixels;
      _stick = d < 60;
    });
  }

  @override
  void dispose() {
    _req?.cancel();
    _flush?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  void _scrollEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    haptic(HapticFeedback.selectionClick);
    _input.clear();
    final userMsg = ChatMessage(role: 'user', text: text);
    final reply = ChatMessage(role: 'assistant', streaming: true)..status = 'Thinking';
    setState(() {
      _messages.add(userMsg);
      _messages.add(reply);
      _busy = true;
    });
    _stick = true;
    _scrollEnd();

    final history = _messages.sublist(0, _messages.length - 1);
    final req = AiRequest();
    _req = req;
    _dirty = false;
    _flush?.cancel();
    _flush = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_dirty) return;
      _dirty = false;
      reply.update();
      if (_stick && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });

    String? failure;
    try {
      await for (final e in req.run(
        history,
        search: false,
        think: false,
        lang: AppSettings.I.language,
        projectContext: widget.project.systemContext,
      )) {
        switch (e.type) {
          case 'status':
            reply.status = e.text;
            break;
          case 'delta':
            reply.append(e.text);
            break;
          case 'done':
            reply.provider = e.provider;
            break;
        }
        _dirty = true;
      }
    } on AiException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = 'Something went wrong. Please try again.';
    }

    _flush?.cancel();
    _req = null;
    reply.streaming = false;
    reply.status = '';

    if (req.cancelled) {
      if (reply.text.trim().isEmpty) _messages.remove(reply);
    } else if (failure != null) {
      if (reply.text.trim().isEmpty) {
        reply.role = 'error';
        reply.text = failure;
      } else {
        reply.append('\n\n_…${failure}_');
      }
    } else if (reply.text.trim().isEmpty) {
      reply.role = 'error';
      reply.text = 'The AI returned an empty answer.';
    }

    reply.update();
    if (mounted) {
      setState(() => _busy = false);
      _scrollEnd();
      if (failure == null && reply.text.trim().isNotEmpty) {
        VoiceService.I.speak(plainText(reply.text));
      }
    }
  }

  void _stop() {
    haptic(HapticFeedback.mediumImpact);
    VoiceService.I.stop();
    _req?.cancel();
  }

  void _regen() {
    if (_busy || _messages.isEmpty) return;
    if (_messages.last.role != 'user') _messages.removeLast();
    final last = _messages.isNotEmpty && _messages.last.role == 'user' ? _messages.removeLast() : null;
    if (last == null) return;
    _input.text = last.text;
    _send();
  }

  void _openLink(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return;
    if (u.scheme == 'http' || u.scheme == 'https' || u.scheme.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebViewPage(url: url)));
    } else {
      launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false);
    }
  }

  void _copy(String t) {
    Clipboard.setData(ClipboardData(text: t));
    _toast('Copied');
  }

  void _openImage(String path) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
        body: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(child: InteractiveViewer(maxScale: 5, child: Image.file(File(path)))),
        ),
      ),
    ));
  }

  void _more(ChatMessage m) {
    final text = m.isUser ? m.text : plainText(m.text);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.content_copy_rounded),
            title: const Text('Copy'),
            onTap: () {
              Navigator.pop(ctx);
              _copy(text);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _saveGen(Attachment a) async {
    try {
      final where = await FileService.saveGeneratedImage(a.path!, a.name);
      _toast('Saved to $where');
    } catch (_) {
      _toast('Could not save the image.');
    }
  }

  Future<void> _shareFile(FileSeg f) async {
    try {
      final where = await FileService.saveFile(f);
      _toast('Saved to $where');
    } catch (_) {
      _toast('Could not save the file.');
    }
  }

  Future<void> _shareImage(ImageSeg img) async {
    try {
      final where = await FileService.saveImage(img);
      _toast('Saved to $where');
    } catch (_) {
      _toast('Could not save the image.');
    }
  }

  Future<void> _shareZip(List<FileSeg> files) async {
    try {
      final where = await FileService.saveZip(files);
      _toast('Saved to $where');
    } catch (_) {
      _toast('Could not create the ZIP.');
    }
  }

  void _previewFile(FileSeg f) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Text(f.name, style: TextStyle(color: Pal.of(context).text, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SelectableText(f.content,
                style: TextStyle(color: Pal.of(context).text, fontFamily: 'monospace', fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            widget.project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: pal.text, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Row(children: [
            Icon(Icons.folder_rounded, size: 11, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              widget.project.isPublic ? 'Public project' : 'Private project',
              style: TextStyle(color: pal.dim, fontSize: 11.5),
            ),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            icon: Icon(Icons.refresh_rounded, color: pal.text),
            onPressed: () {
              if (_busy) return;
              setState(() => _messages.clear());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (widget.project.description.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: pal.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.border),
              ),
              child: Text(
                widget.project.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pal.dim, fontSize: 12.5, height: 1.4),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _Empty(pal: pal, cs: cs, project: widget.project)
                : ListView.builder(
                    controller: _scroll,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => MessageView(
                      key: ValueKey(_messages[i].id),
                      msg: _messages[i],
                      isLast: i == _messages.length - 1,
                      actions: _actions,
                      fontSize: AppSettings.I.fontSize,
                    ),
                  ),
          ),
          _composer(pal, cs),
        ]),
      ),
    );
  }

  Widget _composer(Pal pal, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: pal.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              style: TextStyle(color: pal.text, fontSize: 16, height: 1.4),
              decoration: InputDecoration(
                hintText: 'Ask about your project…',
                hintStyle: TextStyle(color: pal.dim.withValues(alpha: 0.8)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2, right: 2),
          child: GestureDetector(
            onTap: _busy ? _stop : _send,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: _busy ? null : Brand.gradient,
                color: _busy ? pal.text : null,
                shape: BoxShape.circle,
              ),
              child: Icon(_busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  color: _busy ? pal.bg : Colors.white, size: 22),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.pal, required this.cs, required this.project});
  final Pal pal;
  final ColorScheme cs;
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AiOrb(size: 64),
          const SizedBox(height: 8),
          Text(
            'Project room',
            style: TextStyle(color: pal.text, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask CourseDeep to build, fix or improve ${project.name}. It stays focused on this project only.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.dim, fontSize: 13.5, height: 1.5),
          ),
        ]),
      ),
    );
  }
}
