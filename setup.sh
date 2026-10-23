#!/usr/bin/env bash
# بيجهّز مشروع أندرويد حوالين كود Flutter: بيولّد فولدر android وبيضبط الصلاحيات.
# شغّله مرة واحدة من جذر المشروع:  bash setup.sh
set -euo pipefail
cd "$(dirname "$0")"

if grep -q "PASTE_" lib/firebase_config.dart; then
  echo "⚠️  املا بيانات Firebase في lib/firebase_config.dart الأول (القيم اللي فيها PASTE_)."
  exit 1
fi

command -v flutter >/dev/null || { echo "Flutter مش متسطّب. شوف README.md"; exit 1; }

# flutter create ممكن يلمس الملفات الموجودة، فبنعمل نسخة احتياطية ونرجّعها
BAK="$(mktemp -d)"
cp -r lib "$BAK/lib"
cp pubspec.yaml "$BAK/pubspec.yaml"

flutter create --org com.securechat --project-name secure_chat --platforms=android .

rm -rf lib && cp -r "$BAK/lib" lib
cp "$BAK/pubspec.yaml" pubspec.yaml
rm -rf test

# ---- AndroidManifest: صلاحيات + منع النسخ الاحتياطي ----
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "RECORD_AUDIO" "$MANIFEST"; then
  sed -i '0,/<application/s|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application\n        android:allowBackup="false"|' "$MANIFEST"
fi

# ---- minSdk 23 (مطلوب للتخزين الآمن والتسجيل) ----
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] || continue
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' "$f"
done

# ---- منع لقطات الشاشة (FLAG_SECURE) ----
KT_DIR="android/app/src/main/kotlin/com/securechat/secure_chat"
mkdir -p "$KT_DIR"
cat > "$KT_DIR/MainActivity.kt" <<'EOF'
package com.securechat.secure_chat

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }
}
EOF

flutter pub get
echo
echo "✅ جاهز. لبناء ملف APK:  flutter build apk --release"
echo "   الناتج: build/app/outputs/flutter-apk/app-release.apk"
