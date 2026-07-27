// lib/doctor_screens/patient_profile_view_screen.dart
import 'package:flutter/material.dart';
import 'doctor_repository.dart';
import 'patient_profile.dart';

class _PPColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const error = Color(0xFFD64545);
}

class PatientProfileViewScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String patientId;

  const PatientProfileViewScreen({
    super.key,
    required this.repository,
    required this.patientId,
  });

  @override
  State<PatientProfileViewScreen> createState() =>
      _PatientProfileViewScreenState();
}

class _PatientProfileViewScreenState extends State<PatientProfileViewScreen> {
  PatientProfile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.getPatientProfile(widget.patientId);
      if (mounted) setState(() { _profile = result; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load patient profile. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PPColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_PPColors.primary, _PPColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Text(
            'Patient Profile',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _PPColors.primary));
    }
    if (_errorMessage != null || _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _PPColors.error, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Profile not found',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _PPColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                style: ElevatedButton.styleFrom(backgroundColor: _PPColors.primary),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: _PPColors.primary.withOpacity(0.15),
                child: Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: _PPColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 28),
                ),
              ),
              const SizedBox(height: 12),
              Text(profile.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                profile.patientType == 'WALK_IN' ? 'Walk-in Patient' : 'Registered Patient',
                style: const TextStyle(color: _PPColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionCard('Contact Information', [
          _infoRow(Icons.email_outlined, 'Email',
              profile.email.isNotEmpty ? profile.email : 'Not available'),
          _infoRow(Icons.phone_outlined, 'Phone', profile.phone),
          _infoRow(Icons.badge_outlined, 'CNIC', profile.cnic),
        ]),
        const SizedBox(height: 16),
        _sectionCard('Basic Info', [
          _infoRow(Icons.cake_outlined, 'Age',
              profile.age != null ? '${profile.age} years' : 'Not recorded'),
          _infoRow(Icons.wc_outlined, 'Gender', profile.gender ?? 'Not recorded'),
        ]),
        const SizedBox(height: 16),
        _sectionCard('Medical Info', [
          _infoRow(Icons.bloodtype_outlined, 'Blood Group',
              profile.bloodGroup ?? 'Not recorded'),
          _infoRow(Icons.warning_amber_outlined, 'Allergies',
              profile.allergies ?? 'None recorded'),
          _infoRow(Icons.health_and_safety_outlined, 'Chronic Conditions',
              profile.chronicConditions ?? 'None recorded'),
        ]),
      ],
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PPColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _PPColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _PPColors.textMuted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}