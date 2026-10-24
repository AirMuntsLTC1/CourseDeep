import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../models/chat_message.dart';
import 'native_service.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiService {
  static final http.Client _client = http.Client();

  Future<Map<String, dynamic>> send(List<ChatMessage> history) async {
    // 1. USE C++ NATIVE LIB
    NativeService().init();
    final latestHash = NativeService().getHash(history.last.text);
    debugPrint("C++ Native Hash for latest message: $latestHash");

    final recentHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
    final payload = recentHistory
        .where((m) => m.isUser || m.role == 'assistant')
        .map((m) {
          String content = m.text;
          if (m.fileText != null) {
            content = "$content\n\n[Attached File: ${m.fileName}]\n${m.fileText}";
          }
          return {'role': m.role, 'content': content, 'image': m.imageBase64};
        })
        .toList();

    http.Response response;
    try {
      // ONLY USE SUPABASE (45s timeout for 11-tier fallback)
      response = await _client
          .post(
            Uri.parse(kBackendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'messages': payload}),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw AiException('Could not reach CourseDeep servers. Please check your internet connection. ($e)');
    }

    // Safely parse the JSON
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('Server sent an invalid response (HTTP ${response.statusCode}). Please try again.');
    }

    if (response.statusCode != 200 || data['error'] != null) {
      throw AiException(data['error']?.toString() ?? 'Server error (HTTP ${response.statusCode}).');
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
}
