// lib/firebase_options.dart
// Generated manually from google-services.json
// DO NOT EDIT — regenerate with flutterfire configure if possible

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS not configured yet');
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAR--wtaYDyHU4u6Hr7DQ3Anfewjz_m-oQ',
    appId:             '1:870739395964:android:5c9e635fe8c58f771010f9',
    messagingSenderId: '870739395964',
    projectId:         'kanmon-5e624',
    storageBucket:     'kanmon-5e624.firebasestorage.app',
  );
}
