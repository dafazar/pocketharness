// lib/data/services/permission_service.dart
//
// PocketHarness — PermissionService + StoragePermissionHelper
//
// Handles ALL Android permission variants:
//   API ≤ 28  → READ_EXTERNAL_STORAGE (legacy)
//   API 29    → READ_EXTERNAL_STORAGE (still works, requestLegacyExternalStorage=true)
//   API 30-32 → READ_EXTERNAL_STORAGE (maxSdkVersion=32 in manifest)
//   API 33    → READ_MEDIA_IMAGES + READ_MEDIA_VIDEO + READ_MEDIA_AUDIO
//   API 34+   → READ_MEDIA_VISUAL_USER_SELECTED (partial) or full media perms
//   API 30+   → MANAGE_EXTERNAL_STORAGE via MethodChannel (for GGUF model import)
//
// Key classes:
//   PermissionService        — singleton, used by onboarding screen
//   StoragePermissionHelper  — used by Model Manager + Chat Attachment Picker
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const _kPermOnboardingDone = 'kmg.perm.onboarding_done';

// MethodChannels registered in MainActivity.kt (Session 1)
const _kDeviceInfoChannel  = MethodChannel('pocketharness/device_info');
const _kStoragePermChannel = MethodChannel('pocketharness/storage_permission');

// ─────────────────────────────────────────────────────────────────────────────
// DEVICE INFO HELPER
// ─────────────────────────────────────────────────────────────────────────────

/// Returns Android SDK_INT. Cached after first call.
/// Returns 29 as a safe fallback if the channel fails.
int? _cachedSdkInt;

Future<int> getSdkInt() async {
  if (!Platform.isAndroid) return 0;
  if (_cachedSdkInt != null) return _cachedSdkInt!;
  try {
    final result = await _kDeviceInfoChannel.invokeMethod<int>('getSdkInt');
    _cachedSdkInt = result ?? 29;
  } catch (_) {
    _cachedSdkInt = 29;
  }
  return _cachedSdkInt!;
}

// ─────────────────────────────────────────────────────────────────────────────
// PermissionItem MODEL
// ─────────────────────────────────────────────────────────────────────────────

class PermissionItem {
  final Permission permission;
  final String title;
  final String subtitle;
  final String reason;
  final IconData icon;
  final Color color;
  final bool required;

