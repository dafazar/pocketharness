// DART/FLUTTER FIX - Model Loading with Proper Error Handling
// File: lib/services/llama_service.dart atau model_manager.dart

import 'dart:io';
import 'package:flutter/services.dart';

class LlamaService {
  static const platform = MethodChannel('com.kanmongo.llama/engine');
  static const eventChannel = EventChannel('com.kanmongo.llama/stream');
  
  bool _modelLoaded = false;
  bool get isModelLoaded => _modelLoaded;

  /// 🆕 FIX: Proper model loading dengan validasi & error handling lengkap
  Future<bool> loadModel({
    required String modelPath,
    int contextSize = 2048,
    int gpuLayers = 0,
    int nBatch = 512,
    int nThreads = 4,
    bool useFlashAttn = false,
    bool memLock = false,
    double ropeBase = 0.0,
    double ropeScale = 1.0,
  }) async {
    try {
      print('[LlamaService] loadModel START: $modelPath');
      
      // ─── STEP 1: Validate file path ───────────────────────────────────
      if (modelPath.isEmpty) {
        throw Exception('Model path is empty');
      }
      
      final file = File(modelPath);
      
      // Check file exists
      if (!await file.exists()) {
        throw Exception('Model file not found: $modelPath');
      }
      
      // Check file size
      final size = await file.length();
      final sizeMb = size / (1024 * 1024);
      print('[LlamaService] File size: ${sizeMb.toStringAsFixed(1)} MB');
      
      if (size == 0) {
        throw Exception('Model file is empty (0 bytes)');
      }
      
      if (size < 50 * 1024 * 1024) {
        print('[LlamaService] ⚠️  WARNING: File seems too small (${sizeMb.toStringAsFixed(1)}MB)');
      }
      
      // Check GGUF magic
      final raf = RandomAccessFile(modelPath);
      try {
        final magic = await raf.read(4);
        if (magic.length < 4 || 
            magic[0] != 71 || magic[1] != 71 ||   // 'GG'
            magic[2] != 85 || magic[3] != 70) {   // 'UF'
          throw Exception('Invalid GGUF file format (magic bytes check failed)');
        }
      } finally {
        await raf.close();
      }
      
      print('[LlamaService] ✓ File validation passed');
      
      // ─── STEP 2: Call native method with error handling ──────────────
      print('[LlamaService] Calling native loadModel...');
      
      final result = await platform.invokeMethod<Map>('loadModel', {
        'modelPath': modelPath,
        'contextSize': contextSize,
        'gpuLayers': gpuLayers,
        'nBatch': nBatch,
        'nThreads': nThreads,
        'useFlashAttn': useFlashAttn,
        'memLock': memLock,
        'ropeBase': ropeBase,
        'ropeScale': ropeScale,
      });
      
      // ─── STEP 3: Validate response ─────────────────────────────────
      if (result == null) {
        throw Exception('loadModel returned null from native layer');
      }
      
      final handle = result['handle'];
      if (handle == null || handle == 0) {
        throw Exception(
          'Native model loading failed (returned handle=0). '
          'Check Android logcat: adb logcat | grep -E "LlamaJNI|LlamaPlugin"'
        );
      }
      
      print('[LlamaService] ✅ Model loaded successfully');
      print('[LlamaService]   - Handle: $handle');
      print('[LlamaService]   - Context size: ${result['contextSize']}');
      print('[LlamaService]   - File size: ${result['fileSizeMb']}MB');
      
      _modelLoaded = true;
      return true;
      
    } on PlatformException catch (e) {
      print('[LlamaService] ❌ PLATFORM EXCEPTION');
      print('[LlamaService]   Code: ${e.code}');
      print('[LlamaService]   Message: ${e.message}');
      print('[LlamaService]   Details: ${e.details}');
      
      // Interpret error code
      String errorMsg = e.message ?? 'Unknown error';
      
      if (e.code == 'LLAMA_ERROR') {
        if (errorMsg.contains('file not found') || errorMsg.contains('No read permission')) {
          errorMsg = 'File path error: $errorMsg';
        } else if (errorMsg.contains('insufficient memory')) {
          errorMsg = 'Not enough RAM available: $errorMsg';
        } else if (errorMsg.contains('returned 0') || errorMsg.contains('failed')) {
          errorMsg = 'Model loading failed. '
              'Check logcat for detailed error:\n'
              'adb logcat | grep LlamaJNI';
        }
      }
      
      _modelLoaded = false;
      rethrow;
      
    } catch (e) {
      print('[LlamaService] ❌ UNEXPECTED ERROR: $e');
      _modelLoaded = false;
      rethrow;
    }
  }

