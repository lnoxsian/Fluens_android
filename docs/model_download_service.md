# ModelDownloadService

**File:** [`lib/services/model_download_service.dart`](../lib/services/model_download_service.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`ModelDownloadService` handles everything related to getting a GGUF model file onto the device and making its path available to the inference engine. It requests the necessary Android storage permissions, gives the user a file picker to select a `.gguf` model, validates the chosen file, and exposes the resolved path through a simple `modelPath` getter.

---

## Class Definition

```dart
class ModelDownloadService {
  late Directory _modelDirectory;
  String? _modelPath;

  String? get modelPath;
}
```

---

## Methods

### `initialize()`

```dart
Future<bool> initialize()
```

Must be called once before any other method (called by `ChatService.initialize()`).

**Steps:**

1. **Permission request — storage:**  
   Requests `Permission.storage`. On Android 13+ (API 33+), if the initial `storage` permission is denied, falls back to requesting `Permission.manageExternalStorage`. Issues a warning log if neither is granted, but continues (some device/ROM combinations grant access via scoped storage without explicit permission).

2. **Documents directory:**  
   Resolves the app's documents directory via `path_provider.getApplicationDocumentsDirectory()`. This path is used as the base for model storage.

3. **No default model:**  
   Does not attempt to find or preload any model on first launch. Returns `false` immediately to signal that no model is ready.

Returns `false` unconditionally on first launch (no model selected yet). The caller (`ChatService`) uses this return value to decide whether to show the model selection UI or proceed to load.

---

### `pickLocalModel()`

```dart
Future<String?> pickLocalModel()
```

Opens a system file picker dialog for the user to browse and select a GGUF model file.

**Steps:**

1. Opens `FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false)`.
2. If the user cancels, returns `null`.
3. Verifies the selected file exists on disk.
4. **Size validation:** Rejects files smaller than `10 MB`. A valid quantized model is always hundreds of megabytes; a file below this threshold is almost certainly empty or incorrectly selected.
5. **Extension check:** Warns (but does not reject) if the file does not have a `.gguf` extension, accommodating renamed files.
6. Sets `_modelPath` and returns the path string on success.
7. Returns `null` on any error (file not found, picker exception, etc.).

**Why `FileType.any`?**  
Android's `FilePicker` with `FileType.any` ensures users can navigate to arbitrary locations including external storage, downloads, and mounted drives where large model files are commonly stored. Restricting to a custom extension type would limit browsability on some Android versions.

---

### `setCustomModelPath(String path)`

```dart
void setCustomModelPath(String path)
```

Directly sets `_modelPath` without opening a file picker. Used programmatically when a model path is already known (e.g., from a hardcoded default or a previous session path stored elsewhere).

---

### `checkModelExists()`

```dart
Future<bool> checkModelExists()
```

Returns `true` if `_modelPath` is non-null and the file at that path exists. Used by `ChatService` to verify a previously selected model is still present (e.g., user hasn't deleted it from storage).

---

## Validation Rules

| Check | Threshold | Action on Failure |
|---|---|---|
| File exists on disk | — | Return `null` |
| File size | ≥ 10 MB | Return `null`, log diagnostic |
| File extension | `.gguf` | Log warning, continue |

---

## Android Permission Handling

| Android Version | Permission Strategy |
|---|---|
| API ≤ 32 (Android 12 and below) | `Permission.storage` |
| API 33+ (Android 13+) | `Permission.storage` → fallback to `Permission.manageExternalStorage` |

The app will still attempt to operate if permissions are not granted, relying on scoped storage access for files the user explicitly picks via the system file picker (which bypasses permission requirements on modern Android versions).

---

## State

```dart
String? get modelPath
```

Returns the currently selected model file path, or `null` if no model has been selected in this session.

---

## Related Docs

- [ChatService](chat_service.md) — calls `initialize()`, `pickLocalModel()`, and reads `modelPath`
