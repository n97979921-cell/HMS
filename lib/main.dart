import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hospital_management_app/firebase_options.dart';
import 'package:hospital_management_app/splash_screen.dart';
import 'package:hospital_management_app/screens/invite_signup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Family Well Care Hospital',
      theme: ThemeData(
        primaryColor: const Color(0xFF0D6B6B),
        useMaterial3: true,
      ),
      home: _getHome(),
    );
  }

  Widget _getHome() {
    if (kIsWeb) {
      // Browser ka URL read karo
      final url = Uri.base;
      final code = url.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        return InviteSignupScreen(inviteCode: code);
      }
    }
    return const SplashScreen();
  }
}
