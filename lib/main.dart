import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async'; // Delay (Intezaar) ke liye zaroori

// 1. MAIN FUNCTION: App ko shuru karne aur Firebase initialize karne ke liye
void main() async {
  // Yeh Widget binding zaroori hai.
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase ko shuru karna zaroori hai.
  try {
    await Firebase.initializeApp();
    print("Firebase successfully initialized!"); // Agar shuru ho jaye
  } catch (e) {
    print("Firebase initialization error: $e"); // Agar koi error aaye
    // Agar Firebase initialize na ho to bhi app chalegi, bas database features nahi chalenge
  }

  runApp(const MyApp());
}

// 2. MYAPP WIDGET: Poori App ka base structure
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Yeh ek common color scheme define karte hain
  static const Color primaryColor = Color(0xFF00796B); // Dark Teal
  static const Color lightBgColor = Color(0xFFE4F0E9); // Light Mint Green
  static const Color secondaryColor = Color(0xFF4DB6AC); // Lighter Teal

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hospital Management App',
      debugShowCheckedModeBanner: false, // Debug banner hata diya gaya hai

      // App ki basic appearance (rang aur font) set kar rahe hain
      theme: ThemeData(
        fontFamily: 'Inter', // Custom font istemal kar sakte hain
        primaryColor: primaryColor,
        scaffoldBackgroundColor: lightBgColor, // Background ka halka rang
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryColor,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          elevation: 0, // Shadow nahi dikhegi
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            minimumSize: const Size(double.infinity, 50), // Poora width lega
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none, // Border nahi dikhega
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        ),
      ),

      // App ke routes (Screens) define kar rahe hain
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/roleSelection': (context) => const RoleSelectionScreen(),
        '/login': (context) => const LoginScreen(),
        // Humne abhi sirf yeh screens banai hain
        // Aapko '/home', '/register' aur doosri screens khud banani hongi
      },
    );
  }
}


// 3. SPLASH SCREEN: App ki shuruati screen (3 second ka delay)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 3 seconds (3000 milliseconds) ka delay lagaya gaya hai.
    // Delay khatam hone par '/roleSelection' screen par redirect hoga
    Timer(const Duration(milliseconds: 3000), () {
      Navigator.pushReplacementNamed(context, '/roleSelection');
    }); // Timer
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyApp.primaryColor, // Screen ka rang Dark Teal rakha gaya hai
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // App ka logo (Yeh sirf ek placeholder hai)
            const Icon(
              Icons.health_and_safety,
              size: 120,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const Text(
              'HEALCARE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'CONNECT EVERY CORNER OF CARE',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 80),
            // Loading indicator (gola ghoomta hua)
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(MyApp.lightBgColor.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

// 4. ROLE SELECTION SCREEN: User role chunege
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Role')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'What is your role?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: MyApp.primaryColor),
              ),
              const SizedBox(height: 30),
              // Har role ke liye button
              _buildRoleButton(context, 'PATIENT', Icons.person_outline),
              _buildRoleButton(context, 'DOCTOR', Icons.medical_services_outlined),
              _buildRoleButton(context, 'ADMIN', Icons.security),
              _buildRoleButton(context, 'LAB STAFF', Icons.science_outlined),
            ],
          ),
        ),
      ),
    );
  }

  // Role button banane ka function
  Widget _buildRoleButton(BuildContext context, String role, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: ElevatedButton(
        onPressed: () {
          // Jab button dabaya jaye, toh woh login screen par jaye
          Navigator.pushNamed(context, '/login', arguments: role);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: MyApp.primaryColor,
          padding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: Colors.white),
            const SizedBox(width: 15),
            Text(
              role,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}


// 5. LOGIN SCREEN: User login karega
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Current role ko nikalte hain (jo RoleSelectionScreen se aaya hai)
    final String? role = ModalRoute.of(context)?.settings.arguments as String?;

    return Scaffold(
      appBar: AppBar(title: Text('${role ?? 'User'} Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Logo aur Title
              const Icon(Icons.person_pin, size: 80, color: MyApp.primaryColor),
              const SizedBox(height: 20),
              const Text(
                'Apne Account Mein Login Karein',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: MyApp.primaryColor),
              ),
              const SizedBox(height: 40),

              // Email/Username Field
              const TextField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Email / Username',
                  prefixIcon: Icon(Icons.email_outlined, color: MyApp.secondaryColor),
                ),
              ),
              const SizedBox(height: 20),

              // Password Field
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline, color: MyApp.secondaryColor),
                  suffixIcon: Icon(Icons.visibility_off, color: MyApp.secondaryColor),
                ),
              ),
              const SizedBox(height: 10),

              // Forgot Password Link
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // Yahan Forgot Password screen par jane ka code aayega
                  },
                  child: const Text(
                    'Password Bhool Gaye?',
                    style: TextStyle(color: MyApp.primaryColor, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Login Button
              ElevatedButton(
                onPressed: () {
                  // Yahan login logic aayega
                  // Filhaal hum bas ek message dikha dete hain
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Login button dabaya gaya!')),
                  );
                },
                child: const Text('Login Karein'),
              ),
              const SizedBox(height: 20),

              // Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Naya Account Banana Hai? ", style: TextStyle(color: Colors.black54)),
                  TextButton(
                    onPressed: () {
                      // Yahan Sign Up screen par jane ka code aayega
                    },
                    child: const Text(
                      'Sign Up Karein',
                      style: TextStyle(color: MyApp.primaryColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
