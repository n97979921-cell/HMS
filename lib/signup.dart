import 'package:flutter/material.dart';
import 'package:hospital_management_app/login.dart';
import 'login_screen.dart';
import 'user_store.dart';

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
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _selectedGender;
  bool _obscurePassword = true;
  bool _isLoading = false;

  void _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your gender.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (UserStore.emailExists(email)) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This email is already registered. Please login.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    UserStore.register(email, password);
    setState(() => _isLoading = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account created! Please login.'),
        backgroundColor: Color(0xFF0D6B6B),
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCFE3E3),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // ---- Logo ----
                _buildLogo(),

                const SizedBox(height: 18),

                // ---- Toggle ----
                _buildToggle(),

                const SizedBox(height: 10),

                const Text(
                  'Create a new Account',
                  style: TextStyle(
                    color: Color(0xFF1A3A5C),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                // ---- Fields ----
                _buildField(_nameController, 'Full Name', Icons.person_outline,
                    validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Full name is required';
                  }
                  if (val.trim().length < 3) return 'Name is too short';
                  return null;
                }),
                const SizedBox(height: 11),

                _buildField(_emailController, 'Email', Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress, validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!val.contains('@') || !val.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                }),
                const SizedBox(height: 11),

                _buildField(
                    _passwordController, 'Password', Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ), validator: (val) {
                  if (val == null || val.isEmpty) return 'Password is required';
                  if (val.length < 6) return 'Minimum 6 characters';
                  return null;
                }),
                const SizedBox(height: 11),

                _buildField(_ageController, 'Age', Icons.cake_outlined,
                    keyboardType: TextInputType.number, validator: (val) {
                  if (val == null || val.isEmpty) return 'Age is required';
                  final age = int.tryParse(val);
                  if (age == null || age < 1 || age > 120) {
                    return 'Enter a valid age';
                  }
                  return null;
                }),
                const SizedBox(height: 11),

                _buildField(
                    _phoneController, 'Phone Number', Icons.phone_outlined,
                    keyboardType: TextInputType.phone, validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Phone is required';
                  }
                  if (val.trim().length < 10) {
                    return 'Enter valid phone number';
                  }
                  return null;
                }),
                const SizedBox(height: 11),

                // ---- Gender Dropdown ----
                _buildGenderDropdown(),

                const SizedBox(height: 22),

                // ---- Register Button ----
                SizedBox(
                  width: 200,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D6B6B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 4,
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

                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.black87, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LoginScreen()),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Color(0xFF0D6B6B),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Image.asset(
          'assets/Logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 6),
        const Text(
          'FAMILY WELL\nCARE HOSPITAL',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF1A3A5C),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.8,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildToggle() {
    return Row(
      children: [
        // Login tab (inactive)
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0x8CFFFFFF), // fixed: was withOpacity(0.55)
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Center(
                child: Text(
                  'Login',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Sign Up tab (active)
        Expanded(
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF0D6B6B),
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x590D6B6B), // fixed: was withOpacity(0.35)
                  blurRadius: 10,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: const Center(
              child: Text(
                'Sign Up',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
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
        hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xE0FFFFFF), // fixed: was withOpacity(0.88)
        contentPadding:
            const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide:
              const BorderSide(color: Color(0xFF0D6B6B), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      decoration: InputDecoration(
        hintText: 'Gender',
        hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
        prefixIcon:
            const Icon(Icons.wc_outlined, color: Colors.grey, size: 20),
        filled: true,
        fillColor: const Color(0xE0FFFFFF), // fixed: was withOpacity(0.88)
        contentPadding:
            const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide:
              const BorderSide(color: Color(0xFF0D6B6B), width: 1.8),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      items: const [
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Female', child: Text('Female')),
        DropdownMenuItem(value: 'Other', child: Text('Other')),
      ],
      onChanged: (val) => setState(() => _selectedGender = val),
    );
  }
}