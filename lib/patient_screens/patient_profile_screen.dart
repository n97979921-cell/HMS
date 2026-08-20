import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../login_screen.dart';

/// PATIENT PROFILE
/// - Personal (editable): name, phone, age
/// - Medical (editable, nullable): bloodGroup, allergies, chronicConditions
///   → khali chhoda ja sakta hai; null hone par "Not provided" dikhta hai
/// - Account (read-only): email (Firebase Auth login), cnic (identity)
/// - Change Password + Logout
///
/// Data do collections mein hai:
///   users            → name, phone, email, cnic
///   patient_profiles → age, gender, bloodGroup, allergies, chronicConditions
class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);
  static const Color _bg = Color(0xFFF4F7F6);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _chronicController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String _email = '';
  String _cnic = '';
  String _gender = '';
  String _createdAtLabel = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _bloodGroupController.dispose();
    _allergiesController.dispose();
    _chronicController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // users doc — name, phone, email, cnic
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data();
      if (userData != null) {
        _nameController.text = userData['name'] ?? '';
        _phoneController.text = userData['phone'] ?? '';
        _cnic = userData['cnic'] ?? '';
        _email =
            userData['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '';

        final createdAt = userData['createdAt'];
        if (createdAt is Timestamp) {
          final date = createdAt.toDate();
          _createdAtLabel = '${_monthName(date.month)} ${date.year}';
        }
      }

      // patient_profiles doc — age, gender, medical fields
      final profileDoc = await FirebaseFirestore.instance
          .collection('patient_profiles')
          .doc(uid)
          .get();
      final profileData = profileDoc.data();
      if (profileData != null) {
        _ageController.text = (profileData['age'] ?? '').toString();
        _gender = profileData['gender'] ?? '';
        _bloodGroupController.text = profileData['bloodGroup'] ?? '';
        _allergiesController.text = profileData['allergies'] ?? '';
        _chronicController.text = profileData['chronicConditions'] ?? '';
      }
    } catch (e) {
      _showSnack('Error loading profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // users — name, phone
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // patient_profiles — age + medical (nullable: khali = null)
      String? nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

      await FirebaseFirestore.instance
          .collection('patient_profiles')
          .doc(uid)
          .set({
        'patientId': uid,
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'bloodGroup': nullIfEmpty(_bloodGroupController.text),
        'allergies': nullIfEmpty(_allergiesController.text),
        'chronicConditions': nullIfEmpty(_chronicController.text),
      }, SetOptions(merge: true));

      _showSnack('Profile updated successfully');
    } catch (e) {
      _showSnack('Error saving profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    // Sab screens hata ke login/root pe le jao
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFDB4437) : _primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showChangePasswordSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  String? _getInitial() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return null;
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primaryDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAvatarHeader(),
                    const SizedBox(height: 24),

                    // ── Personal ──
                    const _SectionLabel('Personal Information'),
                    const SizedBox(height: 12),
                    _cardWrap([
                      _FieldLabel('Full Name'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        decoration:
                            _inputDecoration(Icons.person_outline_rounded),
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Name is required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Phone Number'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration(Icons.phone_outlined),
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Phone is required' : null,
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Age'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(Icons.cake_outlined),
                        validator: (v) {
                          if (v!.trim().isEmpty) return 'Age is required';
                          final age = int.tryParse(v.trim());
                          if (age == null || age <= 0 || age > 120) {
                            return 'Enter a valid age';
                          }
                          return null;
                        },
                      ),
                    ]),
                    const SizedBox(height: 24),

                    // ── Medical ──
                    const _SectionLabel('Medical Information'),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Optional — helps doctors treat you better. Leave blank if not applicable.',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _cardWrap([
                      _FieldLabel('Blood Group'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _bloodGroupController.text.isEmpty
                            ? null
                            : _bloodGroupController.text,
                        decoration: _inputDecoration(Icons.bloodtype_outlined),
                        hint: const Text('Select blood group',
                            style: TextStyle(
                                color: Color(0xFFB0B7C3), fontSize: 13)),
                        items: const [
                          'A+',
                          'A-',
                          'B+',
                          'B-',
                          'AB+',
                          'AB-',
                          'O+',
                          'O-'
                        ]
                            .map((bg) =>
                                DropdownMenuItem(value: bg, child: Text(bg)))
                            .toList(),
                        onChanged: (value) {
                          setState(
                              () => _bloodGroupController.text = value ?? '');
                        },
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Allergies'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _allergiesController,
                        maxLines: 2,
                        decoration: _inputDecoration(
                            Icons.warning_amber_outlined,
                            hint: 'e.g. Penicillin, peanuts'),
                      ),
                      const SizedBox(height: 16),
                      _FieldLabel('Chronic Conditions'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _chronicController,
                        maxLines: 2,
                        decoration: _inputDecoration(
                            Icons.medical_information_outlined,
                            hint: 'e.g. Diabetes, hypertension'),
                      ),
                    ]),
                    const SizedBox(height: 24),

                    // ── Account (read-only) ──
                    const _SectionLabel('Account Information'),
                    const SizedBox(height: 12),
                    _readOnlyRow(Icons.email_outlined, 'Email Address', _email),
                    const SizedBox(height: 12),
                    _readOnlyRow(Icons.badge_outlined, 'CNIC',
                        _cnic.isEmpty ? 'Not provided' : _cnic),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Email and CNIC cannot be changed.',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Save
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          disabledBackgroundColor:
                              _primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Save Changes',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Change password
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _showChangePasswordSheet,
                        icon: const Icon(Icons.lock_reset_rounded,
                            color: _primary, size: 20),
                        label: const Text('Change Password',
                            style: TextStyle(
                                color: _primary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Logout
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded,
                            color: Color(0xFFD9534F), size: 20),
                        label: const Text('Log Out',
                            style: TextStyle(
                                color: Color(0xFFD9534F),
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD9534F)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAvatarHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              _getInitial() ?? 'P',
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _nameController.text.isEmpty ? 'Patient' : _nameController.text,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _gender.isEmpty ? 'Patient' : 'Patient · $_gender',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ),
          if (_createdAtLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Member since $_createdAtLabel',
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardWrap(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded,
              size: 16, color: Color(0xFFD1D5DB)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB0B7C3), fontSize: 13),
      prefixIcon: Icon(icon, color: _primary, size: 20),
      filled: true,
      fillColor: _bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDB4437), width: 1.5),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280),
        letterSpacing: 0.5,
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
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF374151),
      ),
    );
  }
}

// ── Change Password Bottom Sheet ──────────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  static const Color _primary = Color(0xFF1F8A70);

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;

      // Re-authenticate — Firebase recent sign-in maangta hai
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newPasswordController.text);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Password changed successfully'),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Error changing password';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Current password is incorrect';
      } else if (e.code == 'weak-password') {
        msg = 'New password is too weak';
      }
      _showError(msg);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text('Change Password',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF6B7280)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _passwordField(
                label: 'Current Password',
                controller: _currentPasswordController,
                obscure: _obscureCurrent,
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
                validator: (v) =>
                    v!.isEmpty ? 'Current password is required' : null,
              ),
              const SizedBox(height: 14),
              _passwordField(
                label: 'New Password',
                controller: _newPasswordController,
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
                validator: (v) {
                  if (v!.isEmpty) return 'New password is required';
                  if (v.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _passwordField(
                label: 'Confirm New Password',
                controller: _confirmPasswordController,
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                validator: (v) {
                  if (v!.isEmpty) return 'Please confirm your password';
                  if (v != _newPasswordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    disabledBackgroundColor: _primary.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Update Password',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                color: _primary, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF9CA3AF),
                size: 20,
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: const Color(0xFFF4F7F6),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFDB4437), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
