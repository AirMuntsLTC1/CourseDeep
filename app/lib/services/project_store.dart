import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project.dart';

/// Supabase-backed storage for projects. Survives logout & reinstall.
class ProjectStore {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Project>> list() async {
    final rows = await _db.from('projects').select().order('updated_at', ascending: false);
    return (rows as List)
        .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Project> create(Project p) async {
    final row = await _db.from('projects').insert(p.toUpsert()).select().single();
    return Project.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<Project> update(Project p) async {
    final row = await _db
        .from('projects')
        .update(p.toUpsert())
        .eq('id', p.id)
        .select()
        .single();
    return Project.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<void> delete(String id) async {
    await _db.from('projects').delete().eq('id', id);
  }
}
