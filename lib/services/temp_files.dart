import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// ملفات مؤقتة (صوت/مرفقات بعد فك التشفير). بتتمسح عند الخروج من الشات وعند فتح التطبيق.
class TempFiles {
  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/sc_plain');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> newPath(String name) async =>
      '${(await _dir()).path}/${_safe(name)}';

  static Future<File> write(String name, Uint8List bytes) async {
    final f = File(await newPath(name));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<void> clear() async {
    try {
      final base = await getTemporaryDirectory();
      final d = Directory('${base.path}/sc_plain');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static String _safe(String n) =>
      n.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
}
