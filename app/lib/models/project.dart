class Project {
  Project({
    required this.id,
    required this.name,
    this.description = '',
    this.instructions = '',
    this.isPublic = false,
    List<ProjectFile>? files,
    DateTime? created,
    DateTime? updated,
  })  : files = files ?? [],
        created = created ?? DateTime.now(),
        updated = updated ?? DateTime.now();

  final String id;
  String name;
  String description;
  String instructions;
  bool isPublic;
  final List<ProjectFile> files;
  final DateTime created;
  DateTime updated;

  Map<String, dynamic> toUpsert() => {
        'name': name,
        'description': description,
        'instructions': instructions,
        'is_public': isPublic,
        'files': files.map((f) => f.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Untitled',
        description: j['description'] as String? ?? '',
        instructions: j['instructions'] as String? ?? '',
        isPublic: j['is_public'] as bool? ?? false,
        files: (j['files'] as List? ?? [])
            .map((e) => ProjectFile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        created: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  /// Injected into every AI request made from this project.
  String get systemContext {
    final b = StringBuffer();
    b.writeln('You are CourseDeep working INSIDE a user project called "$name".');
    if (description.trim().isNotEmpty) b.writeln('Project description: ${description.trim()}');
    if (instructions.trim().isNotEmpty) {
      b.writeln('Standing instructions the user gave you that MUST be followed in every reply:');
      b.writeln(instructions.trim());
    }
    final textFiles = files.where((f) => (f.text ?? '').trim().isNotEmpty).toList();
    if (textFiles.isNotEmpty) {
      b.writeln('');
      b.writeln('Imported project files (contents available to you):');
      var used = 0;
      const cap = 5000;
      for (final f in textFiles) {
        final room = cap - used;
        if (room <= 100) {
          b.writeln('- ${f.name}: (omitted, size limit)');
          continue;
        }
        final body = f.text!;
        final snippet = body.length > room ? '${body.substring(0, room)}\n…[truncated]' : body;
        b.writeln('\n--- ${f.name} ---\n$snippet');
        used += snippet.length;
      }
    }
    b.writeln('');
    b.writeln('STRICT RULES:');
    b.writeln('1. Only help with THIS project. If the user asks about something unrelated, gently bring them back to the project.');
    b.writeln('2. Follow the standing instructions above in every single reply.');
    b.writeln('3. Never claim to have files you were not given; ask the user to import them if you need more context.');
    return b.toString();
  }
}

class ProjectFile {
  ProjectFile({required this.name, required this.size, this.text});
  final String name;
  final int size;
  final String? text;

  Map<String, dynamic> toJson() => {'name': name, 'size': size, 'text': text};

  factory ProjectFile.fromJson(Map<String, dynamic> j) => ProjectFile(
        name: j['name'] as String? ?? 'file',
        size: (j['size'] as num?)?.toInt() ?? 0,
        text: j['text'] as String?,
      );
}
