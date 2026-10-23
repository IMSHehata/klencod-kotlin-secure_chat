import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'اكتب الإيميل وكلمة السر');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_register) {
        await auth.createUserWithEmailAndPassword(email: email, password: _pass.text);
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _message(e.code));
    } catch (e) {
      if (mounted) setState(() => _error = 'حصل خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(String code) {
    switch (code) {
      case 'invalid-email':
        return 'الإيميل مش مكتوب صح';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'الإيميل أو كلمة السر غلط';
      case 'email-already-in-use':
        return 'الإيميل ده مسجّل قبل كده';
      case 'weak-password':
        return 'كلمة السر ضعيفة (6 حروف على الأقل)';
      case 'network-request-failed':
        return 'مفيش نت';
      case 'operation-not-allowed':
        return 'التسجيل مقفول أو مش مفعّل في Firebase';
      case 'too-many-requests':
        return 'محاولات كتير، جرّب بعد شوية';
      default:
        return 'خطأ: $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_rounded, size: 72, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    'شات خاص',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'رسايل مشفّرة من طرف لطرف بينك وبين شخص واحد بس',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'الإيميل',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    textDirection: TextDirection.ltr,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'كلمة السر',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_register ? 'إنشاء حساب' : 'دخول'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'عندي حساب، دخول' : 'مفيش حساب؟ إنشاء حساب'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
