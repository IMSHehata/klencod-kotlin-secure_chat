import 'package:firebase_core/firebase_core.dart';

/// الصق هنا بيانات مشروع Firebase بتاعك (من إعدادات المشروع > تطبيق Android).
/// القيم دي مش أسرار؛ الحماية الحقيقية في ملفات القواعد firestore.rules و storage.rules.
const firebaseOptions = FirebaseOptions(
  apiKey: 'PASTE_API_KEY', // current_key في google-services.json
  appId: 'PASTE_APP_ID', // mobilesdk_app_id
  messagingSenderId: 'PASTE_SENDER_ID', // project_number
  projectId: 'PASTE_PROJECT_ID', // project_id
  storageBucket: 'PASTE_STORAGE_BUCKET', // storage_bucket
);
