# TtsService

**File:** [`lib/services/tts_service.dart`](../lib/services/tts_service.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`TtsService` is a thin wrapper around the `flutter_tts` package that provides Text-to-Speech output for AI responses. It is instantiated directly in `ChatScreen` and called whenever the `ttsEnabled` flag is set in [`ChatService`](chat_service.md) and a complete response segment is available (signalled by the `"\n"` end-of-response sentinel on `messageStream`).

---

## Class Definition

```dart
class TtsService {
  final FlutterTts _flutterTts;
  bool _isSpeaking = false;

  bool get isSpeaking;
}
```

---

## Initialization

```dart
await ttsService.init()
```

Must be called once before `speak()`. Configures the TTS engine with the following defaults:

| Parameter | Value | Description |
|---|---|---|
| Language | `en-US` | Locale for speech synthesis |
| Speech Rate | `0.5` | Half the default speed — clearer AI response delivery |
| Volume | `1.0` | Full volume |
| Pitch | `1.0` | Normal pitch |
| `awaitSpeakCompletion` | `true` | The `Future` from `speak()` completes when speech finishes |

**Lifecycle callbacks registered:**

| Callback | Effect |
|---|---|
| `setStartHandler` | Sets `_isSpeaking = true` |
| `setCompletionHandler` | Sets `_isSpeaking = false` |
| `setErrorHandler` | Sets `_isSpeaking = false`, logs the error |

Initialisation errors are caught and logged — `TtsService` degrades gracefully if the platform TTS engine is unavailable.

---

## Methods

### `speak(String text)`

```dart
Future<void> speak(String text)
```

Sends `text` to the platform TTS engine for synthesis.

**Guards and preprocessing:**
- Returns immediately if `text.trim().isEmpty`.
- Truncates `text` to **3900 characters** before passing to the engine. Android's TTS engine has a hard limit of approximately 4000 characters per utterance; exceeding this causes silent failures on some devices.
- Logs the first 20 characters of the text for debugging.

With `awaitSpeakCompletion(true)`, this `Future` resolves only after the engine finishes speaking the utterance. Because the UI does not `await` `speak()` (fire-and-forget pattern), multiple calls queue naturally inside `flutter_tts`.

**Usage in the app:**

```dart
// In ChatScreen message stream listener
} else if (token == '\n') {
  if (_chatService.ttsEnabled && _currentAIResponse.trim().isNotEmpty) {
    _ttsService.speak(_currentAIResponse); // fire-and-forget
  }
  _currentAIResponse = '';
}
```

---

### `stop()`

```dart
Future<void> stop()
```

Immediately halts any ongoing speech and sets `_isSpeaking = false`. Called when the user stops generation or navigates away from the chat.

---

## State

```dart
bool get isSpeaking
```

`true` while the platform engine is actively synthesising/playing speech. Updated by the `StartHandler` and `CompletionHandler` callbacks.

---

## Android Constraints

| Constraint | Detail |
|---|---|
| Character limit | ~4000 chars per call (enforced at 3900 in code) |
| Language availability | Depends on the installed TTS engine and language packs on the device |
| Background playback | TTS may be interrupted by the system if the app loses audio focus |

---

## Related Docs

- [ChatService](chat_service.md) — exposes `ttsEnabled` and `ttsService` flag
- [Main / ChatScreen UI](main.md) — instantiates `TtsService` and calls `speak()` / `stop()`
- [SettingsService](settings_service.md) — `tts_enabled` preference key
