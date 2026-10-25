import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// On-device speech-to-text for the "hold to speak" composer button.
class SpeechService {
  SpeechService._();
  static final SpeechService I = SpeechService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  bool get isListening => _listening;

  Future<bool> ensureReady() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('SpeechService: mic permission denied');
      return false;
    }
    if (!_initialized) {
      _initialized = await _speech.initialize(
        onStatus: (s) {
          debugPrint('SpeechService status: $s');
          if (s == 'done' || s == 'notListening') _listening = false;
        },
        onError: (e) => debugPrint('SpeechService error: $e'),
      );
    }
    return _initialized;
  }

  Future<bool> start({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
  }) async {
    if (!await ensureReady()) return false;
    await _speech.stop();
    _listening = true;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        final text = r.recognizedWords.trim();
        if (text.isEmpty) return;
        if (r.finalResult) {
          onFinal(text);
          _listening = false;
        } else {
          onPartial(text);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
    return true;
  }

  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    _listening = false;
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}
