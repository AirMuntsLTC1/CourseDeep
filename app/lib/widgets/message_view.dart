import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    required this.shareZip,
    required this.previewFile,
  });
  final void Function(String url) openLink;
  final void Function(String text) copy;
  final VoidCallback regenerate;
  final void Function(String path) openImage;
  final void Function(ChatMessage m) more;
  final void Function(FileSeg f) shareFile;
  final void Function(List<FileSeg> files) shareZip;
  final void Function(FileSeg f) previewFile;
}

String plainText(String raw) => parseSegments(raw).whereType<TextSeg>().map((t) => t.text.trim()).where((t) => t.isNotEmpty).join('\n\n');

IconData iconFor(String name, {AttachKind? kind}) {
  final e = extOf(name);
  if (kind == AttachKind.pdf || e == 'pdf') return Icons.picture_as_pdf_outlined;
  if (kind == AttachKind.archive || e == 'zip') return Icons.folder_zip_outlined;
  if (kind == AttachKind.document || ['docx', 'doc', 'xlsx', 'pptx'].contains(e)) return Icons.description_outlined;
  if (['csv', 'tsv'].contains(e)) return Icons.table_chart_outlined;
  if (['json', 'yaml', 'yml', 'xml', 'toml'].contains(e)) return Icons.data_object;
  if (['html', 'css', 'js', 'ts', 'dart', 'py', 'java', 'kt', 'cpp', 'c', 'h', 'php', 'go', 'rs', 'sh', 'sql', 'jsx', 'tsx'].contains(e)) return Icons.code;
  if (e == 'svg') return Icons.image_outlined;
  return Icons.insert_drive_file_outlined;
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.msg, required this.isLast, required this.actions});
  final ChatMessage msg;
  final bool isLast;
  final MessageActions actions;

  @override
  Widget build(BuildContext context) {
    if (msg.isUser) return _UserBubble(msg: msg, actions: actions);
    return ListenableBuilder(
      listenable: msg,
      builder: (_, __) => _AssistantBlock(msg: msg, isLast: isLast, actions: actions),
    );
  }
}

// ───────────────────────── user ─────────────────────────
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.msg, required this.actions});
  final ChatMessage msg;
  final MessageActions actions;

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
                  child: Text(msg.text, style: TextStyle(color: pal.text, fontSize: 16, height: 1.42)),
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

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({required this.msg, required this.isLast, required this.actions});
  final ChatMessage msg;
  final bool isLast;
  final MessageActions actions;

  MarkdownStyleSheet _sheet(BuildContext c, Pal pal) {
    final cs = Theme.of(c).colorScheme;
    const fs = 16.5;
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

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final segs = msg.isError ? const <Seg>[] : parseSegments(_linkCitations(msg.text, msg.sources));
    final files = segs.whereType<FileSeg>().where((f) => f.done && f.name.isNotEmpty).toList();
    final waiting = msg.streaming && msg.text.isEmpty;

    return Padding(
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
            if (msg.isError)
              _ErrorCard(text: msg.text, onRetry: isLast ? actions.regenerate : null)
            else
              for (final s in segs)
                if (s is TextSeg && s.text.trim().isNotEmpty)
                  MarkdownBody(
                    data: s.text.trim(),
                    softLineBreak: true,
                    onTapLink: (text, href, title) {
                      if (href != null && href.isNotEmpty) actions.openLink(href);
                    },
                    builders: {'pre': CodeBlockBuilder(pal, actions.copy)},
                    styleSheet: _sheet(context, pal),
                  )
                else if (s is FileSeg)
                  GeneratedFileCard(file: s, actions: actions),
            if (files.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: FilledButton.tonalIcon(
                  onPressed: () => actions.shareZip(files),
                  icon: const Icon(Icons.folder_zip_outlined, size: 18),
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
    );
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
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          color: pal.surface2.withValues(alpha: 0.7),
          child: Row(children: [
            Text(lang.isEmpty ? 'code' : lang, style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: pal.dim),
              onPressed: () => onCopy(code),
              icon: const Icon(Icons.content_copy_rounded, size: 14),
              label: const Text('Copy', style: TextStyle(fontSize: 12)),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: file.done ? cs.primary.withValues(alpha: 0.35) : pal.border),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(12)),
          child: file.done
              ? Icon(iconFor(name), color: Colors.white, size: 22)
              : const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
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
          IconButton.filledTonal(tooltip: 'Save / share', visualDensity: VisualDensity.compact, onPressed: () => actions.shareFile(file), icon: const Icon(Icons.ios_share_rounded, size: 19)),
        ],
      ]),
    );
  }
}