  const PermissionItem({
    required this.permission,
    required this.title,
    required this.subtitle,
    required this.reason,
    required this.icon,
    required this.color,
    this.required = true,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PERMISSION LIST BUILDER
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the list of permissions shown during first-launch onboarding.
List<PermissionItem> buildPermissionList() {
  if (!Platform.isAndroid) return [];

  return [
    // ── Notifications ─────────────────────────────────────────────────────
    const PermissionItem(
      permission: Permission.notification,
      title: 'Notifications',
      subtitle: 'Daily study reminders',
      reason:
          'Pocket Harness sends daily reminders so you stay consistent with studying. '
          'You can disable them any time in Settings.',
      icon: Icons.notifications_rounded,
      color: Color(0xFF6366F1),
      required: false,
    ),

    // ── Photos / Images ───────────────────────────────────────────────────
    const PermissionItem(
      permission: Permission.photos,
      title: 'Photos & Images',
      subtitle: 'Choose wallpaper from gallery',
      reason:
          'This permission lets you pick a photo from your gallery to use as '
          'the background wallpaper in the main menu.',
      icon: Icons.photo_library_rounded,
      color: Color(0xFF10B981),
      required: false,
    ),

    // ── Videos ───────────────────────────────────────────────────────────
    const PermissionItem(
      permission: Permission.videos,
      title: 'Videos',
      subtitle: 'Use video as live wallpaper',
      reason:
          'This lets you select a video from your storage to use as an '
          'animated live wallpaper on the main menu screen.',
      icon: Icons.video_library_rounded,
      color: Color(0xFFF59E0B),
      required: false,
    ),

    // ── Audio / Documents ─────────────────────────────────────────────────
    const PermissionItem(
      permission: Permission.audio,
      title: 'Audio & Documents',
      subtitle: 'Open study materials from storage',
      reason:
          'Required to open study files (audio, PDF, documents) stored on '
          'your device through the Ebook and AI Chat features.',
      icon: Icons.folder_open_rounded,
      color: Color(0xFFE67E22),
      required: false,
    ),

    // ── Camera ───────────────────────────────────────────────────────────
    const PermissionItem(
      permission: Permission.camera,
      title: 'Camera',
      subtitle: 'Scan text with OCR',
      reason:
          'The OCR Scan feature needs your camera to let you photograph text '
          'and get an instant AI analysis.',
      icon: Icons.camera_alt_rounded,
      color: Color(0xFF0EA5E9),
      required: false,
    ),

    // ── Microphone ────────────────────────────────────────────────────────
    const PermissionItem(
      permission: Permission.microphone,
      title: 'Microphone',
      subtitle: 'Voice input for AI Interview',
      reason:
          'The AI Mensetsu feature needs your microphone so you can answer '
          'interview questions by speaking, just like a real interview.',
      icon: Icons.mic_rounded,
      color: Color(0xFF8B5CF6),
      required: false,
    ),

    // ── All Files Access (MANAGE_EXTERNAL_STORAGE) ────────────────────────
    const PermissionItem(
      permission: Permission.manageExternalStorage,
      title: 'All Files Access',
      subtitle: 'Import AI model files (GGUF) from Downloads',
      reason:
          'To load offline AI models, the app needs access to files anywhere '
          'on your storage — including your Downloads folder. '
          'On Android 11+, tap "Allow" and then enable "Allow access to all files" '
          'in the Settings page that opens.',
      icon: Icons.storage_rounded,
      color: Color(0xFFEF4444),
      required: false,
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// PermissionService — SINGLETON
// ─────────────────────────────────────────────────────────────────────────────

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  // ── Onboarding state ────────────────────────────────────────────────────

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPermOnboardingDone) ?? false;
  }

  Future<void> markOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermOnboardingDone, true);
  }

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPermOnboardingDone);
  }

  // ── Generic permission helpers ──────────────────────────────────────────

  Future<PermissionStatus> check(Permission permission) =>
      permission.status;

  Future<bool> isAlreadyGranted(Permission permission) async {
    // Special handling for MANAGE_EXTERNAL_STORAGE on API 30+
    if (permission == Permission.manageExternalStorage) {
      return StoragePermissionHelper.isManageExternalStorageGranted();
    }
    final status = await permission.status;
    return status.isGranted || status.isLimited;
  }

  Future<PermissionStatus> request(Permission permission) async {
    // MANAGE_EXTERNAL_STORAGE cannot be requested via permission_handler's
    // standard .request() — it opens a Settings page. Handle separately.
    if (permission == Permission.manageExternalStorage) {
      final granted = await StoragePermissionHelper
          .requestManageExternalStorageViaChannel();
      return granted ? PermissionStatus.granted : PermissionStatus.denied;
    }
    return permission.request();
  }

  Future<void> openSettings() => openAppSettings();
}

// ─────────────────────────────────────────────────────────────────────────────
// StoragePermissionHelper — UNIFIED ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────
//
// Used by:
//   - Model Manager screen (Session 6) before showing GGUF file picker
//   - Attachment Picker Sheet (Session 4) before picking any file
//
// Handles all Android API levels in one place.

class StoragePermissionHelper {

  StoragePermissionHelper._();

  // ── API-level aware storage permission check ───────────────────────────

  /// Returns true if the app has sufficient storage access to read
  /// files from external storage using File() paths (not SAF).
  static Future<bool> hasStorageReadPermission() async {
    if (!Platform.isAndroid) return true;

    final sdk = await getSdkInt();

    if (sdk >= 33) {
      // Android 13+: Granular media permissions. Check photos as representative.
      final status = await Permission.photos.status;
      return status.isGranted || status.isLimited;
    } else if (sdk >= 30) {
      // Android 11-12: MANAGE_EXTERNAL_STORAGE is the only way to get
      // real file paths. Fall back to SAF (content://) if not granted.
      return isManageExternalStorageGranted();
    } else {
      // API 29 and below: READ_EXTERNAL_STORAGE
      final status = await Permission.storage.status;
      return status.isGranted;
    }
  }

  /// Returns true if MANAGE_EXTERNAL_STORAGE is granted.
  /// On Android < 11 (API < 30), always returns true (not needed).
  static Future<bool> isManageExternalStorageGranted() async {
    if (!Platform.isAndroid) return true;
    final sdk = await getSdkInt();
    if (sdk < 30) return true; // Not needed below Android 11

    try {
      final result = await _kStoragePermChannel
          .invokeMethod<bool>('isManageExternalStorageGranted');
      return result ?? false;
    } catch (_) {
      // Channel not available — assume false to trigger request
      return false;
    }
  }

