import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/chat_message.dart';
import '../services/file_service.dart';
import '../theme/app_theme.dart';
import '../util/segments.dart';
import 'brand.dart';

class MessageActions {
  MessageActions({
    required this.openLink,
    required this.copy,
    required this.regenerate,
    required this.openImage,
    required this.more,
    required this.shareFile,
    required this.shareImage,
    required this.shareZip,
    required this.previewFile,
  });
  final void Function(String url) openLink;
  final void Function(String text) copy;
  final VoidCallback regenerate;
  final void Function(String path) openImage;
  final void Function(ChatMessage m) more;
  final void Function(FileSeg f) shareFile;
  final void Function(ImageSeg img) shareImage;
  final void Function(List<FileSeg> files) shareZip;
  final void Function(FileSeg f) previewFile;
}

String plainText(String raw) => parseSegments(raw).whereType<TextSeg>().map((t) => t.text.trim()).where((t) => t.isNotEmpty).join('\n\n');

IconData iconFor(String name, {AttachKind? kind}) {
  final e = extOf(name);
  if (kind == AttachKind.pdf || e == 'pdf') return Icons.picture_as_pdf_rounded;
  if (kind == AttachKind.archive || e == 'zip') return Icons.folder_zip_rounded;
  if (kind == AttachKind.document || ['docx', 'doc', 'xlsx', 'pptx'].contains(e)) return Icons.description_rounded;
  if (['csv', 'tsv'].contains(e)) return Icons.table_chart_rounded;
  if (['json', 'yaml', 'yml', 'xml', 'toml'].contains(e)) return Icons.data_object_rounded;
  if (['html', 'css', 'js', 'ts', 'dart', 'py', 'java', 'kt', 'cpp', 'c', 'h', 'php', 'go', 'rs', 'sh', 'sql', 'jsx', 'tsx'].contains(e)) return Icons.terminal_rounded;
  if (e == 'svg') return Icons.image_rounded;
  return Icons.insert_drive_file_rounded;
}

// Helper for polished gradient icons
(List<Color>, Color) _getFileStyle(String name, BuildContext context) {
  final e = extOf(name);
  final cs = Theme.of(context).colorScheme;
  
  if (e == 'zip' || e == 'rar' || e == 'tar') {
    return ([const Color(0xFFFF9A44), const Color(0xFFFF6B6B)], Colors.white);
  }
  if (['dart', 'py', 'js', 'ts', 'cpp', 'c', 'h', 'java', 'php', 'go', 'rs', 'html', 'css'].contains(e)) {
    return ([const Color(0xFF00B4DB), const Color(0xFF0083B0)], Colors.white);
  }
  if (e == 'pdf') {
    return ([const Color(0xFFFF416C), const Color(0xFFFF4B2B)], Colors.white);
  }
  if (['docx', 'doc', 'xlsx', 'pptx', 'csv'].contains(e)) {
    return ([const Color(0xFF11998E), const Color(0xFF38EF7D)], Colors.white);
  }
  return ([cs.primary, cs.tertiary], Colors.white);
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.msg, required this.isLast, required this.actions, required this.fontSize});
  final ChatMessage msg;
  final bool isLast;
  final MessageActions actions;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (msg.isUser) return _UserBubble(msg: msg, actions: actions, fontSize: fontSize);
    return ListenableBuilder(
      listenable: msg,
      builder: (_, __) => _AssistantBlock(msg: msg, isLast: isLast, actions: actions, fontSize: fontSize),
    );
  }
}

