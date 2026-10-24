class Source {
  final String title;
  final String url;
  Source({required this.title, required this.url});
  factory Source.fromJson(Map<String, dynamic> j) => Source(title: j['title'] as String? ?? 'Source', url: j['url'] as String? ?? '');
}

class ChatMessage {
  ChatMessage({required this.role, required this.text, this.sources = const [], this.imageBase64, DateTime? time})
      : time = time ?? DateTime.now();

  final List<Source> sources;
  final String? imageBase64;

  /// 'user', 'assistant' or 'error'
  final String role;
  final String text;
  final DateTime time;

  bool get isUser => role == 'user';
  bool get isError => role == 'error';

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'time': time.toIso8601String(),
        'sources': sources.map((s) => {'title': s.title, 'url': s.url}).toList(),
        'imageBase64': imageBase64,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String,
        text: j['text'] as String,
        time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
        sources: (j['sources'] as List? ?? []).map((e) => Source.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        imageBase64: j['imageBase64'] as String?,
      );
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? updated,
  })  : messages = messages ?? [],
        updated = updated ?? DateTime.now();

  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updated;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'New chat',
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
        messages: (j['messages'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