  /// 🆕 FIX: Release model dengan proper cleanup
  Future<void> releaseModel() async {
    try {
      print('[LlamaService] releaseModel START');
      await platform.invokeMethod('releaseModel');
      _modelLoaded = false;
      print('[LlamaService] Model released');
    } catch (e) {
      print('[LlamaService] releaseModel error: $e');
    }
  }

  /// 🆕 FIX: Check if model is actually loaded
  Future<bool> isModelLoaded() async {
    try {
      final result = await platform.invokeMethod<bool>('isModelLoaded');
      return result ?? false;
    } catch (e) {
      print('[LlamaService] isModelLoaded error: $e');
      return false;
    }
  }

  /// 🆕 FIX: Generate tokens dengan proper event listening
  Future<void> generateTokens({
    required String prompt,
    required void Function(String token) onToken,
    required void Function() onComplete,
    required void Function(String error) onError,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    int maxTokens = 512,
    int seq = 0,
  }) async {
    try {
      // Listen untuk events dari native layer
      eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is! Map) return;
          
          final type = event['type'] as String?;
          
          switch (type) {
            case 'token':
              final token = event['token'] as String? ?? '';
              onToken(token);
              break;
              
            case 'done':
              print('[LlamaService] Generation complete');
              onComplete();
              break;
              
            case 'error':
              final errorMsg = event['message'] as String? ?? 'Unknown error';
              print('[LlamaService] Generation error: $errorMsg');
              onError(errorMsg);
              break;
              
            case 'loading_progress':
              final progress = event['progress'] as double? ?? 0.0;
              print('[LlamaService] Loading progress: ${(progress * 100).toStringAsFixed(1)}%');
              break;
              
            case 'model_loaded':
              print('[LlamaService] Model loaded event received');
              break;
              
            case 'memory_warning':
              final availMb = event['availableMb'] as int? ?? 0;
              print('[LlamaService] ⚠️  Memory warning: ${availMb}MB available');
              break;
          }
        },
        onError: (error) {
          print('[LlamaService] Event stream error: $error');
          onError(error.toString());
        },
      );
      
      // Call native generation
      print('[LlamaService] generateTokens START - prompt length: ${prompt.length}');
      
      await platform.invokeMethod('generateTokens', {
        'prompt': prompt,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'maxTokens': maxTokens,
        'seq': seq,
        'repeatPenalty': 1.1,
        'seed': -1,
        'mirostatMode': 0,
        'mirostatTau': 5.0,
        'mirostatEta': 0.1,
        'minP': 0.05,
        'penalizeNl': false,
      });
      
    } catch (e) {
      print('[LlamaService] generateTokens error: $e');
      onError(e.toString());
    }
  }

  /// 🆕 FIX: Get available memory
  Future<int> getAvailableMemoryMb() async {
    try {
      final result = await platform.invokeMethod<int>('getAvailableMemoryMb');
      return result ?? 0;
    } catch (e) {
      print('[LlamaService] getAvailableMemoryMb error: $e');
      return 0;
    }
  }

  /// 🆕 FIX: Get system info
  Future<Map<String, dynamic>> getSystemInfo() async {
    try {
      final result = await platform.invokeMethod<Map>('getSystemInfo');
      return result?.cast<String, dynamic>() ?? {};
    } catch (e) {
      print('[LlamaService] getSystemInfo error: $e');
      return {};
    }
  }

  /// 🆕 FIX: Diagnostic helper - check everything before loading
  Future<String> diagnosticCheck(String modelPath) async {
    final diagnostics = StringBuffer();
    
    diagnostics.writeln('╔═══════════════════════════════════════════════════╗');
    diagnostics.writeln('║        KanMon AI - Diagnostic Check               ║');
    diagnostics.writeln('╚═══════════════════════════════════════════════════╝\n');
    
    // Check file
    diagnostics.writeln('📁 File Check:');
    try {
      final file = File(modelPath);
      if (await file.exists()) {
        final size = await file.length();
        diagnostics.writeln('  ✓ File exists');
        diagnostics.writeln('  ✓ Size: ${(size / (1024*1024)).toStringAsFixed(1)} MB');
      } else {
        diagnostics.writeln('  ✗ File not found: $modelPath');
      }
    } catch (e) {
      diagnostics.writeln('  ✗ Error checking file: $e');
    }
    
    // Check memory
    diagnostics.writeln('\n💾 Memory:');
    try {
      final availMb = await getAvailableMemoryMb();
      diagnostics.writeln('  ✓ Available RAM: $availMb MB');
    } catch (e) {
      diagnostics.writeln('  ✗ Error checking memory: $e');
    }
    
    // Check system
    diagnostics.writeln('\n🖥️  System:');
    try {
      final info = await getSystemInfo();
      diagnostics.writeln('  ✓ Total RAM: ${info['totalRamMb']} MB');
      diagnostics.writeln('  ✓ Available RAM: ${info['availableRamMb']} MB');
      diagnostics.writeln('  ✓ CPU cores: ${info['cpuCores']}');
      diagnostics.writeln('  ✓ GPU available: ${info['gpuAvailable']}');
    } catch (e) {
      diagnostics.writeln('  ✗ Error getting system info: $e');
    }
    
    diagnostics.writeln('\n📋 Recommendations:');
    diagnostics.writeln('  1. Ensure model file is valid GGUF format');
    diagnostics.writeln('  2. Have at least 2GB RAM free for 7B model');
    diagnostics.writeln('  3. Close other apps to free memory');
    diagnostics.writeln('  4. Check logcat: adb logcat | grep LlamaJNI');
    
    return diagnostics.toString();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// UI Widget untuk display model loading dengan proper error handling
// ═════════════════════════════════════════════════════════════════════════════

class ModelLoadWidget extends StatefulWidget {
  final String modelPath;
  final VoidCallback onLoadComplete;

  const ModelLoadWidget({
    required this.modelPath,
    required this.onLoadComplete,
  });

  @override
  State<ModelLoadWidget> createState() => _ModelLoadWidgetState();
}

class _ModelLoadWidgetState extends State<ModelLoadWidget> {
  bool _isLoading = false;
  String? _errorMessage;
  double _progress = 0.0;
  final _llama = LlamaService();

  Future<void> _loadModel() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      // Show diagnostic info
      final diagnostics = await _llama.diagnosticCheck(widget.modelPath);
      print(diagnostics);
      
      // Load model
      final success = await _llama.loadModel(
        modelPath: widget.modelPath,
        contextSize: 2048,
        gpuLayers: 0,
        nBatch: 512,
        nThreads: 4,
      );
      
      if (success) {
        setState(() {
          _progress = 1.0;
        });
        
        // Delay untuk show success sebentar
        await Future.delayed(Duration(seconds: 1));
        
        widget.onLoadComplete();
      }
    } catch (e) {
      print('[UI] Model loading failed: $e');
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isLoading) ...[
          CircularProgressIndicator(value: _progress),
          SizedBox(height: 16),
          Text('Loading model... ${(_progress * 100).toStringAsFixed(0)}%'),
        ] else if (_errorMessage != null) ...[
          Icon(Icons.error_outline, color: Colors.red, size: 64),
          SizedBox(height: 16),
          Text('Loading failed:', style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade900, fontSize: 12),
            ),
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadModel,
            icon: Icon(Icons.refresh),
            label: Text('Retry'),
          ),
          SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final diagnostics = await _llama.diagnosticCheck(widget.modelPath);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(diagnostics)),
                );
              }
            },
            icon: Icon(Icons.info_outline),
            label: Text('Diagnostics'),
          ),
        ] else ...[
          Icon(Icons.upload_file, size: 64, color: Colors.blue),
          SizedBox(height: 16),
          Text('Load Model', style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 8),
          Text(widget.modelPath, style: TextStyle(fontSize: 12)),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadModel,
            icon: Icon(Icons.play_arrow),
            label: Text('Load'),
          ),
        ],
      ],
    );
  }
}