// ───────────────────────── user ─────────────────────────
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.msg, required this.actions, required this.fontSize});
  final ChatMessage msg;
  final MessageActions actions;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final images = msg.attachments.where((a) => a.kind == AttachKind.image && a.path != null).toList();
    final files = msg.attachments.where((a) => a.kind != AttachKind.image).toList();
    return Padding(
      padding: const EdgeInsets.only(left: 44, top: 10, bottom: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => actions.more(msg),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w * 0.82),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                    for (final a in images)
                      GestureDetector(
                        onTap: () => actions.openImage(a.path!),
                        child: Hero(
                          tag: a.path!,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(a.path!),
                              width: images.length == 1 ? 230 : 108,
                              height: images.length == 1 ? 230 : 108,
                              fit: BoxFit.cover,
                              cacheWidth: 500,
                              errorBuilder: (_, __, ___) => Container(
                                width: 108,
                                height: 108,
                                color: pal.surface2,
                                child: Icon(Icons.broken_image_outlined, color: pal.dim),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              for (final a in files)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: AttachmentChip(a: a)),
              if (msg.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: pal.userBubble,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      topRight: Radius.circular(22),
                      bottomLeft: Radius.circular(22),
                      bottomRight: Radius.circular(6),
                    ),
                    border: Border.all(color: pal.border),
                  ),
                  child: Text(msg.text, style: TextStyle(color: pal.text, fontSize: fontSize, height: 1.42)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class AttachmentChip extends StatelessWidget {
  const AttachmentChip({super.key, required this.a, this.onRemove});
  final Attachment a;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: a.failed ? cs.error : pal.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: a.loading
              ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(a.failed ? Icons.error_outline : iconFor(a.name, kind: a.kind), size: 18, color: a.failed ? cs.error : cs.primary),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              a.loading ? 'Reading…' : a.failed ? (a.note ?? 'Failed') : [fmtSize(a.size), if (a.note != null) a.note!].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.dim, fontSize: 11),
            ),
          ]),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          GestureDetector(onTap: onRemove, child: Icon(Icons.close_rounded, size: 18, color: pal.dim)),
        ],
      ]),
    );
  }
}

// ───────────────────────── assistant ─────────────────────────
String _linkCitations(String t, List<Source> sources) {
  if (sources.isEmpty) return t;
  return t.replaceAllMapped(RegExp(r'\[(\d{1,2})\](?!\()'), (m) {
    final i = int.parse(m.group(1)!) - 1;
    if (i < 0 || i >= sources.length || sources[i].url.isEmpty) return m.group(0)!;
    return '[${m.group(1)}](${sources[i].url})';
  });
}

MarkdownStyleSheet mdSheet(BuildContext c, Pal pal, double fontSize) {
  final cs = Theme.of(c).colorScheme;
  final fs = fontSize;
  TextStyle base({double? size, FontWeight? w}) => TextStyle(color: pal.text, fontSize: size ?? fs, height: 1.6, fontWeight: w);
  return MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
    p: base(),
    pPadding: const EdgeInsets.only(bottom: 2),
    h1: base(size: 24, w: FontWeight.w700),
    h2: base(size: 21, w: FontWeight.w700),
    h3: base(size: 18.5, w: FontWeight.w700),
    h4: base(size: 17, w: FontWeight.w700),
    strong: TextStyle(color: pal.text, fontWeight: FontWeight.w700),
    em: TextStyle(color: pal.text, fontStyle: FontStyle.italic),
    a: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
    listBullet: base(),
    listIndent: 20,
    blockSpacing: 12,
    code: TextStyle(
      color: cs.primary,
      backgroundColor: pal.codeBg,
      fontFamily: 'monospace',
      fontSize: fs - 2.5,
    ),
    blockquote: base().copyWith(color: pal.dim),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
    blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: cs.primary, width: 3))),
    tableHead: base(size: 14.5, w: FontWeight.w700),
    tableBody: base(size: 14.5),
    tableBorder: TableBorder.all(color: pal.border, width: 1, borderRadius: BorderRadius.circular(10)),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: pal.border))),
  );
}


