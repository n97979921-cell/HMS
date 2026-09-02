import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'book_appointment_screen.dart';

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
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

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
      backgroundColor: const Color(0xFFDB4437),
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
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _doctors.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadDoctors,
                          color: _primary,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 80),
                            children: [
                              Text(
                                'Available for ${_typeLabel.toLowerCase()}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2F3A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_doctors.length} doctor${_doctors.length == 1 ? '' : 's'} found',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 14),
                              ..._doctors.map(_doctorCard),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.departmentName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medical_services_outlined,
              size: 64, color: _primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'No doctors available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please check back later',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _doctorCard(Map<String, dynamic> doctor) {
    final avgRating = (doctor['avgRating'] as double);
    final reviewCount = doctor['reviewCount'] as int;
    final num fee = doctor['consultationFee'] as num;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _primary.withOpacity(0.1),
                child: const Icon(Icons.person, color: _primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor['name'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doctor['specialization'],
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 14),
              const SizedBox(width: 3),
              Text(
                reviewCount == 0
                    ? 'No reviews yet'
                    : '${avgRating.toStringAsFixed(1)} ($reviewCount review${reviewCount == 1 ? '' : 's'})',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rs. $fee',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A),
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
                child: Row(
                  children: const [
                    Text(
                      'Book now',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _primary,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16, color: _primary),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
