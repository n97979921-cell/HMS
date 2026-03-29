import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print(" Firebase successfully initialized!");
  } catch (e) {
    print(" Firebase initialization error: $e");
  }

  runApp(const FamilyWellCareApp());
}

class FamilyWellCareApp extends StatelessWidget {
  const FamilyWellCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Well Care Hospital',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A6B6B),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
