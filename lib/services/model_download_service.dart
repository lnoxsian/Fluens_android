import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

class ModelDownloadService {
  late Directory _modelDirectory;
  String? _modelPath;
  
  Future<bool> initialize() async {
    debugPrint('[ModelDownload] Initializing model download service...');
    
    // Request storage permission (handles both old and new Android versions)
    debugPrint('[ModelDownload] Requesting storage permission...');
    var status = await Permission.storage.request();
    debugPrint('[ModelDownload] Storage permission status: $status');
    
    // For Android 13+ (API 33+), also request manageExternalStorage
    if (status != PermissionStatus.granted) {
      debugPrint('[ModelDownload] Storage permission not granted, requesting manageExternalStorage...');
      status = await Permission.manageExternalStorage.request();
      debugPrint('[ModelDownload] ManageExternalStorage permission status: $status');
    }
    
    if (status != PermissionStatus.granted) {
      debugPrint('[ModelDownload] ⚠ Warning: Storage permission not granted: $status');
    } else {
      debugPrint('[ModelDownload] ✓ Storage permission granted');
    }
    
    // Get app documents directory
    debugPrint('[ModelDownload] Getting application documents directory...');
    _modelDirectory = await getApplicationDocumentsDirectory();
    debugPrint('[ModelDownload] Documents directory: ${_modelDirectory.path}');
    
    // Initially we don't have a model selected
    debugPrint('[ModelDownload] Initialization complete. No model selected by default.');
    return false;
  }
  
  String? get modelPath => _modelPath;
  
  /// Set custom model path from user-selected file
  void setCustomModelPath(String path) {
    _modelPath = path;
  }
  
  /// Pick a model file from local storage
  Future<String?> pickLocalModel() async {
    debugPrint('[ModelDownload] Starting file picker...');
    try {
      debugPrint('[ModelDownload] Opening file picker dialog with FileType.any');
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select GGUF Model File',
        allowMultiple: false,
      );
      
      debugPrint('[ModelDownload] File picker result: ${result != null ? "Got result" : "null"}');
      
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        
        debugPrint('[ModelDownload] Selected file path: $filePath');
        debugPrint('[ModelDownload] Checking if file exists...');
        
        if (await file.exists()) {
          final fileSize = await file.length();
          final fileSizeMB = fileSize / 1024 / 1024;
          debugPrint('[ModelDownload] ✓ File exists! Size: ${fileSizeMB.toStringAsFixed(2)} MB ($fileSize bytes)');
          
          // Validate file size
          if (fileSize < 10 * 1024 * 1024) {
            debugPrint('[ModelDownload] ✗✗✗ ERROR: File is too small (${fileSizeMB.toStringAsFixed(2)} MB)');
            debugPrint('[ModelDownload] ✗ A valid GGUF model should be at least 100+ MB');
            debugPrint('[ModelDownload] ✗ This file is likely empty or corrupted');
            return null;
          }
          
          debugPrint('[ModelDownload] ✓ File size is valid');
          
          // Optionally validate that it's a .gguf file
          if (!filePath.toLowerCase().endsWith('.gguf')) {
            debugPrint('[ModelDownload] ⚠ Warning: Selected file does not have .gguf extension: $filePath');
            debugPrint('[ModelDownload] ⚠ Continuing anyway - make sure this is a valid GGUF model');
          } else {
            debugPrint('[ModelDownload] ✓ File has .gguf extension');
          }
          
          _modelPath = filePath;
          debugPrint('[ModelDownload] ✓ Model path set successfully: $filePath');
          return filePath;
        } else {
          debugPrint('[ModelDownload] ✗ Error: File does not exist at path: $filePath');
        }
      } else {
        debugPrint('[ModelDownload] ✗ No file selected or path is null');
      }
      return null;
    } catch (e) {
      debugPrint('[ModelDownload] ✗✗✗ Error picking model file: $e');
      debugPrint('[ModelDownload] Stack trace: ${StackTrace.current}');
      return null;
    }
  }
  
  Future<bool> checkModelExists() async {
    if (_modelPath == null) {
      return false;
    }
    return File(_modelPath!).existsSync();
  }
}