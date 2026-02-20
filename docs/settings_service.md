# SettingsService

**File:** [`lib/services/settings_service.dart`](../lib/services/settings_service.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`SettingsService` is the single source of truth for all persistent application configuration. It wraps `SharedPreferences` and provides typed getters/setters with input validation and sensible defaults for every setting. All other services that need configuration depend on an initialised `SettingsService` instance, which is created and owned by [`ChatService`](chat_service.md).

---

## Initialization

```dart
await settingsService.init();
```

Must be called before accessing any property. Obtains the `SharedPreferences` singleton. Calling getters before `init()` is safe — they fall back to their declared `default*` constants.

---

## Settings Reference

### Inference Settings

#### Context Size

```dart
int get contextSize                          // default: 2048
Future<bool> setContextSize(int size)        // valid range: 128–8192
```

The token context window passed to `LlamaController.loadModel()`. A larger context allows longer conversations but requires more RAM and increases VRAM/CPU load.

Throws `ArgumentError` if `size < 128 || size > 8192`.

| Key | `context_size` |
|---|---|
| Type | `int` |
| Default | `2048` |
| Range | 128 – 8192 |

#### Chat Template

```dart
String get chatTemplate                        // default: 'auto'
Future<bool> setChatTemplate(String template)
```

Controls how conversation history is formatted into a prompt. `'auto'` lets the native layer detect the template from the model filename.

Throws `ArgumentError` for unrecognised template IDs that are also not in the custom template list.

Supported values: `auto`, `chatml`, `llama3`, `llama2`, `phi`, `gemma`, `gemma2`, `gemma3`, `alpaca`, `vicuna`, `mistral`, `mixtral`, `qwq`, `deepseek-r1`, `deepseek-v3`, `deepseek-coder`.

| Key | `chat_template` |
|---|---|
| Type | `String` |
| Default | `'auto'` |

---

### Model Management Settings

#### Auto-Unload Model

```dart
bool get autoUnloadModel                           // default: true
Future<bool> setAutoUnloadModel(bool enabled)
```

When `true`, the model is unloaded after `autoUnloadTimeout` seconds of inactivity (no messages sent). Frees RAM on mobile devices where memory is constrained. Enabled by default.

| Key | `auto_unload_model` |
|---|---|
| Type | `bool` |
| Default | `true` |

#### Auto-Unload Timeout

```dart
int get autoUnloadTimeout                          // default: 60
Future<bool> setAutoUnloadTimeout(int seconds)     // minimum: 10
```

Throws `ArgumentError` if `seconds < 10`.

| Key | `auto_unload_timeout` |
|---|---|
| Type | `int` |
| Default | `60` (seconds) |
| Minimum | 10 (seconds) |

---

### Conversation Settings

#### System Message

```dart
String get systemMessage
Future<bool> setSystemMessage(String message)
```

The initial system prompt injected as the first message in every conversation. Sets the AI's persona and behavioural constraints.

| Key | `system_message` |
|---|---|
| Type | `String` |
| Default | `'You are a helpful AI assistant. Be concise and friendly.'` |

#### Thinking Mode

```dart
bool get thinkingMode                        // default: false
Future<bool> setThinkingMode(bool enabled)
```

When `true`, the UI surfaces the raw `<think>...</think>` reasoning blocks emitted by reasoning models (QwQ, DeepSeek-R1). When `false`, these blocks are filtered out before display.

| Key | `thinking_mode` |
|---|---|
| Type | `bool` |
| Default | `false` |

---

### TTS Settings

```dart
bool get ttsEnabled                          // default: false
Future<bool> setTtsEnabled(bool enabled)
```

When `true`, AI responses are read aloud via [`TtsService`](tts_service.md) as they are generated.

| Key | `tts_enabled` |
|---|---|
| Type | `bool` |
| Default | `false` |

---

### Groq API Settings

#### API Key

```dart
String get groqApiKey                        // default: ''
Future<bool> setGroqApiKey(String apiKey)
```

The secret API key for the Groq cloud API. An empty string means Online Mode is unavailable. Set via the Settings screen — not hardcoded.

| Key | `groq_api_key` |
|---|---|
| Type | `String` |
| Default | `''` |

#### Model

```dart
String get groqModel                         // default: 'llama-3.3-70b-versatile'
Future<bool> setGroqModel(String model)
```

The Groq model ID to use for online inference. Can be changed to any model returned by `GroqService.getModels()`.

| Key | `groq_model` |
|---|---|
| Type | `String` |
| Default | `'llama-3.3-70b-versatile'` |

---

## Custom Templates

Custom prompt templates are stored as lists and key-value pairs in `SharedPreferences`.

```dart
// Get all template names
List<String> get customTemplateNames

// Get/set names list
Future<bool> setCustomTemplateNames(List<String> names)

// Get/set a single template's content
String getCustomTemplateContent(String name)
Future<bool> setCustomTemplateContent(String name, String content)

// Get all templates as a map
Map<String, String> getAllCustomTemplates()

// High-level add/remove helpers
Future<void> addCustomTemplate(String name, String content)
Future<void> removeCustomTemplate(String name)
```

Template names are stored under key `custom_templates` (a `List<String>`). Each template's content is stored under `custom_templates_<name>`.

---

## Reset

```dart
Future<void> resetToDefault()
```

Resets all settings to their declared `default*` values. Also removes all custom templates. Called by `ChatService.resetSettingsToDefault()`.

```dart
void resetContextSizeToDefault()
```

Resets only the context size to `defaultContextSize`. Called by `ChatService.clearHistory()`.

---

## Default Constants

| Constant | Value |
|---|---|
| `defaultContextSize` | `2048` |
| `defaultChatTemplate` | `'auto'` |
| `defaultAutoUnloadModel` | `true` |
| `defaultAutoUnloadTimeout` | `60` |
| `defaultSystemMessage` | `'You are a helpful AI assistant. Be concise and friendly.'` |
| `defaultThinkingMode` | `false` |
| `defaultTtsEnabled` | `false` |
| `defaultGroqModel` | `'llama-3.3-70b-versatile'` |

---

## Related Docs

- [ChatService](chat_service.md) — primary consumer of this service
- [GroqService](groq_service.md) — reads `groqApiKey` and `groqModel`
- [TtsService](tts_service.md) — `ttsEnabled` flag read by `ChatService`