  /// Requests MANAGE_EXTERNAL_STORAGE by opening the system Settings page.
  /// Returns true if already granted, false if Settings was opened
  /// (caller must re-check after user returns using [isManageExternalStorageGranted]).
  static Future<bool> requestManageExternalStorageViaChannel() async {
    if (!Platform.isAndroid) return true;
    final sdk = await getSdkInt();
    if (sdk < 30) return true; // Not needed below Android 11

    try {
      final result = await _kStoragePermChannel
          .invokeMethod<bool>('requestManageExternalStorage');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Media permissions for Chat Attachment Picker ───────────────────────

  /// Requests the correct set of media permissions based on Android version.
  /// Returns a [MediaPermissionResult] indicating what was granted.
  ///
  /// API ≤ 32  → READ_EXTERNAL_STORAGE
  /// API 33    → READ_MEDIA_IMAGES + READ_MEDIA_VIDEO + READ_MEDIA_AUDIO
  /// API 34+   → READ_MEDIA_VISUAL_USER_SELECTED (partial) + audio
  static Future<MediaPermissionResult> requestMediaPermissions() async {
    if (!Platform.isAndroid) {
      return const MediaPermissionResult(images: true, video: true, audio: true);
    }

    final sdk = await getSdkInt();

    if (sdk >= 34) {
      // Android 14+: Prefer partial visual media access (user-selected)
      // combined with full audio. If user grants full, even better.
      final results = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.mediaLibrary, // maps to READ_MEDIA_VISUAL_USER_SELECTED on API 34+
      ].request();

      final imagesGranted =
          (results[Permission.photos]?.isGranted ?? false) ||
          (results[Permission.photos]?.isLimited ?? false) ||
          (results[Permission.mediaLibrary]?.isGranted ?? false) ||
          (results[Permission.mediaLibrary]?.isLimited ?? false);

      return MediaPermissionResult(
        images: imagesGranted,
        video: (results[Permission.videos]?.isGranted ?? false) ||
               (results[Permission.videos]?.isLimited ?? false),
        audio: results[Permission.audio]?.isGranted ?? false,
      );

    } else if (sdk >= 33) {
      // Android 13: Granular media permissions
      final results = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();

      return MediaPermissionResult(
        images: (results[Permission.photos]?.isGranted ?? false) ||
                (results[Permission.photos]?.isLimited ?? false),
        video: results[Permission.videos]?.isGranted ?? false,
        audio: results[Permission.audio]?.isGranted ?? false,
      );

    } else {
      // API ≤ 32: Single READ_EXTERNAL_STORAGE permission
      final status = await Permission.storage.request();
      final granted = status.isGranted;
      return MediaPermissionResult(
        images: granted,
        video:  granted,
        audio:  granted,
      );
    }
  }

  // ── Combined request for Model Manager (GGUF import) ───────────────────

  /// Ensures full storage access for reading GGUF files from arbitrary paths.
  /// Shows a dialog explaining why MANAGE_EXTERNAL_STORAGE is needed if
  /// [context] is provided. Returns true if the user should proceed.
  ///
  /// Strategy:
  ///   1. If MANAGE_EXTERNAL_STORAGE already granted → proceed
  ///   2. If API < 30 → request READ_EXTERNAL_STORAGE, proceed if granted
  ///   3. If API ≥ 30 → open Settings, return false (caller re-checks)
  static Future<StorageAccessResult> ensureModelImportAccess(
    BuildContext? context,
  ) async {
    if (!Platform.isAndroid) {
      return const StorageAccessResult(granted: true, needsSettings: false);
    }

    final sdk = await getSdkInt();

    // Already fully granted
    if (await isManageExternalStorageGranted()) {
      return const StorageAccessResult(granted: true, needsSettings: false);
    }

    if (sdk < 30) {
      // API 21-29: Request READ_EXTERNAL_STORAGE
      final status = await Permission.storage.request();
      if (status.isGranted) {
        return const StorageAccessResult(granted: true, needsSettings: false);
      }
      if (status.isPermanentlyDenied) {
        return const StorageAccessResult(granted: false, needsSettings: true);
      }
      return const StorageAccessResult(granted: false, needsSettings: false);
    }

    // API 30+: Must open Settings. Optionally show dialog first.
    if (context != null && context.mounted) {
      final shouldOpen = await _showManageStorageDialog(context);
      if (!shouldOpen) {
        return const StorageAccessResult(granted: false, needsSettings: false);
      }
    }

    await requestManageExternalStorageViaChannel();
    // After returning from Settings, the caller MUST re-check
    return const StorageAccessResult(granted: false, needsSettings: false);
  }

  // ── Dialog for MANAGE_EXTERNAL_STORAGE explanation ────────────────────

  static Future<bool> _showManageStorageDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.storage_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'All Files Access Required',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'To import AI model files (GGUF) from your Downloads folder or '
          'any location on your device, Pocket Harness needs the '
          '"Allow access to all files" permission.\n\n'
          'Tap "Open Settings" below, then enable '
          '"Allow access to all files" for Pocket Harness.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── SAF fallback check ─────────────────────────────────────────────────

  /// Returns true if the app should use Storage Access Framework (SAF) /
  /// content:// URIs instead of File() paths.
  ///
  /// This is the case on Android 10+ when MANAGE_EXTERNAL_STORAGE is NOT granted.
  static Future<bool> shouldUseSAFFallback() async {
    if (!Platform.isAndroid) return false;
    final sdk = await getSdkInt();
    if (sdk < 30) return false;
    return !(await isManageExternalStorageGranted());
  }

  // ── requestForGgufImport (used by Model Manager) ─────────────────────────

  /// Ensures storage access for GGUF model import via FilePicker.
  ///
  /// API 30+: SAF-based pickers don't need any permission — return true.
  ///          Optionally request MANAGE_EXTERNAL_STORAGE for direct path.
  /// API ≤ 29: Need READ_EXTERNAL_STORAGE.
  static Future<bool> requestForGgufImport({
    BuildContext? context,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdk = await getSdkInt();

    // API 30+: SAF handles file picking without any permission.
    // Optionally try MANAGE_EXTERNAL_STORAGE for better path access.
    if (sdk >= 30) {
      // Non-blocking: try to get full access for better UX, but proceed anyway.
      final alreadyGranted = await isManageExternalStorageGranted();
      if (!alreadyGranted && context != null && context.mounted) {
        // Show dialog and open settings — caller will re-check on resume.
        // But SAF will still work even if user denies, so we return true.
        await ensureModelImportAccess(context);
      }
      return true; // SAF always works on API 30+
    }

    // API ≤ 29: Need READ_EXTERNAL_STORAGE
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && context != null && context.mounted) {
      await openAppSettings();
    }
    return false;
  }

  // ── requestForMediaRead (used by Attachment Picker Sheet) ─────────────────

  /// Requests read permission for a specific media type.
  /// Returns true if permission is granted (or not needed).
  ///
  /// API 33+: Requests READ_MEDIA_IMAGES / READ_MEDIA_VIDEO / READ_MEDIA_AUDIO
  ///          (except images on API 33+: system Photo Picker needs no permission)
  /// API ≤ 32: Requests READ_EXTERNAL_STORAGE
  static Future<bool> requestForMediaRead(
    MediaType type, {
    BuildContext? context,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdk = await getSdkInt();

    if (sdk >= 33) {
      // Images: system Photo Picker (ImagePicker) — no permission needed on API 33+
      if (type == MediaType.images) return true;

      // Audio / Video: need specific media permission
      final perm = type == MediaType.audio
          ? Permission.audio
          : Permission.videos;
      final status = await perm.request();
      if (status.isGranted || status.isLimited) return true;
      if (status.isPermanentlyDenied && context != null && context.mounted) {
        await openAppSettings();
      }
      return false;

    } else {
      // API ≤ 32: READ_EXTERNAL_STORAGE covers all media
      final status = await Permission.storage.request();
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied && context != null && context.mounted) {
        await openAppSettings();
      }
      return false;
    }
  }

  // ── requestForFileAccess (used by Document / Code / Archive / Any pickers) ─

  /// Requests file access for document/code/archive pickers.
  ///
  /// API 30+: SAF (no permission needed — FilePicker uses Intent.ACTION_OPEN_DOCUMENT)
  /// API 29:  READ_EXTERNAL_STORAGE (requestLegacyExternalStorage=true handles this)
  /// API ≤ 28: READ_EXTERNAL_STORAGE
  static Future<bool> requestForFileAccess({
    BuildContext? context,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdk = await getSdkInt();

    // API 30+: SAF-based pickers don't need any permission
    if (sdk >= 30) return true;

    // API ≤ 29: Need READ_EXTERNAL_STORAGE
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && context != null && context.mounted) {
      await openAppSettings();
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MediaType ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum MediaType { images, audio, video }

// ─────────────────────────────────────────────────────────────────────────────
// RESULT TYPES
// ─────────────────────────────────────────────────────────────────────────────

class MediaPermissionResult {
  final bool images;
  final bool video;
  final bool audio;

  const MediaPermissionResult({
    required this.images,
    required this.video,
    required this.audio,
  });

  /// Returns true if ANY media type was granted
  bool get anyGranted => images || video || audio;

  /// Returns true if ALL media types were granted
  bool get allGranted => images && video && audio;
}

class StorageAccessResult {
  /// True if access is already granted and the caller can proceed
  final bool granted;

  /// True if the user must go to Settings to grant permission (permanently denied)
  final bool needsSettings;

  const StorageAccessResult({
    required this.granted,
    required this.needsSettings,
  });
}
