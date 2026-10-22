// lib/screens/invite_form_screen.dart
import 'package:flutter/material.dart';
import '../Services/invite_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

class InviteFormScreen extends StatefulWidget {
  final String role;

  const InviteFormScreen({super.key, required this.role});

  @override
  State<InviteFormScreen> createState() => _InviteFormScreenState();
}

class _InviteFormScreenState extends State<InviteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final InviteService _inviteService = InviteService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _specializationController = TextEditingController();
  final _departmentController = TextEditingController();
  final _licenceController = TextEditingController();

  bool _isLoading = false;
  bool get _isDoctor => widget.role == 'doctor';

  List<Map<String, dynamic>> _departments = [];
  String? _selectedDepartmentId;
  String? _selectedDepartmentName;

  @override
  void initState() {
    super.initState();
    if (_isDoctor) _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    final snap = await FirebaseFirestore.instance
        .collection('departments')
        .orderBy('createdAt')
        .get();
    setState(() {
      _departments =
          snap.docs.map((d) => {'id': d.id, 'name': d.data()['name']}).toList();
    });
  }

  String get _roleLabel {
    switch (widget.role) {
      case 'doctor':
        return 'Doctor';
      case 'admin':
        return 'Admin';
      case 'receptionist':
        return 'Receptionist';
      case 'labstaff':
        return 'Lab Staff';
      default:
        return 'User';
    }
  }

  Future<void> _sendInvite() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();

      // NEW: pehle check karo ke is email pe pehle se invite pending ya used to nahi
      final status = await _inviteService.checkInviteStatus(email);

      if (status == "pending") {
        _showError(
            'An invite is already active for this email. Please wait until it is used or expires.');
        setState(() => _isLoading = false);
        return;
      }

      if (status == "used") {
        _showError('A user with this email is already registered.');
        setState(() => _isLoading = false);
        return;
      }

      // status == "none" -> yahan se aage normal flow chalega
      final inviteCode = await _inviteService.generateInvite(
        doctorName: _nameController.text.trim(),
        email: email,
        role: widget.role,
        specialization: _isDoctor ? _specializationController.text.trim() : '',
        phone: _phoneController.text.trim(),
        departmentId: _isDoctor ? (_selectedDepartmentId ?? '') : '',
        license: _isDoctor ? _licenceController.text.trim() : '',
      );

      if (inviteCode != null) {
        await _inviteService.sendInviteEmail(
          email: email,
          inviteCode: inviteCode,
          name: _nameController.text.trim(),
        );

        if (mounted) {
          _showSuccessDialog(inviteCode);
        }
      } else {
        if (mounted) {
          _showError('Failed to generate invite. Please try again.');
        }
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(String inviteCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.tealSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.teal, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Invite Sent!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite sent to ${_emailController.text.trim()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Invite Code',
                    style: TextStyle(fontSize: 11, color: AppColors.faint),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    inviteCode,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // go back to list
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.header,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Done',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _specializationController.dispose();
    _departmentController.dispose();
    _licenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          AppHeader(
            title: 'Invite $_roleLabel',
            subtitle: 'Send an invite link by email',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppInfoNote(
                      text:
                          'An invite link will be sent to the email address. User will set their own password.',
                    ),
                    const SizedBox(height: 16),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Common Fields
                          _buildLabel('Full Name'),
                          _buildField(
                            controller: _nameController,
                            hint: 'Enter full name',
                            icon: Icons.person_outline_rounded,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Name is required';
                              }
                              // Kam az kam 3 characters (spaces gin kar nahi)
                              if (v.trim().length < 3) {
                                return 'Name must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          _buildLabel('Email Address'),
                          _buildField(
                            controller: _emailController,
                            hint: 'Enter email address',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required';
                              }
                              // Login screen jaisa hi email format check
                              final emailRegex =
                                  RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                              if (!emailRegex.hasMatch(v.trim())) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          _buildLabel('Phone Number'),
                          _buildField(
                            controller: _phoneController,
                            hint: '03XXXXXXXXX',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Phone is required';
                              }
                              if (!RegExp(r'^03\d{9}$').hasMatch(v.trim())) {
                                return 'Enter valid Pakistani number (03XXXXXXXXX)';
                              }
                              return null;
                            },
                          ),
                          // Doctor-specific fields
                          if (_isDoctor) ...[
                            const SizedBox(height: 14),
                            _buildLabel('Specialization'),
                            _buildField(
                              controller: _specializationController,
                              hint: 'e.g. Cardiologist, Dentist',
                              icon: Icons.medical_services_outlined,
                              validator: (v) => v!.isEmpty
                                  ? 'Specialization is required'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            _buildLabel('Department'),
                            DropdownButtonFormField<String>(
                              value: _selectedDepartmentId,
                              dropdownColor: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              decoration: _fieldDecoration(
                                  icon: Icons.business_outlined),
                              hint: const Text('Select Department',
                                  style: TextStyle(
                                      color: AppColors.faint, fontSize: 14)),
                              items: _departments.map((dept) {
                                return DropdownMenuItem<String>(
                                  value: dept['id'],
                                  child: Text(dept['name']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDepartmentId = value;
                                  _selectedDepartmentName =
                                      _departments.firstWhere(
                                          (d) => d['id'] == value)['name'];
                                });
                              },
                              validator: (v) =>
                                  v == null ? 'Department is required' : null,
                            ),
                            const SizedBox(height: 14),
                            _buildLabel('Licence No.'),
                            _buildField(
                              controller: _licenceController,
                              hint: 'Enter medical licence number',
                              icon: Icons.badge_outlined,
                              validator: (v) => v!.isEmpty
                                  ? 'Licence number is required'
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Send Invite Button
                    AppPrimaryButton(
                      label: 'Send Invite',
                      onPressed: _isLoading ? null : _sendInvite,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded,
                                    color: Colors.white, size: 19),
                                SizedBox(width: 10),
                                Text(
                                  'Send Invite',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) => AppFieldLabel(text);

  InputDecoration _fieldDecoration({String? hint, required IconData icon}) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return appInputDecoration(hint: hint, filled: true).copyWith(
      prefixIcon: Icon(icon, color: AppColors.teal, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: b(Colors.transparent),
      enabledBorder: b(Colors.transparent),
      focusedBorder: b(AppColors.teal, 1.5),
      errorBorder: b(AppColors.danger, 1.5),
      focusedErrorBorder: b(AppColors.danger, 1.5),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: AppColors.text),
      decoration: _fieldDecoration(hint: hint, icon: icon),
    );
  }
}