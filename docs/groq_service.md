# GroqService

**File:** [`lib/services/groq_service.dart`](../lib/services/groq_service.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`GroqService` is a lightweight HTTP client that streams AI responses from the [Groq cloud API](https://console.groq.com). It implements the OpenAI-compatible chat completions endpoint (`/openai/v1/chat/completions`) using Server-Sent Events (SSE) streaming, enabling token-by-token output identical to the on-device inference experience.

It is exclusively used by [`ChatService`](chat_service.md) when **Online Mode** is active.

---

## Class Definition

```dart
class GroqService {
  final SettingsService _settingsService;
  final http.Client _client;

  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  GroqService({SettingsService? settingsService});
}
```

`SettingsService` is injected at construction time. If not provided, a new default instance is created (not recommended; always pass an already-initialised instance from `ChatService`).

---

## Methods

### `sendMessageStream`

```dart
Stream<String> sendMessageStream(
  String message,
  List<Map<String, String>> history, {
  String? systemMessage,
}) async*
```

Streams response tokens from Groq for a single user turn.

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `message` | `String` | The current user message to send |
| `history` | `List<Map<String, String>>` | Prior conversation turns as `[{"role": "user"/"assistant", "content": "..."}]` |
| `systemMessage` | `String?` | Optional system prompt prepended before the history |

**Behaviour:**

1. Reads `groqApiKey` from `SettingsService`. Throws `Exception('Groq API Key not set...')` immediately if empty.
2. Builds the messages array: system message (if present) → history → current user message.
3. Creates an `http.StreamedRequest` (`POST`) with the following fixed parameters:

```json
{
  "model": "<from SettingsService>",
  "messages": [...],
  "stream": true,
  "temperature": 1,
  "max_completion_tokens": 1024,
  "top_p": 1
}
```

4. Sends the request and checks `response.statusCode`. On non-200, reads the full body, attempts to parse the Groq error JSON, and rethrows as `Exception`.
5. Decodes the SSE stream line by line using `utf8.decoder` + `LineSplitter`.
6. For each line starting with `"data: "`, strips the prefix and parses the JSON delta. Yields `choices[0].delta.content` if present.
7. Stops on the `[DONE]` sentinel.

**Error handling:** JSON parse errors for partial SSE chunks are silently swallowed (expected during streaming). Network errors are wrapped in `Exception('Network error: $e')` and rethrown.

**Example usage (inside ChatService):**

```dart
final stream = _groqService.sendMessageStream(
  userMessage,
  historyList,
  systemMessage: systemPrompt,
);

await for (final token in stream) {
  if (_isCancelled) break;
  _messageStreamController.add(token);
}
```

---

### `getModels`

```dart
Future<List<String>> getModels()
```

Fetches the list of currently available model IDs from `GET /openai/v1/models`.

- Returns an empty list if the API key is not set or if the request fails.
- Returns a `List<String>` of model ID strings on success.
- Used by the Settings UI to populate the model picker.

---

## Request Format

```json
POST https://api.groq.com/openai/v1/chat/completions
Authorization: Bearer <groq_api_key>
Content-Type: application/json

{
  "model": "llama-3.3-70b-versatile",
  "messages": [
    {"role": "system",    "content": "You are a helpful AI assistant."},
    {"role": "user",      "content": "Previous user message"},
    {"role": "assistant", "content": "Previous assistant reply"},
    {"role": "user",      "content": "Current user message"}
  ],
  "stream": true,
  "temperature": 1,
  "max_completion_tokens": 1024,
  "top_p": 1
}
```

---

## SSE Response Parsing

Each SSE line has the format:

```
data: {"id":"...","choices":[{"delta":{"content":"token"},...}],...}
```

The service extracts `choices[0].delta.content` and yields it as a `String`. The final event `data: [DONE]` terminates the stream.

---

## Configuration

All configuration is read from [`SettingsService`](settings_service.md) at call time (not cached):

| Setting | Key | Description |
|---|---|---|
| `groqApiKey` | `groq_api_key` | Required — Groq API secret key |
| `groqModel` | `groq_model` | Model to use, default `llama-3.3-70b-versatile` |

---

## Error Reference

| Error | Cause |
|---|---|
| `Exception('Groq API Key not set...')` | `groqApiKey` is empty in settings |
| `Exception('Groq API Error: 401 ...')` | Invalid API key |
| `Exception('Groq API Error: 429 ...')` | Rate limit exceeded |
| `Exception('Network error: ...')` | Network unreachable or request timeout |

---

## Related Docs

- [ChatService](chat_service.md) — calls this service for online inference
- [SettingsService](settings_service.md) — provides API key and model selection
