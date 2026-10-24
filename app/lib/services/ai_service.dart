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
  /// Sends the whole conversation so the AI remembers context.
  Future<String> send(List<ChatMessage> history) async {
    final payload = history
        .where((m) => m.isUser || m.role == 'assistant')
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(kBackendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'messages': payload}),
          )
          .timeout(const Duration(seconds: 120));
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
    return reply.trim();
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
