import 'package:flutter/material.dart';
import 'package:hospital_management_app/services/auth_service.dart';
import 'login_screen.dart';

/// UI/UX REDESIGN ONLY — koi signup/validation logic change nahi hua.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cnicController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _selectedGender;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  final authService = AuthService();

  static const Color _navy = Color(0xFF1A2F5A);
  static const Color _teal = Color(0xFF0D6B6B);
  static const Color _bg = Color(0xFFF1F6F5);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _cnicController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _register() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ Get all values
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final cnic = _cnicController.text.trim();
    final phone = _phoneController.text.trim();
    final age = int.parse(_ageController.text.trim());
    final gender = _selectedGender!;

    setState(() => _isLoading = true);

    try {
      // ✅ Call Firebase
      bool success = await authService.patientSignup(
        email: email,
        password: password,
        name: name,
        cnic: cnic,
        phone: phone,
        age: age,
        gender: gender,
      );

      setState(() => _isLoading = false);
      if (!mounted) return;

      if (success) {
        // ✅ SUCCESS
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Account created! Check your email to verify.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // ✅ Redirect to login after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
        });
      } else {
        // ❌ FAILED
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Registration failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);

    final result = await authService.signInWithGoogle();

    setState(() => _isGoogleLoading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      if (result['isNewUser'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Signed in with Google! Please complete your profile.'),
            backgroundColor: Color(0xFF1A6B6B),
          ),
        );
        // NOTE: agar aapke paas "complete profile" screen banai hui hai
        // to yahan us par navigate kar dein, e.g.:
        // Navigator.push(context, MaterialPageRoute(
        //   builder: (_) => CompleteGoogleProfileScreen(googleUser: result['googleUser']),
        // ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome back! Logging you in...'),
            backgroundColor: Color(0xFF1A6B6B),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Google sign-in failed'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 6),

                // ── Logo + Header ─────────────────────────────────────────
                Image.asset(
                  'assets/Logo.png',
                  width: 88,
                  height: 92,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Family Well Care Hospital',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _navy,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 22),

                // ── Card ─────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create account',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Fill in your details to get started',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      const _FieldLabel('Full Name'),
                      const SizedBox(height: 6),
                      _field(_nameController, 'Enter your full name',
                          Icons.person_outline, validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Full name required';
                        }
                        if (v.length < 3) return 'Name too short';
                        return null;
                      }),
                      const SizedBox(height: 14),

                      const _FieldLabel('Email Address'),
                      const SizedBox(height: 6),
                      _field(_emailController, 'name@example.com',
                          Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                        if (v == null || v.isEmpty) return 'Email required';
                        if (!v.contains('@')) return 'Enter valid email';
                        return null;
                      }),
                      const SizedBox(height: 14),

                      const _FieldLabel('Password'),
                      const SizedBox(height: 6),
                      _field(
                          _passwordController, 'Create a password', Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ), validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Password required';
                        }
                        if (v.length < 6) return 'Min 6 characters';
                        return null;
                      }),
                      const SizedBox(height: 14),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Age'),
                                const SizedBox(height: 6),
                                _field(_ageController, 'Age',
                                    Icons.cake_outlined,
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Age required';
                                  }
                                  final age = int.tryParse(v);
                                  if (age == null || age < 1 || age > 120) {
                                    return 'Enter valid age';
                                  }
                                  return null;
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Phone Number'),
                                const SizedBox(height: 6),
                                _field(_phoneController, '03XX-XXXXXXX',
                                    Icons.phone_outlined,
                                    keyboardType: TextInputType.phone,
                                    validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Phone required';
                                  }
                                  if (v.length < 10) {
                                    return 'Enter valid phone number';
                                  }
                                  return null;
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      const _FieldLabel('CNIC'),
                      const SizedBox(height: 6),
                      _field(_cnicController, 'XXXXX-XXXXXXX-X',
                          Icons.card_membership,
                          keyboardType: TextInputType.number, validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'CNIC required';
                        }
                        if (v.length < 13) {
                          return 'CNIC must be at least 13 characters';
                        }
                        if (!RegExp(r'^\d{5}-\d{7}-\d$').hasMatch(v)) {
                          return 'Invalid CNIC format (12345-6789012-3)';
                        }
                        return null;
                      }),
                      const SizedBox(height: 14),

                      const _FieldLabel('Gender'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedGender,
                        validator: (v) =>
                            v == null ? 'Please select gender' : null,
                        decoration: InputDecoration(
                          hintText: 'Select gender',
                          hintStyle: const TextStyle(
                              color: Colors.grey, fontSize: 14),
                          prefixIcon: const Icon(Icons.person_pin_outlined,
                              color: _teal, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF4F7F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: _teal, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: Colors.redAccent),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: Colors.redAccent),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 16),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'Female', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                      const SizedBox(height: 22),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _teal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 3,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Register',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const _OrDivider(),
                      const SizedBox(height: 20),

                      _GoogleButton(
                        isLoading: _isGoogleLoading,
                        onPressed:
                            _isGoogleLoading ? null : _handleGoogleSignIn,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── Already have account ───────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text(
                        'Log in',
                        style: TextStyle(
                          color: _teal,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: Icon(icon, color: _teal, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF4F7F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1A2F5A),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider(color: Colors.black26)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: Colors.black26)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GoogleButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE0E6E5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Color(0xFF0D6B6B),
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Image(
                    image: AssetImage('assets/google_logo.png'),
                    width: 20,
                    height: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      color: Color(0xFF1A2F5A),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}