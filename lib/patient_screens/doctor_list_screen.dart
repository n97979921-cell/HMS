import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'book_appointment_screen.dart';
import '../widgets/app_ui.dart';

class DoctorListScreen extends StatefulWidget {
  final String departmentId;
  final String departmentName;
  // Schema appointmentType: 'IN_PERSON' | 'VIDEO_CALL'
  final String appointmentType;

  const DoctorListScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
    required this.appointmentType,
  });

  @override
  State<DoctorListScreen> createState() => _DoctorListScreenState();
}

class _DoctorListScreenState extends State<DoctorListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _doctors = [];

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    setState(() => _isLoading = true);
    try {
      // ---- Doctors in this department ----
      final profilesSnap = await FirebaseFirestore.instance
          .collection('doctor_profiles')
          .where('departmentId', isEqualTo: widget.departmentId)
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final profileDoc in profilesSnap.docs) {
        final doctorId = profileDoc.id;

        // Rule 1: Timing set hai? Agar nahi -> doctor hidden.
        final settingsDoc = await FirebaseFirestore.instance
            .collection('doctor_settings')
            .doc(doctorId)
            .get();
        if (!settingsDoc.exists) continue;

        // Rule 2: Fee set hai? (PER-DOCTOR ab, department se nahi)
        // Agar nahi -> doctor hidden.
        final feeDoc = await FirebaseFirestore.instance
            .collection('doctor_consultation_fees')
            .doc(doctorId)
            .get();
        if (!feeDoc.exists) continue;

        final feeData = feeDoc.data()!;
        final num fee = widget.appointmentType == 'VIDEO_CALL'
            ? (feeData['videoCallFee'] ?? 0) as num
            : (feeData['inPersonFee'] ?? 0) as num;
        if (fee <= 0) continue; // fee 0/unset = doctor hidden

        // Rule 3: User active hai?
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(doctorId)
            .get();
        if (!userDoc.exists) continue;
        if (userDoc.data()?['status'] != 'active') continue;

        // Average rating from feedback collection.
        final feedbackSnap = await FirebaseFirestore.instance
            .collection('feedback')
            .where('doctorId', isEqualTo: doctorId)
            .get();

        double avgRating = 0;
        if (feedbackSnap.docs.isNotEmpty) {
          final ratings = feedbackSnap.docs
              .map((d) => ((d.data()['rating'] ?? 0) as num).toDouble())
              .toList();
          avgRating = ratings.reduce((a, b) => a + b) / ratings.length;
        }

        result.add({
          'doctorId': doctorId,
          'name': userDoc.data()?['name'] ?? 'Doctor',
          'specialization': profileDoc.data()['specialization'] ?? '',
          'avgRating': avgRating,
          'reviewCount': feedbackSnap.docs.length,
          'consultationFee': fee, // har doctor ki apni fee
        });
      }

      // Sort by rating descending — highest rated first.
      result.sort((a, b) =>
          (b['avgRating'] as double).compareTo(a['avgRating'] as double));

      setState(() {
        _doctors = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading doctors: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String get _typeLabel => widget.appointmentType == 'VIDEO_CALL'
      ? 'Video consult'
      : 'In-clinic visit';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _doctors.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadDoctors,
                        color: AppColors.teal,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            Text(
                              '${_doctors.length} doctor${_doctors.length == 1 ? '' : 's'} found',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.teal,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._doctors.map(_doctorCard),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: widget.departmentName,
      subtitle: 'Available for ${_typeLabel.toLowerCase()}',
    );
  }

  Widget _buildEmptyState() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: AppEmptyState(
        icon: Icons.medical_services_outlined,
        title: 'No doctors available',
        subtitle: 'Please check back later',
      ),
    );
  }

  Widget _doctorCard(Map<String, dynamic> doctor) {
    final avgRating = (doctor['avgRating'] as double);
    final reviewCount = doctor['reviewCount'] as int;
    final num fee = doctor['consultationFee'] as num;
    final String name = '${doctor['name']}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.tealSoft,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doctor['specialization'],
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFF2B233), size: 15),
                        const SizedBox(width: 3),
                        Text(
                          reviewCount == 0
                              ? 'No reviews yet'
                              : '${avgRating.toStringAsFixed(1)} ($reviewCount review${reviewCount == 1 ? '' : 's'})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8A6D00),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Consultation fee',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.faint,
                      ),
                    ),
                    Text(
                      'Rs. $fee',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B5E57),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookAppointmentScreen(
                        doctorId: doctor['doctorId'],
                        doctorName: doctor['name'],
                        specialization: doctor['specialization'],
                        appointmentType: widget.appointmentType,
                        consultationFee: fee,
                        departmentId: widget.departmentId,
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 16, right: 10),
                  decoration: BoxDecoration(
                    color: AppColors.header,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Book now',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
