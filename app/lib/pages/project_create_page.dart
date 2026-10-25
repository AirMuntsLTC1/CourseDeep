import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/project_store.dart';
import '../theme/app_theme.dart';

class ProjectCreatePage extends StatefulWidget {
  const ProjectCreatePage({super.key});
  @override
  State<ProjectCreatePage> createState() => _ProjectCreatePageState();
}

class _ProjectCreatePageState extends State<ProjectCreatePage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _nameFocus = FocusNode();
  final _store = ProjectStore();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give your project a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final p = Project(
        id: '',
        name: name,
        description: _desc.text.trim(),
      );
      final created = await _store.create(p);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not create the project. Check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(children: [
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, color: pal.text),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('New project',
                    style: TextStyle(color: pal.text, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                const SizedBox(height: 6),
                Text('Give it a name and a short description.',
                    style: TextStyle(color: pal.dim, fontSize: 14.5)),
                const SizedBox(height: 22),
                Text('Project name',
                    style: TextStyle(color: pal.dim, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: pal.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: pal.border),
                  ),
                  child: TextField(
                    controller: _name,
                    focusNode: _nameFocus,
                    enabled: !_saving,
                    maxLength: 120,
                    style: TextStyle(color: pal.text, fontSize: 16.5),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'e.g. CourseDeep marketing site',
                      hintStyle: TextStyle(color: pal.dim.withValues(alpha: 0.7)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Description',
                    style: TextStyle(color: pal.dim, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: pal.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: pal.border),
                  ),
                  child: TextField(
                    controller: _desc,
                    enabled: !_saving,
                    minLines: 6,
                    maxLines: 12,
                    maxLength: 8000,
                    style: TextStyle(color: pal.text, fontSize: 15.5, height: 1.45),
                    decoration: InputDecoration(
                      counterStyle: TextStyle(color: pal.dim, fontSize: 11),
                      hintText: 'What is this project about? What do you want to build or fix?',
                      hintStyle: TextStyle(color: pal.dim.withValues(alpha: 0.7)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_error != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13.5)),
                ),
              ]),
            ),
          ),
          // Floating create button — stays above the keyboard thanks to default resizeToAvoidBottomInset.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: GestureDetector(
              onTap: _saving ? null : _create,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _saving ? 0.7 : 1,
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: Brand.gradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Create project', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
