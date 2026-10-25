import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/project_store.dart';
import '../theme/app_theme.dart';
import 'project_create_page.dart';
import 'project_detail_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final _store = ProjectStore();
  final _search = TextEditingController();
  List<Project> _all = [];
  List<Project> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_filter);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_filter);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _store.list();
      if (!mounted) return;
      setState(() {
        _all = list;
        _error = null;
        _loading = false;
      });
      _filter();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _filter() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.description.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<Project>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, a, __) => const ProjectCreatePage(),
        transitionsBuilder: (_, a, __, child) {
          final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(curve),
            child: FadeTransition(opacity: a, child: child),
          );
        },
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      _all.insert(0, created);
      _filtered.insert(0, created);
    });
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectDetailPage(project: created)),
    );
    _load();
  }

  Future<void> _openDetail(Project p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p)),
    );
    _load();
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
        title: const Text('Projects'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text('New Project', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              style: TextStyle(color: pal.text),
              decoration: InputDecoration(
                hintText: 'Search projects…',
                hintStyle: TextStyle(color: pal.dim.withValues(alpha: 0.8)),
                prefixIcon: Icon(Icons.search_rounded, color: pal.dim),
                filled: true,
                fillColor: pal.surface2,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _body(pal, cs)),
        ]),
      ),
    );
  }

  Widget _body(Pal pal, ColorScheme cs) {
    if (_loading) {
      return const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: pal.dim),
            const SizedBox(height: 12),
            Text('Could not load projects', style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.dim, fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_off_rounded, size: 44, color: cs.primary),
            ),
            const SizedBox(height: 18),
            Text('No project folder', style: TextStyle(color: pal.text, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Create your first project to organise your work and give the AI persistent context.',
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.dim, fontSize: 14, height: 1.5),
            ),
          ]),
        ),
      );
    }
    if (_filtered.isEmpty) {
      return Center(child: Text('No matches for "${_search.text}"', style: TextStyle(color: pal.dim)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _ProjectCard(project: _filtered[i], onTap: () => _openDetail(_filtered[i])),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: pal.border),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C5CFF), Color(0xFF22D3EE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.folder_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.text, fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (project.isPublic ? cs.primary : pal.dim).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        project.isPublic ? 'Public' : 'Private',
                        style: TextStyle(
                          color: project.isPublic ? cs.primary : pal.dim,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    project.description.trim().isEmpty
                        ? 'No description'
                        : project.description.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.dim, fontSize: 12.5),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
