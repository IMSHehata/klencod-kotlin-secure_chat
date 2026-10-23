import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum KeyStatus { firstUse, same, changed }

/// التشفير من طرف لطرف:
///  - كل جهاز بيولّد زوج مفاتيح X25519، والمفتاح الخاص بيفضل في Keystore بتاع أندرويد.
///  - المفتاح العام بس هو اللي بيترفع.
///  - المفتاح المشترك = X25519(مفتاحي الخاص، مفتاح الطرف التاني العام) ثم HKDF-SHA256.
///  - كل رسالة/ملف بيتشفّر بـ AES-256-GCM ومعاه nonce عشوائي.
class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  final _x25519 = X25519();
  final _aes = AesGcm.with256bits();
  final _storage = const FlutterSecureStorage();

  SimpleKeyPair? _keyPair;
  SecretKey? _sessionKey;
  String _partnerPubB64 = '';

  /// كود الأمان اللي الاتنين بيقارنوه للتأكد إن مفيش حد في النص.
  String safetyNumber = '';

  /// بيرجّع المفتاح العام (base64) بتاعي.
  Future<String> loadOrCreateIdentity(String uid) async {
    final privKey = 'priv_$uid';
    final pubKey = 'pub_$uid';
    final priv = await _storage.read(key: privKey);
    final pub = await _storage.read(key: pubKey);

    if (priv != null && pub != null) {
      _keyPair = SimpleKeyPairData(
        base64Decode(priv),
        publicKey: SimplePublicKey(base64Decode(pub), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
      return pub;
    }

    final kp = await _x25519.newKeyPair();
    final data = await kp.extract();
    final privBytes = await data.extractPrivateKeyBytes();
    final pubB64 = base64Encode(data.publicKey.bytes);
    await _storage.write(key: privKey, value: base64Encode(privBytes));
    await _storage.write(key: pubKey, value: pubB64);
    _keyPair = data;
    return pubB64;
  }

  /// بيحسب المفتاح المشترك مع الطرف التاني، وبيرجّع هل مفتاحه اتغيّر عن آخر مرة.
  Future<KeyStatus> setPartnerKey(String myUid, List<int> theirPub) async {
    final kp = _keyPair!;
    final myPub = (await kp.extractPublicKey()).bytes;
    final a = base64Encode(myPub);
    final b = base64Encode(theirPub);
    final mineFirst = a.compareTo(b) <= 0;
    final salt = <int>[
      ...(mineFirst ? myPub : theirPub),
      ...(mineFirst ? theirPub : myPub),
    ];

    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(theirPub, type: KeyPairType.x25519),
    );
    _sessionKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode('securechat/v1'),
    );

    final digest = await Sha256().hash(salt);
    final hex = digest.bytes
        .take(15)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    safetyNumber = [
      for (var i = 0; i < hex.length; i += 5) hex.substring(i, i + 5),
    ].join(' ');

    _partnerPubB64 = b;
    final storeKey = 'partner_pub_$myUid';
    final known = await _storage.read(key: storeKey);
    if (known == null) {
      await _storage.write(key: storeKey, value: b);
      return KeyStatus.firstUse;
    }
    return known == b ? KeyStatus.same : KeyStatus.changed;
  }

  /// بعد ما المستخدم يأكد إنه قارن كود الأمان مع الطرف التاني.
  Future<void> acceptPartnerKey(String myUid) =>
      _storage.write(key: 'partner_pub_$myUid', value: _partnerPubB64);

  Future<Uint8List> encryptBytes(List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: _sessionKey!);
    return Uint8List.fromList(box.concatenation());
  }

  Future<Uint8List> decryptBytes(List<int> data) async {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _aes.decrypt(box, secretKey: _sessionKey!);
    return Uint8List.fromList(clear);
  }

  Future<String> encryptString(String s) async =>
      base64Encode(await encryptBytes(utf8.encode(s)));

  Future<String> decryptString(String b64) async =>
      utf8.decode(await decryptBytes(base64Decode(b64)));
}
