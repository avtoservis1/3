import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_WEB_API_KEY',
    authDomain: 'REPLACE_WITH_YOUR_PROJECT.firebaseapp.com',
    projectId: 'avtoservis-app',
    storageBucket: 'avtoservis-app.firebasestorage.app',
    messagingSenderId: '534987148245',
    appId: 'REPLACE_WITH_YOUR_WEB_APP_ID',
    measurementId: 'REPLACE_WITH_YOUR_MEASUREMENT_ID',
  );
}