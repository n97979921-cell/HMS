import 'package:flutter/material.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ Admin dashboard ke bgColor se match kiya (0xFFF4F7F6)
      backgroundColor: const Color(0xFFF4F7F6),

      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Image.asset(
                        'assets/Logo.png',
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ✅ EXACT IMAGE COLOR: Dark teal text (image jaisa)
                  const Text(
                    'FAMILY WELL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A4A4A), // Dark teal
                      letterSpacing: 3,
                    ),
                  ),
                  const Text(
                    'CARE HOSPITAL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A4A4A), // Dark teal
                      letterSpacing: 3,
                    ),
                  ),

                  const SizedBox(height: 70),

                  // ✅ EXACT IMAGE COLOR: Medium dark teal for tagline
                  const Text(
                    'CONNECT EVERY CORNER OF CARE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A5C5C), // Medium dark teal
                      letterSpacing: 2.5,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}