class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({required this.msg, required this.isLast, required this.actions, required this.fontSize});
  final ChatMessage msg;
  final bool isLast;
  final MessageActions actions;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final ({String? think, String answer}) tk = msg.isError ? (think: null, answer: '') : splitThink(_linkCitations(msg.text, msg.sources));
    final segs = msg.isError ? const <Seg>[] : parseSegments(tk.answer);
    final files = segs.whereType<FileSeg>().where((f) => f.done && f.name.isNotEmpty).toList();
    final waiting = msg.streaming && msg.text.isEmpty;

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: msg.isError
              ? Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.priority_high_rounded, size: 16, color: cs.error),
                )
              : const AiMark(size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (waiting)
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 8),
                child: Row(children: [
                  const ThinkingDots(),
                  const SizedBox(width: 10),
                  Flexible(child: Text(msg.status.isEmpty ? 'Thinking' : msg.status, style: TextStyle(color: pal.dim, fontSize: 14, fontWeight: FontWeight.w500))),
                ]),
              ),
            if (msg.sources.isNotEmpty) _SourceStrip(sources: msg.sources, onOpen: actions.openLink),
            if (tk.think != null)
              ThinkBlock(text: tk.think!, streaming: msg.streaming && tk.answer.trim().isEmpty),
            if (msg.isError)
              _ErrorCard(text: msg.text, onRetry: isLast ? actions.regenerate : null)
            else
              for (final s in segs)
                if (s is TextSeg && s.text.trim().isNotEmpty)
                  MdBlocks(text: s.text.trim(), fontSize: fontSize, actions: actions)
                else if (s is FileSeg)
                  GeneratedFileCard(file: s, actions: actions)
                else if (s is ImageSeg)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s.name.endsWith('.svg'))
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: pal.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: pal.border),
                            ),
                            child: SvgPicture.string(s.content),
                          )
                        else
                          Text('Image: ${s.name}', style: TextStyle(color: pal.text)),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => actions.shareImage(s),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download Image'),
                        ),
                      ],
                    ),
                  ),
            if (files.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: FilledButton.tonalIcon(
                  onPressed: () => actions.shareZip(files),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Download all ${files.length} files as ZIP'),
                ),
              ),
            if (msg.streaming && msg.text.isNotEmpty)
              const Padding(padding: EdgeInsets.only(top: 8), child: ThinkingDots(size: 5)),
            if (!msg.streaming && !msg.isError && msg.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  _MiniBtn(icon: Icons.content_copy_rounded, tip: 'Copy', onTap: () => actions.copy(plainText(msg.text))),
                  if (isLast) _MiniBtn(icon: Icons.refresh_rounded, tip: 'Regenerate', onTap: actions.regenerate),
                  _MiniBtn(icon: Icons.more_horiz_rounded, tip: 'More', onTap: () => actions.more(msg)),
                  const Spacer(),
                  if (msg.provider != null && msg.provider!.isNotEmpty)
                    Text('via ${msg.provider}', style: TextStyle(color: pal.dim.withValues(alpha: 0.8), fontSize: 11)),
                ]),
              ),
          ]),
        ),
      ]),
    ));
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: Padding(padding: const EdgeInsets.fromLTRB(0, 6, 16, 6), child: Icon(icon, size: 18, color: Pal.of(context).dim)),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.error.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: TextStyle(color: pal.text, fontSize: 14.5, height: 1.45)),
        if (onRetry != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
          ),
      ]),
    );
  }
}

