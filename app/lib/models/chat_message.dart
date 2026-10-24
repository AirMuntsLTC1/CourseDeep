import 'package:flutter/foundation.dart';

enum AttachKind { image, pdf, text, archive, document }

class Attachment {
  Attachment({
    required this.name,
    required this.kind,
    this.mime = 'application/octet-stream',
    this.path,
    this.text,
    this.size = 0,
    this.note,
    this.loading = false,
  });

  final String name;
  final AttachKind kind;
  final String mime;
  String? path; // copy inside the app folder (survives restarts)
  String? text; // extracted text sent to the AI
  int size;
  String? note;
  bool loading; // transient
  bool failed = false; // transient

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'mime': mime,
        'path': path,
        'text': text,
        'size': size,
        'note': note,
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        name: j['name'] as String? ?? 'file',
        kind: AttachKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => AttachKind.text),
        mime: j['mime'] as String? ?? 'application/octet-stream',
        path: j['path'] as String?,
        text: j['text'] as String?,
        size: (j['size'] as num?)?.toInt() ?? 0,
        note: j['note'] as String?,
      );
}

class Source {
  Source({required this.title, required this.url});
  final String title;
  final String url;

  String get host => (Uri.tryParse(url)?.host ?? '').replaceFirst('www.', '');

  factory Source.fromJson(Map<String, dynamic> j) =>
      Source(title: j['title'] as String? ?? 'Source', url: j['url'] as String? ?? '');
  Map<String, dynamic> toJson() => {'title': title, 'url': url};
}

/// A message is a ChangeNotifier so only the streaming row rebuilds while tokens arrive.
class ChatMessage extends ChangeNotifier {
  ChatMessage({
    String? id,
    required this.role,
    String text = '',
    List<Source>? sources,
    List<Attachment>? attachments,
    DateTime? time,
    this.provider,
    this.streaming = false,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        _text = text,
        sources = sources ?? [],
        attachments = attachments ?? [],
        time = time ?? DateTime.now();

  final String id;

  /// 'user', 'assistant' or 'error'
  String role;
  String _text;
  List<Source> sources;
  final List<Attachment> attachments;
  final DateTime time;
  String? provider;

  // transient streaming state
  bool streaming;
  String status = '';

  String get text => _text;
  set text(String v) => _text = v;
  void append(String d) => _text += d;
  void update() => notifyListeners();

  bool get isUser => role == 'user';
  bool get isError => role == 'error';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': _text,
        'time': time.toIso8601String(),
        'provider': provider,
        'sources': sources.map((s) => s.toJson()).toList(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String?,
        role: j['role'] as String? ?? 'assistant',
        text: j['text'] as String? ?? '',
        time: DateTime.tryParse(j['time'] as String? ?? ''),
        provider: j['provider'] as String?,
        sources: (j['sources'] as List? ?? []).map((e) => Source.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        attachments: (j['attachments'] as List? ?? []).map((e) => Attachment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class ChatSession {
  ChatSession({required this.id, required this.title, List<ChatMessage>? messages, DateTime? updated})
      : messages = messages ?? [],
        updated = updated ?? DateTime.now();

  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updated;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated.toIso8601String(),
        'messages': messages.where((m) => !m.streaming).map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'New chat',
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
        messages: (j['messages'] as List? ?? []).map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}
