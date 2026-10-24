import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/chat_message.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiService {
  // Reuse connection for faster requests
  static final http.Client _client = http.Client();

  /// Sends the whole conversation so the AI remembers context.
  Future<Map<String, dynamic>> send(List<ChatMessage> history) async {
    final recentHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
    final payload = recentHistory
        .where((m) => m.isUser || m.role == 'assistant')
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(kBackendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'messages': payload}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw AiException(
          'Could not reach the CourseDeep server. Check your internet connection.');
    }

    final data = _parse(response.body);
    if (data == null) {
      throw AiException(
          'Server sent an unexpected response (HTTP ${response.statusCode}). '
          'Check kBackendUrl in lib/config.dart.');
    }
    if (response.statusCode != 200 || data['error'] != null) {
      throw AiException(
          data['error']?.toString() ?? 'Server error (HTTP ${response.statusCode}).');
    }
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw AiException('The AI returned an empty answer. Please try again.');
    }
    return {
      'reply': reply.trim(),
      'sources': data['sources'] ?? [],
    };
  }

  Map<String, dynamic>? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
