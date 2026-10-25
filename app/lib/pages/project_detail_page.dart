import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/project.dart';
import '../services/file_service.dart';
import '../services/project_store.dart';
import '../theme/app_theme.dart';
import 'project_chat_page.dart';

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key, required this.project});
  final Project project;
  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  final _store = ProjectStore();
  late Project _project;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  Future<void> _save() async {
    try {
      final updated = await _store.update(_project);
      if (mounted) setState(() => _project = updated);
    } catch (_) {
      _toast('Could not save changes.');
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  Future<void> _togglePublic(bool v) async {
    setState(() => _project.isPublic = v);
    await _save();
  }

  Future<void> _importFiles() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip', 'txt', 'md', 'markdown', 'csv', 'json', 'html', 'css', 'js', 'dart', 'py', 'java', 'cpp', 'c', 'h'],
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      var added = 0;
      for (final f in result.files) {
        if (f.path == null) continue;
        final extracted = await _extract(f.name, f.path!);
        if (extracted != null) {
          _project.files.add(extracted);
          added++;
        }
      }
      if (added > 0) {
        await _save();
        _toast('$added file${added == 1 ? '' : 's'} imported. The AI can now use them.');
      } else {
        _toast('No readable text files selected.');
      }
    } catch (e) {
      _toast('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ProjectFile?> _extract(String name, String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final ext = extOf(name);
      if (ext == 'zip') {
        final arc = ZipDecoder().decodeBytes(bytes);
        final sb = StringBuffer();
        for (final e in arc.files) {
          if (!e.isFile) continue;
          final ee = extOf(e.name);
          if (!const {
            'txt', 'md', 'markdown', 'csv', 'json', 'yaml', 'yml', 'xml', 'html', 'css', 'js', 'ts', 'dart',
            'py', 'java', 'kt', 'cpp', 'c', 'h', 'hpp', 'go', 'rs', 'rb', 'php', 'sh', 'sql'
          }.contains(ee)) continue;
          try {
            final c = utf8.decode((e.content as List).cast<int>(), allowMalformed: true);
            sb.writeln('--- ${e.name} ---\n$c\n');
            if (sb.length > 50000) break;
          } catch (_) {}
        }
        final text = sb.toString();
        return ProjectFile(
          name: name,
          size: bytes.length,
          text: text.length > 50000 ? text.substring(0, 50000) : text,
        );
      }
      if (ext == 'pdf' || !const {
        'txt', 'md', 'markdown', 'csv', 'json', 'yaml', 'yml', 'xml', 'html', 'css', 'js', 'ts', 'dart',
        'py', 'java', 'kt', 'cpp', 'c', 'h', 'hpp', 'go', 'rs', 'rb', 'php', 'sh', 'sql'
      }.contains(ext)) {
        return ProjectFile(name: name, size: bytes.length);
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      return ProjectFile(
        name: name,
        size: bytes.length,
        text: text.length > 50000 ? text.substring(0, 50000) : text,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _editInstructions() async {
    final c = TextEditingController(text: _project.instructions);
    final saved = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Project instructions'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(
              hintText: 'Tell the AI how to help you with this project. These instructions are permanent and apply to every reply.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() => _project.instructions = c.text.trim());
      await _save();
      _toast('Instructions saved to the AI.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete project?'),
        content: const Text('The project, its files and its instructions will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _store.delete(_project.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _toast('Could not delete the project.');
    }
  }

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectChatPage(project: _project)),
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
        title: Text(
          _project.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Delete project',
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
            onPressed: _delete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _start,
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start Project', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            // Public / Private toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: pal.surface2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.border),
              ),
              child: Row(children: [
                Expanded(
                  child: _SegBtn(
                    label: 'Public',
                    icon: Icons.public_rounded,
                    selected: _project.isPublic,
                    onTap: () => _togglePublic(true),
                  ),
                ),
                Expanded(
                  child: _SegBtn(
                    label: 'Private',
                    icon: Icons.lock_rounded,
                    selected: !_project.isPublic,
                    onTap: () => _togglePublic(false),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            Text('Description',
                style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: pal.border),
              ),
              child: Text(
                _project.description.trim().isEmpty ? 'No description yet.' : _project.description,
                style: TextStyle(color: pal.text, fontSize: 15, height: 1.55),
              ),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.upload_file_rounded,
                  label: 'Import Project',
                  sub: 'ZIP or text files',
                  busy: _busy,
                  onTap: _busy ? null : _importFiles,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.psychology_alt_rounded,
                  label: 'Instructions',
                  sub: '${_project.instructions.trim().isEmpty ? "None yet" : "Saved"}',
                  onTap: _editInstructions,
                ),
              ),
            ]),
            if (_project.files.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('Imported files (${_project.files.length})',
                  style: TextStyle(color: pal.dim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: pal.border),
                ),
                child: Column(
                  children: [
                    for (final f in _project.files)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(Icons.insert_drive_file_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: pal.text, fontSize: 13.5),
                            ),
                          ),
                          Text(
                            '${(f.size / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(color: pal.dim, fontSize: 11.5),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 46,
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: selected ? Colors.white : Pal.of(context).dim),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Pal.of(context).text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.sub, required this.onTap, this.busy = false});
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pal.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: busy
                  ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, size: 20, color: cs.primary),
            ),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: pal.text, fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: pal.dim, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
