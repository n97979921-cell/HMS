// lib/doctor_screens/doctor_profile_screen.dart
import 'package:flutter/material.dart';
import 'doctor_repository.dart';
import 'doctor_profile.dart';
import '../login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class _ProfileColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const error = Color(0xFFD64545);
}

class DoctorProfileScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String doctorId;

  const DoctorProfileScreen({
    super.key,
    required this.repository,
    required this.doctorId,
  });

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  DoctorProfile? _profile;
  bool _isLoading = true;
  double _avgRating = 0;
  int _reviewCount = 0;
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
      final result = await widget.repository.getDoctorProfile(widget.doctorId);

      // Rating summary — separate lightweight query, doesn't touch
      // the DoctorProfile model/repository interface.
      final feedbackSnap = await FirebaseFirestore.instance
          .collection('feedback')
          .where('doctorId', isEqualTo: widget.doctorId)
          .get();

      double avg = 0;
      if (feedbackSnap.docs.isNotEmpty) {
        final ratings = feedbackSnap.docs
            .map((d) => ((d.data()['rating'] ?? 0) as num).toDouble())
            .toList();
        avg = ratings.reduce((a, b) => a + b) / ratings.length;
      }

      if (mounted) {
        setState(() {
          _profile = result;
          _avgRating = avg;
          _reviewCount = feedbackSnap.docs.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load profile. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openEditDialog() async {
    final profile = _profile;
    if (profile == null) return;

    final nameController = TextEditingController(text: profile.name);
    final phoneController = TextEditingController(text: profile.phone);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Profile'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final phone = phoneController.text.trim();
                          if (name.isEmpty || phone.isEmpty) return;

                          setDialogState(() => isSaving = true);
                          try {
                            await widget.repository.updateDoctorProfile(
                              doctorId: widget.doctorId,
                              name: name,
                              phone: phone,
                            );
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext);
                            await _loadProfile();
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                    content: Text('Failed to update profile'),
                                    backgroundColor: _ProfileColors.error),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _ProfileColors.primary),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Save',
                          style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout',
                style: TextStyle(color: _ProfileColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileColors.background,
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
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_ProfileColors.primary, _ProfileColors.primaryDark],
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
            'Profile',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _ProfileColors.primary));
    }
    if (_errorMessage != null || _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: _ProfileColors.error, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Profile not found',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _ProfileColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _ProfileColors.primary),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: _ProfileColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: _ProfileColors.primary.withOpacity(0.15),
                  child: Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: _ProfileColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 28),
                  ),
                ),
                const SizedBox(height: 12),
                Text(profile.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(profile.specialization,
                    style: const TextStyle(
                        color: _ProfileColors.textMuted, fontSize: 13)),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _ProfileColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _reviewCount == 0
                            ? 'No reviews yet'
                            : '${_avgRating.toStringAsFixed(1)} ($_reviewCount review${_reviewCount == 1 ? '' : 's'})',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _ProfileColors.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionCard('Contact Information', [
            _infoRow(Icons.email_outlined, 'Email', profile.email),
            _infoRow(Icons.phone_outlined, 'Phone', profile.phone),
            _infoRow(Icons.badge_outlined, 'CNIC', profile.cnic),
          ]),
          const SizedBox(height: 16),
          _sectionCard('Professional Details', [
            _infoRow(Icons.medical_services_outlined, 'Specialization',
                profile.specialization),
            _infoRow(Icons.workspace_premium_outlined, 'License No.',
                profile.license),
            _infoRow(
                Icons.apartment_outlined, 'Department', profile.departmentName),
          ]),
          const SizedBox(height: 16),
          _sectionCard('Consultation Timing', [
            _infoRow(
              Icons.schedule_outlined,
              'Available Hours',
              (profile.appointmentStartTime != null &&
                      profile.appointmentEndTime != null)
                  ? '${profile.appointmentStartTime} - ${profile.appointmentEndTime}'
                  : 'Not set by admin yet',
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openEditDialog,
              icon: const Icon(Icons.edit_outlined,
                  color: _ProfileColors.primary),
              label: const Text('Edit Profile',
                  style: TextStyle(color: _ProfileColors.primary)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _ProfileColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout, color: Colors.white),
              label:
                  const Text('Logout', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _ProfileColors.error,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _ProfileColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
          Icon(icon, size: 18, color: _ProfileColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: _ProfileColors.textMuted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