// ───────────────────────── sources ─────────────────────────
class _SourceStrip extends StatelessWidget {
  const _SourceStrip({required this.sources, required this.onOpen});
  final List<Source> sources;
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.travel_explore_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text('${sources.length} sources', style: TextStyle(color: pal.dim, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: sources.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 320 + i * 70),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child)),
              child: _SourceCard(index: i + 1, s: sources[i], onOpen: onOpen),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.index, required this.s, required this.onOpen});
  final int index;
  final Source s;
  final void Function(String url) onOpen;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final host = s.host.isEmpty ? 'source' : s.host;
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onOpen(s.url),
        child: Container(
          width: 178,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  'https://www.google.com/s2/favicons?domain=$host&sz=64',
                  width: 16,
                  height: 16,
                  errorBuilder: (_, __, ___) => Icon(Icons.public, size: 16, color: cs.primary),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.dim, fontSize: 11.5, fontWeight: FontWeight.w500))),
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: Text('$index', style: TextStyle(color: cs.primary, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 7),
            Expanded(child: Text(s.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── code blocks ─────────────────────────
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder(this.pal, this.onCopy);
  final Pal pal;
  final void Function(String) onCopy;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var lang = '';
    final kids = element.children;
    if (kids != null && kids.isNotEmpty) {
      final c = kids.first;
      if (c is md.Element) {
        final cls = c.attributes['class'];
        if (cls != null) lang = cls.replaceFirst('language-', '');
      }
    }
    return _CodeBox(lang: lang, code: element.textContent.trimRight(), pal: pal, onCopy: onCopy);
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.lang, required this.code, required this.pal, required this.onCopy});
  final String lang, code;
  final Pal pal;
  final void Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: pal.codeBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: pal.surface2.withValues(alpha: 0.8),
            border: Border(bottom: BorderSide(color: pal.border)),
          ),
          child: Row(children: [
            Icon(Icons.terminal_rounded, size: 16, color: pal.dim),
            const SizedBox(width: 8),
            Text(
              lang.isEmpty ? 'code' : lang.toUpperCase(), 
              style: TextStyle(color: pal.dim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact, 
                foregroundColor: pal.text,
                backgroundColor: pal.surface,
                side: BorderSide(color: pal.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              ),
              onPressed: () => onCopy(code),
              icon: const Icon(Icons.content_copy_rounded, size: 13),
              label: const Text('Copy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(14),
          child: Text(code, style: TextStyle(color: pal.text, fontFamily: 'monospace', fontSize: 13, height: 1.5)),
        ),
      ]),
    );
  }
}

// ───────────────────────── files created by the AI ─────────────────────────
class GeneratedFileCard extends StatelessWidget {
  const GeneratedFileCard({super.key, required this.file, required this.actions});
  final FileSeg file;
  final MessageActions actions;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final name = file.name.isEmpty ? 'file' : file.name;
    final (grad, fg) = _getFileStyle(name, context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: file.done ? pal.border : cs.primary.withValues(alpha: 0.4)),
        boxShadow: file.done ? [
          BoxShadow(color: Colors.black.withValues(alpha: pal.isDark ? 0.2 : 0.04), blurRadius: 10, offset: const Offset(0, 4))
        ] : null,
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: grad.first.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: file.done
              ? Icon(iconFor(name), color: fg, size: 24)
              : Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.2, color: fg)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(file.done ? fmtSize(file.content.length) : 'Creating file…', style: TextStyle(color: pal.dim, fontSize: 12)),
          ]),
        ),
        if (file.done) ...[
          IconButton(tooltip: 'Preview', visualDensity: VisualDensity.compact, onPressed: () => actions.previewFile(file), icon: Icon(Icons.visibility_outlined, size: 20, color: pal.dim)),
          IconButton(tooltip: 'Copy', visualDensity: VisualDensity.compact, onPressed: () => actions.copy(file.content), icon: Icon(Icons.content_copy_rounded, size: 19, color: pal.dim)),
          IconButton.filledTonal(tooltip: 'Download', visualDensity: VisualDensity.compact, onPressed: () => actions.shareFile(file), icon: const Icon(Icons.download_rounded, size: 19)),
        ],
      ]),
    );
  }
}


// ───────────────────────── fast streaming markdown ─────────────────────────
/// DeepThink answers start with "**Thinking** … ---" — split them so the reasoning can be folded.
({String? think, String answer}) splitThink(String raw) {
  final m = RegExp(r'^\s*\*{0,2}Thinking\*{0,2}:?[ \t]*\n').firstMatch(raw);
  if (m == null) return (think: null, answer: raw);
  final i = raw.indexOf('\n---', m.end);
  if (i < 0) return (think: raw.substring(m.end).trim(), answer: '');
  final end = raw.indexOf('\n', i + 4);
  return (think: raw.substring(m.end, i).trim(), answer: end < 0 ? '' : raw.substring(end + 1));
}

