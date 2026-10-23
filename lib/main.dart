import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_config.dart';
import 'screens/auth_screen.dart';
import 'screens/bootstrap.dart';
import 'services/temp_files.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await TempFiles.clear();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const SecureChatApp());
}

class SecureChatApp extends StatelessWidget {
  const SecureChatApp({super.key});

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF008069),
      brightness: b,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF1F2C34) : const Color(0xFF008069),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'شات خاص',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const AuthScreen();
        return Bootstrap(key: ValueKey(user.uid), user: user);
      },
    );
  }
}
