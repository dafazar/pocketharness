import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tools_service.dart';
import 'native_tools_manager.dart';

/// Provides the singleton [ToolsService].
/// Use [toolsReadyProvider] to check if extraction is complete.
final toolsServiceProvider = Provider<ToolsService>((ref) {
  return ToolsService.instance;
});

/// AsyncNotifier that resolves to true once tools are extracted and ready.
final toolsReadyProvider = FutureProvider<bool>((ref) async {
  final svc = ref.read(toolsServiceProvider);
  if (svc.isReady) return true;
  await svc.initialize();
  return svc.isReady;
});

/// Provides the [ToolsManifest] once tools are ready. Null if not bundled.
final toolsManifestProvider = Provider<ToolsManifest?>((ref) {
  return ToolsService.instance.manifest;
});

/// Provides the singleton [NativeToolsManager].
final nativeToolsManagerProvider = Provider<NativeToolsManager>((ref) {
  return NativeToolsManager.instance;
});

/// Quick check: node + claude code present.
final toolsQuickReadyProvider = FutureProvider<bool>((ref) async {
  await ref.watch(toolsReadyProvider.future);
  return NativeToolsManager.instance.quickCheck();
});
