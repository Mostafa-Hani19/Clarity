
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '420246631473',
    projectId: 'clarity-app-1d42c',
    authDomain: 'clarity-app-1d42c.firebaseapp.com',
    storageBucket: 'clarity-app-1d42c.firebasestorage.app',
    measurementId: 'G-X47TD9657Z',
  );

  // IMPORTANT: Replace these with values from your Firebase project

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '420246631473',
    projectId: 'clarity-app-1d42c',
    storageBucket: 'clarity-app-1d42c.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '',
    appId: '1::ios:7b6cce1097471e2be05110',
    messagingSenderId: '420246631473',
    projectId: 'clarity-app-1d42c',
    storageBucket: 'clarity-app-1d42c.firebasestorage.app',
    iosBundleId: 'com.clarity.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: '',
    appId: ':',
    messagingSenderId: '420246631473',
    projectId: 'clarity-app-1d42c',
    storageBucket: 'clarity-app-1d42c.firebasestorage.app',
    iosBundleId: 'com.clarity.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '420246631473',
    projectId: 'clarity-app-1d42c',
    authDomain: 'clarity-app-1d42c.firebaseapp.com',
    storageBucket: 'clarity-app-1d42c.firebasestorage.app',
    measurementId: 'G-SBQL60S793',
  );

} 