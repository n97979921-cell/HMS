// lib/doctor_screens/patient_profile_view_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'doctor_repository.dart';
import 'patient_profile.dart';

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
      final result =
          await widget.repository.getPatientProfile(widget.patientId);
      if (mounted)
        setState(() {
          _profile = result;
          _isLoading = false;
        });
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
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Patient Profile',
      subtitle: _profile?.name,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.teal));
    }
    if (_errorMessage != null || _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Profile not found',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.header, elevation: 0),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.tealSoft,
                child: Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w800,
                      fontSize: 28),
                ),
              ),
              const SizedBox(height: 10),
              Text(profile.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  profile.patientType == 'WALK_IN'
                      ? 'Walk-in Patient'
                      : 'Registered Patient',
                  style: const TextStyle(
                      color: Color(0xFF0B5E57),
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionCard('Contact Information', [
          _infoRow(Icons.email_outlined, 'Email',
              profile.email.isNotEmpty ? profile.email : 'Not available'),
          _infoRow(Icons.phone_outlined, 'Phone', profile.phone),
        ]),
        const SizedBox(height: 16),
        _sectionCard('Basic Info', [
          _infoRow(Icons.cake_outlined, 'Age',
              profile.age != null ? '${profile.age} years' : 'Not recorded'),
          _infoRow(
              Icons.wc_outlined, 'Gender', profile.gender ?? 'Not recorded'),
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
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, color: AppColors.divider));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.muted)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: AppColors.faint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.faint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
