import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models.dart';
import 'crypto_service.dart';

class ChatService {
  ChatService({required this.myUid, required this.partnerUid})
      : chatId = chatIdFor(myUid, partnerUid);

  final String myUid;
  final String partnerUid;
  final String chatId;

  final _db = FirebaseFirestore.instance;
  final _crypto = CryptoService.instance;
  final Map<String, Payload?> _decryptCache = {};
  final Map<String, Future<Uint8List>> _mediaCache = {};

  static String chatIdFor(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      _db.collection('chats').doc(chatId);
  CollectionReference<Map<String, dynamic>> get _msgs =>
      _chatRef.collection('messages');

  /// بينشئ غرفة الشات لو مش موجودة (الاتنين أعضاء فيها بس).
  Future<void> ensureChat() {
    final members = [myUid, partnerUid]..sort();
    return _chatRef.set({'members': members}, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> chatStream() =>
      _chatRef.snapshots();

  Stream<List<ChatMessage>> messages() {
    return _msgs
        .orderBy('ts', descending: true)
        .limit(300)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snap) => Future.wait(snap.docs.map(_toMessage)));
  }

  Future<ChatMessage> _toMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) async {
    final m = d.data();
    final c = (m['c'] as String?) ?? '';
    final deleted = m['deleted'] == true;

    var payload = Payload.empty;
    var failed = false;
    if (!deleted && c.isNotEmpty) {
      final key = '${d.id}|$c';
      if (_decryptCache.containsKey(key)) {
        final cached = _decryptCache[key];
        if (cached == null) {
          failed = true;
        } else {
          payload = cached;
        }
      } else {
        try {
          final json = await _crypto.decryptString(c);
          payload = Payload.fromJson(jsonDecode(json) as Map<String, dynamic>);
          _decryptCache[key] = payload;
        } catch (_) {
          _decryptCache[key] = null;
          failed = true;
        }
      }
    }

    final ts = (m['ts'] as Timestamp?)?.toDate() ?? DateTime.now();
    final reactions = <String, String>{};
    final r = m['reactions'];
    if (r is Map) {
      r.forEach((k, v) => reactions['$k'] = '$v');
    }

    return ChatMessage(
      id: d.id,
      sender: (m['sender'] as String?) ?? '',
      ts: ts,
      pending: d.metadata.hasPendingWrites,
      edited: m['edited'] == true,
      deleted: deleted,
      reactions: reactions,
      payload: payload,
      decryptFailed: failed,
    );
  }

  Future<void> send(Payload p) async {
    final c = await _crypto.encryptString(jsonEncode(p.toJson()));
    await _msgs.add({
      'sender': myUid,
      'ts': FieldValue.serverTimestamp(),
      'c': c,
      'edited': false,
      'deleted': false,
      'reactions': <String, String>{},
    });
  }

  Future<void> edit(ChatMessage m, String newText) async {
    final c = await _crypto
        .encryptString(jsonEncode(m.payload.withText(newText).toJson()));
    await _msgs.doc(m.id).update({'c': c, 'edited': true});
  }

  /// حذف للطرفين: بنفضّي المحتوى المشفّر ونحذف الملف من Storage.
  Future<void> deleteForEveryone(ChatMessage m, {String? pinnedId}) async {
    await _msgs.doc(m.id).update({
      'deleted': true,
      'c': '',
      'reactions': <String, String>{},
    });
    if (pinnedId == m.id) await pin(null);
    final f = m.payload.file;
    if (f != null) {
      try {
        await FirebaseStorage.instance.ref(f.path).delete();
      } catch (_) {}
    }
  }

  Future<void> react(ChatMessage m, String emoji) {
    final mine = m.reactions[myUid];
    return _msgs.doc(m.id).update({
      'reactions.$myUid': mine == emoji ? FieldValue.delete() : emoji,
    });
  }

  Future<void> pin(String? messageId) => _chatRef.update({
        'pinnedId': messageId ?? FieldValue.delete(),
      });

  Future<void> markRead() =>
      _chatRef.update({'read.$myUid': FieldValue.serverTimestamp()});

  // ---------------- الملفات ----------------

  Future<FileInfo> upload({
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final enc = await _crypto.encryptBytes(bytes);
    final path = 'chats/$chatId/'
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}.bin';
    await FirebaseStorage.instance.ref(path).putData(
          enc,
          SettableMetadata(contentType: 'application/octet-stream'),
        );
    return FileInfo(path: path, name: name, mime: mime, size: bytes.length);
  }

  /// بينزّل الملف المشفّر ويفك تشفيره (مع كاش علشان ميتحمّلش مرتين).
  Future<Uint8List> media(String path) {
    final existing = _mediaCache[path];
    if (existing != null) return existing;
    final f = _download(path);
    _mediaCache[path] = f;
    f.catchError((_) {
      _mediaCache.remove(path);
      return Uint8List(0);
    });
    return f;
  }

  Future<Uint8List> _download(String path) async {
    final data = await FirebaseStorage.instance.ref(path).getData(40 * 1024 * 1024);
    if (data == null) throw Exception('الملف مش موجود');
    return _crypto.decryptBytes(data);
  }
}
