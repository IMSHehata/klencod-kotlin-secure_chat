import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/crypto_service.dart';
import 'chat_screen.dart';
import 'pair_screen.dart';

class _Boot {
  const _Boot({
    required this.myUid,
    this.partnerUid,
    this.partnerEmail,
    this.keyStatus = KeyStatus.same,
  });

  final String myUid;
  final String? partnerUid;
  final String? partnerEmail;
  final KeyStatus keyStatus;
}

/// بيجهّز المفاتيح، وبيقرر يفتح شاشة الربط ولا الشات.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, required this.user});
  final User user;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<_Boot> _future = _load();

  Future<_Boot> _load() async {
    final uid = widget.user.uid;
    final crypto = CryptoService.instance;
    final db = FirebaseFirestore.instance;

    final myPub = await crypto.loadOrCreateIdentity(uid);
    final meRef = db.collection('users').doc(uid);
    await meRef.set({'email': widget.user.email, 'pub': myPub}, SetOptions(merge: true));

    final me = await meRef.get();
    final partnerUid = me.data()?['partner'] as String?;
    if (partnerUid == null) return _Boot(myUid: uid);

    final p = await db.collection('users').doc(partnerUid).get();
    final pd = p.data();
    if (pd == null || pd['pub'] == null) return _Boot(myUid: uid);

    final status = await crypto.setPartnerKey(uid, base64Decode(pd['pub'] as String));
    return _Boot(
      myUid: uid,
      partnerUid: partnerUid,
      partnerEmail: pd['email'] as String?,
      keyStatus: status,
    );
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 56),
                    const SizedBox(height: 12),
                    Text('مقدرناش نجهّز التطبيق:\n${snap.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('تسجيل خروج'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final boot = snap.data!;
        if (boot.partnerUid == null) {
          return PairScreen(user: widget.user, onPaired: _reload);
        }
        final name = (boot.partnerEmail ?? 'الطرف التاني').split('@').first;
        return ChatScreen(
          key: ValueKey(boot.partnerUid),
          myUid: boot.myUid,
          partnerUid: boot.partnerUid!,
          partnerName: name,
          keyStatus: boot.keyStatus,
        );
      },
    );
  }
}
