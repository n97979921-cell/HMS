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

  static const Color _primary = Color(0xFF0D6B6B);

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
      backgroundColor: const Color(0xFFBDD8D8),
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 0,
        title: const Text('Staff Sign Up',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isValidating
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _errorMessage != null
              ? _buildErrorView()
              : _buildSignupForm(),
    );
  }

  // Invalid / expired / no-code
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off_rounded,
                size: 64, color: Color(0xFFD9534F)),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, color: Color(0xFF1A2F3A), height: 1.4),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              width: 200,
              child: ElevatedButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('Go to Login',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Welcome! Complete your account',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F5A)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Set a password to finish creating your staff account.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),

            // Invite details (read-only)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Name', _inviteData!['name'] ?? '—'),
                  const SizedBox(height: 8),
                  _detailRow('Email', _inviteData!['email'] ?? '—'),
                  const SizedBox(height: 8),
                  _detailRow('Role',
                      (_inviteData!['role'] ?? '—').toString().toUpperCase()),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Set your password',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F5A)),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            _passwordField(
              controller: _confirmController,
              hint: 'Confirm Password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm password';
                if (v != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSigningUp ? null : _completeSignup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
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
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
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
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2F3A))),
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
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
        prefixIcon:
            const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
      ),
    );
  }
}
