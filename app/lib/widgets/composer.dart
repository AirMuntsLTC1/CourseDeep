import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import '../services/app_settings.dart';
import 'message_view.dart';

enum AttachChoice { photo, camera, file }

Future<AttachChoice?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final pal = Pal.of(ctx);
      Widget tile(IconData i, String t, String s, AttachChoice c, List<Color> g) => ListTile(
            onTap: () => Navigator.pop(ctx, c),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: LinearGradient(colors: g), borderRadius: BorderRadius.circular(14)),
              child: Icon(i, color: Colors.white, size: 22),
            ),
            title: Text(t, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
            subtitle: Text(s, style: TextStyle(color: pal.dim, fontSize: 12.5)),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile(Icons.photo_library_outlined, 'Photos', 'Ask about any picture', AttachChoice.photo, const [Color(0xFF7C5CFF), Color(0xFF4F8CFF)]),
            tile(Icons.photo_camera_outlined, 'Camera', 'Take a photo and analyse it', AttachChoice.camera, const [Color(0xFFFF6BCB), Color(0xFF7C5CFF)]),
            tile(Icons.attach_file_rounded, 'Files', 'PDF, ZIP, Word, Excel, PowerPoint, code, text…', AttachChoice.file, const [Color(0xFF22D3EE), Color(0xFF4F8CFF)]),
          ]),
        ),
      );
    },
  );
}

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.focus,
    required this.busy,
    required this.attachments,
    required this.searchOn,
    required this.thinkOn,
    required this.onToggleSearch,
    required this.onToggleThink,
    required this.onAttach,
    required this.onSend,
    required this.onStop,
    required this.onRemove,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
    this.holding = false,
    this.liveText = '',
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final List<Attachment> attachments;
  final bool searchOn, thinkOn;
  final VoidCallback onToggleSearch, onToggleThink, onAttach, onSend, onStop;
  final void Function(Attachment) onRemove;
  final VoidCallback onHoldStart;
  final void Function(String finalText) onHoldEnd;
  final VoidCallback onHoldCancel;
  final bool holding;
  final String liveText;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final hasImage = attachments.any((a) => a.kind == AttachKind.image);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: pal.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: pal.isDark ? 0.35 : 0.06), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: !holding || liveText.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(children: [
                        Icon(Icons.graphic_eq_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            liveText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: pal.text, fontSize: 13.5),
                          ),
                        ),
                      ]),
                    ),
                  ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: attachments.isEmpty
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 66,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      scrollDirection: Axis.horizontal,
                      itemCount: attachments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => AttachmentChip(a: attachments[i], onRemove: () => onRemove(attachments[i])),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 14, 0),
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: pal.text, fontSize: 16.5, height: 1.4),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: hasImage ? 'Ask about this image…' : attachments.isNotEmpty ? 'Ask about this file…' : 'Ask CourseDeep anything…',
                hintStyle: TextStyle(color: pal.dim.withValues(alpha: 0.8)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: Row(children: [
              _RoundBtn(icon: Icons.add_rounded, tip: 'Attach', onTap: () {
                haptic(HapticFeedback.selectionClick);
                onAttach();
              }),
              const SizedBox(width: 6),
              _ToggleChip(icon: Icons.psychology_alt_outlined, label: 'DeepThink', on: thinkOn, onTap: () {
                haptic(HapticFeedback.selectionClick);
                onToggleThink();
              }),
              const SizedBox(width: 6),
              _ToggleChip(icon: Icons.public_rounded, label: 'Search', on: searchOn, onTap: () {
                haptic(HapticFeedback.selectionClick);
                onToggleSearch();
              }),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, v, __) {
                  final ready = v.text.trim().isNotEmpty || attachments.any((a) => !a.loading && !a.failed);
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: busy
                        ? GestureDetector(
                            key: const ValueKey('stop'),
                            onTap: onStop,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: pal.text, shape: BoxShape.circle),
                              child: Icon(Icons.stop_rounded, color: pal.bg, size: 22),
                            ),
                          )
                        : GestureDetector(
                            key: const ValueKey('send'),
                            onTap: ready ? onSend : null,
                            onLongPressStart: (_) => onHoldStart(),
                            onLongPressEnd: (_) => onHoldEnd(liveText),
                            onLongPressCancel: onHoldCancel,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: holding ? 52 : 40,
                              height: holding ? 52 : 40,
                              decoration: BoxDecoration(
                                gradient: (holding || ready) ? Brand.gradient : null,
                                color: (holding || ready) ? null : pal.surface2,
                                shape: BoxShape.circle,
                                boxShadow: holding
                                    ? [BoxShadow(color: Brand.violet.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 3)]
                                    : null,
                              ),
                              child: Icon(
                                holding ? Icons.mic_rounded : Icons.arrow_upward_rounded,
                                color: (holding || ready) ? Colors.white : pal.dim,
                                size: holding ? 26 : 22,
                              ),
                            ),
                          ),
                  );
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: pal.surface2, shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: pal.text),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? cs.primary.withValues(alpha: 0.15) : pal.surface2,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: on ? cs.primary.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: on ? cs.primary : pal.dim),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: on ? cs.primary : pal.dim, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

