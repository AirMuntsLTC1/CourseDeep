import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_settings.dart';

/// Speaks AI replies out loud using the device's native TTS engine.
/// No API key, no network, works offline. Reads settings live so the user
/// can toggle it on/off without restarting the app.
class VoiceService {
  VoiceService._();
  static final VoiceService I = VoiceService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  String? _currentText;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);   // 0.0 = slow, 1.0 = fast
      await _tts.setPitch(1.0);         // 1.0 = normal
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
    } catch (e) {
      debugPrint('VoiceService init failed: $e');
    }
  }

  bool get isSpeaking => _currentText != null;

  /// Speak a reply. Strips markdown so the TTS doesn't read "*" and "#".
  Future<void> speak(String rawText) async {
    if (!AppSettings.I.voiceEnabled) return;
    if (rawText.trim().isEmpty) return;
    await init();
    await stop();
    final clean = _cleanForSpeech(rawText);
    if (clean.isEmpty) return;
    _currentText = clean;
    try {
      await _tts.speak(clean);
    } catch (e) {
      debugPrint('VoiceService speak failed: $e');
    } finally {
      _currentText = null;
    }
  }

  Future<void> stop() async {
    _currentText = null;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Remove markdown, code blocks, URLs, emojis — leave only readable words.
  String _cleanForSpeech(String s) {
    var t = s;
    // Remove fenced code blocks entirely (don't read code aloud)
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' code omitted. ');
    // Remove inline code
    t = t.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    // Remove FILE blocks
    t = t.replaceAll(RegExp(r'<<<FILE:[\s\S]*?<<<END FILE>>>'), ' file created. ');
    // Remove URLs
    t = t.replaceAll(RegExp(r'https?://\S+'), ' link. ');
    // Remove markdown links [text](url) -> text
    t = t.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '');
    // Remove markdown symbols
    t = t.replaceAll(RegExp(r'[#*_~>`]'), '');
    // Collapse whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Limit length (don't read 10,000 chars)
    if (t.length > 3000) t = '${t.substring(0, 3000)}… ';
    return t;
  }
}
