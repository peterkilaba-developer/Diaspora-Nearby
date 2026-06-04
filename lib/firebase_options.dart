import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
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
    apiKey: 'AIzaSyACyPyqHcgciP31rKqPTuS5jXAtyqpNkdU',
    appId: '1:512074182214:web:351bd07f62180977b92447',
    messagingSenderId: '512074182214',
    projectId: 'diaspora-nearby-a3dac',
    authDomain: 'diaspora-nearby-a3dac.firebaseapp.com',
    databaseURL: 'https://diaspora-nearby-a3dac-default-rtdb.firebaseio.com',
    storageBucket: 'diaspora-nearby-a3dac.firebasestorage.app',
    measurementId: 'G-0FD7KSDSSD',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAgWq-6gdzy6TxODM3WuUUmQ0zu7-6aVlc',
    appId: '1:512074182214:android:3a55dd7ec6825f2db92447',
    messagingSenderId: '512074182214',
    projectId: 'diaspora-nearby-a3dac',
    databaseURL: 'https://diaspora-nearby-a3dac-default-rtdb.firebaseio.com',
    storageBucket: 'diaspora-nearby-a3dac.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAnvuP6-HBvxxfSgNpiOR42lonoCTovhFw',
    appId: '1:512074182214:ios:60cf4efcfcb7d872b92447',
    messagingSenderId: '512074182214',
    projectId: 'diaspora-nearby-a3dac',
    databaseURL: 'https://diaspora-nearby-a3dac-default-rtdb.firebaseio.com',
    storageBucket: 'diaspora-nearby-a3dac.firebasestorage.app',
    iosBundleId: 'com.diasporanearby.diasporaFlutter',
  );
}
