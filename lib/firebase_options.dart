import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Placeholder FirebaseOptions.
/// YOU MUST REPLACE THIS FILE by running:
/// `flutterfire configure`
/// in your terminal to connect to your real Firebase project.
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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB1hZS0pu62LYFzZpsktUHCgpE71tyhfQY',
    appId: '1:807371083430:web:c55a761ae9d60394a62e67',
    messagingSenderId: '807371083430',
    projectId: 'xmoapp-6ef05',
    authDomain: 'xmoapp-6ef05.firebaseapp.com',
    storageBucket: 'xmoapp-6ef05.firebasestorage.app',
    measurementId: 'G-J8NEERNGHS',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBvC2G_OVJ0iQm0WgxumhW9NmHoe3RjHWU',
    appId: '1:807371083430:android:8ba0516138b2fb3aa62e67',
    messagingSenderId: '807371083430',
    projectId: 'xmoapp-6ef05',
    storageBucket: 'xmoapp-6ef05.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCDC-O7SGJwXmhIiIg92ETXN8oPMQLQezs',
    appId: '1:807371083430:ios:4a3cd5daa07d3bc8a62e67',
    messagingSenderId: '807371083430',
    projectId: 'xmoapp-6ef05',
    storageBucket: 'xmoapp-6ef05.firebasestorage.app',
    iosBundleId: 'com.xmo.xmo',
  );

}
