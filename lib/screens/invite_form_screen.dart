import 'package:flutter/material.dart';
import '../Services/invite_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Color get _roleColor {
    switch (widget.role) {
      case 'doctor':
        return const Color(0xFF1A73E8);
      case 'admin':
        return const Color(0xFF0F9D58);
      case 'receptionist':
        return const Color(0xFFF4B400);
      case 'labstaff':
        return const Color(0xFFDB4437);
      default:
        return const Color(0xFF1A73E8);
    }
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
      final inviteCode = await _inviteService.generateInvite(
        doctorName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        role: widget.role,
        specialization: _isDoctor ? _specializationController.text.trim() : '',
        phone: _phoneController.text.trim(),
        departmentId: _isDoctor
            ? (_selectedDepartmentId ?? '')
            : '', // ← YEH LINE ADD KAR
      );

      if (inviteCode != null) {
        // Send email with invite
        await _inviteService.sendInviteEmail(
          email: _emailController.text.trim(),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFF0F9D58), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Invite Sent!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite sent to ${_emailController.text.trim()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Text(
                    'Invite Code',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    inviteCode,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _roleColor,
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
                backgroundColor: _roleColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Done',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
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
        backgroundColor: const Color(0xFFDB4437),
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Invite $_roleLabel',
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _roleColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _roleColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: _roleColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'An invite link will be sent to the email address. User will set their own password.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _roleColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Common Fields
              _buildLabel('Full Name'),
              _buildField(
                controller: _nameController,
                hint: 'Enter full name',
                icon: Icons.person_outline_rounded,
                validator: (v) => v!.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              _buildLabel('Email Address'),
              _buildField(
                controller: _emailController,
                hint: 'Enter email address',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v!.isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Enter valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _buildLabel('Phone Number'),
              _buildField(
                controller: _phoneController,
                hint: 'Enter phone number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? 'Phone is required' : null,
              ),

              // Doctor-specific fields
              if (_isDoctor) ...[
                const SizedBox(height: 16),
                _buildLabel('Specialization'),
                _buildField(
                  controller: _specializationController,
                  hint: 'e.g. Cardiologist, Dentist',
                  icon: Icons.medical_services_outlined,
                  validator: (v) =>
                      v!.isEmpty ? 'Specialization is required' : null,
                ),
                const SizedBox(height: 16),
                _buildLabel('Department'),
                DropdownButtonFormField<String>(
                  value: _selectedDepartmentId,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.business_outlined,
                        color: _roleColor, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
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
                      borderSide: BorderSide(color: _roleColor, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFFDB4437), width: 1.5),
                    ),
                  ),
                  hint: const Text('Select Department',
                      style: TextStyle(color: Color(0xFFB0B8C1), fontSize: 14)),
                  items: _departments.map((dept) {
                    return DropdownMenuItem<String>(
                      value: dept['id'],
                      child: Text(dept['name']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedDepartmentId = value;
                      _selectedDepartmentName = _departments
                          .firstWhere((d) => d['id'] == value)['name'];
                    });
                  },
                  validator: (v) => v == null ? 'Department is required' : null,
                ),
                const SizedBox(height: 16),
                _buildLabel('Licence No.'),
                _buildField(
                  controller: _licenceController,
                  hint: 'Enter medical licence number',
                  icon: Icons.badge_outlined,
                  validator: (v) =>
                      v!.isEmpty ? 'Licence number is required' : null,
                ),
              ],

              const SizedBox(height: 32),

              // Send Invite Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendInvite,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _roleColor,
                    disabledBackgroundColor: _roleColor.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
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
                                color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Send Invite',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
        ),
      ),
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
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB0B8C1), fontSize: 14),
        prefixIcon: Icon(icon, color: _roleColor, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          borderSide: BorderSide(color: _roleColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDB4437), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDB4437), width: 1.5),
        ),
      ),
    );
  }
}
