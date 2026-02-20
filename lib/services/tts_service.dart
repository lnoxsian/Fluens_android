import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    try {
      // Default settings
      await _flutterTts.setLanguage("en-US"); 
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      // Attempt to await speak completion on iOS and Android
      // Note: On some Android devices, awaiting completion might cause issues if not handled properly.
      // But for streaming, we want to queue utterances or handle them sequentially usually...
      // However, here we fire-and-forget from the UI thread, so awaiting completion means
      // multiple calls will run overlapping or interfere? No, flutter_tts queues them internally usually.
      // Setting awaitSpeakCompletion(true) makes the Future complete only when done.
      // Since we don't await speak() in the UI loop, this just means the future hangs around.
      // It shouldn't block.
      await _flutterTts.awaitSpeakCompletion(true);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        debugPrint("[TtsService] Speaking started");
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        debugPrint("[TtsService] Speaking completed");
      });
      
      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint("[TtsService] Error: $msg");
      });
      
      debugPrint("[TtsService] Initialized successfully");
    } catch (e) {
      debugPrint("[TtsService] Error initializing: $e");
    }
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      // Clean up text if needed (remove emojis or weird chars if they cause issues, 
      // but usually TTS handles them or ignores them)
      debugPrint("[TtsService] Requesting speak: ${text.substring(0, text.length > 20 ? 20 : text.length)}...");
      
      // Limit text length to avoid Android TTS limits (approx 4000 chars)
      // Though unlikely to hit here if chunking by newlines.
      if (text.length > 3900) {
        text = text.substring(0, 3900);
      }
      
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("[TtsService] Error speaking: $e");
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
    } catch (e) {
      debugPrint("[TtsService] Error stopping: $e");
    }
  }
}
