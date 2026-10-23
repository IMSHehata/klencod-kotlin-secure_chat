import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// الربط مع الشخص التاني: كل واحد بيبعت كوده للتاني ويكتب كود التاني هنا.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.user, required this.onPaired});
  final User user;
  final VoidCallback onPaired;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _ctl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final code = _ctl.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{20,40}$').hasMatch(code)) {
      setState(() => _error = 'الكود مش مظبوط');
      return;
    }
    if (code == widget.user.uid) {
      setState(() => _error = 'ده كودك انت! اكتب كود الشخص التاني');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final other = await db.collection('users').doc(code).get();
      if (!other.exists) {
        setState(() => _error = 'الكود غلط، أو الشخص التاني لسه ما سجّلش دخول على التطبيق');
        return;
      }
      await db.collection('users').doc(widget.user.uid).update({'partner': code});
      widget.onPaired();
    } catch (e) {
      if (mounted) setState(() => _error = 'حصل خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myCode = widget.user.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ربط مع شخص'),
        actions: [
          IconButton(
            tooltip: 'تسجيل خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('1) ابعت كودك للشخص التاني', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    myCode,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: myCode));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('اتنسخ الكود')));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('2) اكتب كود الشخص التاني', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _ctl,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'الصق الكود هنا',
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) _ctl.text = d!.text!.trim();
                },
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _connect,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ابدأ الشات'),
          ),
          const SizedBox(height: 24),
          Text(
            'لازم الاتنين يعملوا الخطوتين دول مرة واحدة بس. بعد كده الشات بيفتح على طول.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
