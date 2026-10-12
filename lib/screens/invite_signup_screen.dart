import 'package:flutter/material.dart';
import 'package:hospital_management_app/services/auth_service.dart';
import 'package:hospital_management_app/services/invite_service.dart';
import '../login_screen.dart';

/// INVITE SIGNUP (Staff only — receptionist/doctor/labstaff/admin)
///
/// FLOW (Option 1 — sirf deep link):
///   Admin invite form bharta hai → user ko email par link jaata hai →
///   user link kholta hai → main.dart URL se code nikal ke yeh screen
///   inviteCode ke saath kholti hai → code auto-validate → user sirf
///   password set karta hai → account ban jaata hai.
///
/// Koi manual code-typing NAHI. Agar bina code ke yeh screen khul jaye
/// (galti se), to "invalid link" message dikhta hai.
///
/// Account banana AuthService ke role-specific methods se hota hai
/// (transaction-safe: account + invite mark-used ek saath).
class InviteSignupScreen extends StatefulWidget {
  /// Deep-link (invite URL) se aaya invite code.
  final String? inviteCode;

  const InviteSignupScreen({super.key, this.inviteCode});

  @override
  State<InviteSignupScreen> createState() => _InviteSignupScreenState();
}

class _InviteSignupScreenState extends State<InviteSignupScreen> {
  final _authService = AuthService();
  final _inviteService = InviteService();

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isValidating = true; // shuru mein hi validate hota hai
  bool _isSigningUp = false;

  Map<String, dynamic>? _inviteData; // validated invite ka data
  String? _errorMessage; // invalid/expired link ka message

  // Theme colors — login screen (Option 2) se match
  static const Color _primary = Color(0xFF0B2E33);
  static const Color _bg = Color(0xFFF4F7F6);

  @override
  void initState() {
    super.initState();
    _validateInviteFromLink();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Deep link se aaye code ko validate karo
  Future<void> _validateInviteFromLink() async {
    final code = widget.inviteCode?.trim();

    // Bina code ke aaye (galat raasta) → error message
    if (code == null || code.isEmpty) {
      setState(() {
        _isValidating = false;
        _errorMessage =
            'This page can only be opened from an invite link sent to your email.';
      });
      return;
    }

    try {
      final data = await _inviteService.validateInvite(code);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _isValidating = false;
          _errorMessage =
              'This invite link is invalid, already used, or has expired.';
        });
      } else {
        setState(() {
          _isValidating = false;
          _inviteData = data;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidating = false;
        _errorMessage = 'Could not validate invite. Please try again.';
      });
    }
  }

  // Password set karke account banao
  Future<void> _completeSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_inviteData == null) return;

    setState(() => _isSigningUp = true);

    final inviteCode = widget.inviteCode!.trim();
    final password = _passwordController.text.trim();
    final role = (_inviteData!['role'] ?? '').toString().toLowerCase();

    try {
      bool success;
      switch (role) {
        case 'doctor':
          success = await _authService.doctorSignupWithInvite(
              inviteCode: inviteCode, password: password);
          break;
        case 'labstaff':
          success = await _authService.labStaffSignupWithInvite(
              inviteCode: inviteCode, password: password);
          break;
        case 'receptionist':
          success = await _authService.receptionistSignupWithInvite(
              inviteCode: inviteCode, password: password);
          break;
        case 'admin':
          success = await _authService.adminSignupWithInvite(
              inviteCode: inviteCode, password: password);
          break;
        default:
          _showError('Unknown role in invite: $role');
          setState(() => _isSigningUp = false);
          return;
      }

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account created! Please log in.'),
          backgroundColor: _primary,
        ));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      } else {
        _showError('Signup failed. The invite may already be used or expired.');
      }
    } catch (e) {
      _showError('Error creating account: $e');
    } finally {
      if (mounted) setState(() => _isSigningUp = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _isValidating
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : _errorMessage != null
                ? _buildErrorView()
                : _buildSignupForm(),
      ),
    );
  }

  // Logo + hospital name (login screen jaisa)
  Widget _buildBrand() {
    return Column(
      children: [
        Image.asset(
          'assets/Logo.png',
          width: 96,
          height: 100,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 12),
        const Text(
          'Family Well Care Hospital',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _primary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Staff Sign Up',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      );

  // Invalid / expired / no-code
  Widget _buildErrorView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            _buildBrand(),
            const SizedBox(height: 26),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
              decoration: _cardDecoration,
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFBEDE8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.link_off_rounded,
                        size: 36, color: Color(0xFFB23A1E)),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, color: _primary, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text('Go to Login',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Valid invite — details + password (koi code box nahi)
  Widget _buildSignupForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            _buildBrand(),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
              decoration: _cardDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Welcome! Complete your account',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _primary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Set a password to finish creating your staff account.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),

                  // Invite details (read-only)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow('Name', _inviteData!['name'] ?? '—'),
                        const SizedBox(height: 8),
                        _detailRow('Email', _inviteData!['email'] ?? '—'),
                        const SizedBox(height: 8),
                        _detailRow(
                            'Role',
                            (_inviteData!['role'] ?? '—')
                                .toString()
                                .toUpperCase()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Password',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _primary),
                  ),
                  const SizedBox(height: 6),
                  _passwordField(
                    controller: _passwordController,
                    hint: 'Password',
                    obscure: _obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'Minimum 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Confirm password',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _primary),
                  ),
                  const SizedBox(height: 6),
                  _passwordField(
                    controller: _confirmController,
                    hint: 'Confirm Password',
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm password';
                      }
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSigningUp ? null : _completeSignup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _isSigningUp
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Text('Create Account',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _primary)),
        ),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: const Icon(Icons.lock_outline, color: _primary, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: _bg,
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
          borderSide: const BorderSide(color: _primary, width: 1.5),
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