final _listStart = RegExp(r'^(\s*[-*+]\s|\s*\d+[.)]\s|\s{2,}\S)');

/// Splits markdown into blocks at blank lines (never inside ``` fences, and list items stay together).
List<String> splitMdBlocks(String t) {
  final out = <String>[];
  var buf = <String>[];
  var fence = false;
  var pendingBlank = false;
  void flush() {
    if (buf.isNotEmpty) out.add(buf.join('\n'));
    buf = <String>[];
  }

  for (final line in t.split('\n')) {
    if (line.trimLeft().startsWith('```')) fence = !fence;
    if (!fence && line.trim().isEmpty) {
      pendingBlank = buf.isNotEmpty;
      continue;
    }
    if (pendingBlank && !fence) {
      pendingBlank = false;
      if (!_listStart.hasMatch(line) || !(buf.isNotEmpty && _listStart.hasMatch(buf.first))) {
        flush();
      } else {
        buf.add('');
      }
    }
    buf.add(line);
  }
  flush();
  return out;
}

/// Only the LAST block changes while the answer streams, so finished blocks are never re-parsed
/// (re-parsing the whole answer 25x per second was the main source of dropped frames).
/// Finished blocks keep the SAME widget instance, which Flutter skips when rebuilding.
class MdBlocks extends StatefulWidget {
  const MdBlocks({super.key, required this.text, required this.fontSize, required this.actions});
  final String text;
  final double fontSize;
  final MessageActions actions;

  @override
  State<MdBlocks> createState() => _MdBlocksState();
}

class _MdBlocksState extends State<MdBlocks> {
  final List<String> _keys = [];
  final List<Widget> _widgets = [];

  @override
  Widget build(BuildContext context) {
    final blocks = splitMdBlocks(widget.text);
    final dark = Pal.of(context).isDark;
    final fs = widget.fontSize;
    for (var i = 0; i < blocks.length; i++) {
      final k = '$dark|$fs|${blocks[i]}';
      if (i < _keys.length && _keys[i] == k) continue; // unchanged -> same widget instance
      final w = _MdBlock(key: ValueKey(i), text: blocks[i], fontSize: fs, actions: widget.actions);
      if (i < _keys.length) {
        _keys[i] = k;
        _widgets[i] = w;
      } else {
        _keys.add(k);
        _widgets.add(w);
      }
    }
    if (_keys.length > blocks.length) {
      _keys.length = blocks.length;
      _widgets.length = blocks.length;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: List<Widget>.of(_widgets));
  }
}

class _MdBlock extends StatelessWidget {
  const _MdBlock({super.key, required this.text, required this.fontSize, required this.actions});
  final String text;
  final double fontSize;
  final MessageActions actions;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return RepaintBoundary(
      child: MarkdownBody(
        data: text,
        softLineBreak: true,
        onTapLink: (t, href, title) {
          if (href != null && href.isNotEmpty) actions.openLink(href);
        },
        builders: {'pre': CodeBlockBuilder(pal, actions.copy)},
        styleSheet: mdSheet(context, pal, fontSize),
      ),
    );
  }
}

/// DeepSeek-style foldable "Thought process".
class ThinkBlock extends StatefulWidget {
  const ThinkBlock({super.key, required this.text, required this.streaming});
  final String text;
  final bool streaming;
  @override
  State<ThinkBlock> createState() => _ThinkBlockState();
}

class _ThinkBlockState extends State<ThinkBlock> {
  bool? _open; // null => follow streaming state

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final open = _open ?? widget.streaming;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(Icons.psychology_alt_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.streaming ? 'Thinking…' : 'Thought process', style: TextStyle(color: pal.dim, fontSize: 13.5, fontWeight: FontWeight.w600))),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: pal.dim),
              ]),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(widget.text, style: TextStyle(color: pal.dim, fontSize: 13.5, height: 1.5)),
            ),
        ]),
      ),
    );
  }
}
