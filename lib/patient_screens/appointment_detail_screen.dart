import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// SCHEMA COMPLIANCE:
/// - Status names: Requested/Confirmed/InProgress/Completed/Cancelled/NoShow
/// - Reschedule NAHI hai (schema mein exist nahi karta)
/// - Lab tests: sirf status + testType dikhta hai ("Normal/High" nahi —
///   schema mein result-interpretation field nahi hai)
/// - Feedback: feedbackId = appointmentId (uniqueness rule) —
///   ek appointment ki sirf ek feedback, sirf Completed ke baad
class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailScreen({super.key, required this.appointmentId});

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  Map<String, dynamic>? _appt;
  String _doctorName = '';
  String _specialization = '';
  String _dateLabel = '';
  String _timeLabel = '';
  List<Map<String, dynamic>> _labTests = [];
  bool _hasFeedback = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _isLoading = true);
    try {
      final apptDoc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .get();
      if (!apptDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }
      _appt = apptDoc.data();

      final doctorDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_appt!['doctorId'])
          .get();
      _doctorName = doctorDoc.data()?['name'] ?? 'Doctor';

      final profileDoc = await FirebaseFirestore.instance
          .collection('doctor_profiles')
          .doc(_appt!['doctorId'])
          .get();
      _specialization =
          profileDoc.exists ? (profileDoc.data()?['specialization'] ?? '') : '';

      final slotId = _appt!['slotId'];
      if (slotId != null) {
        final slotDoc = await FirebaseFirestore.instance
            .collection('slots')
            .doc(slotId)
            .get();
        if (slotDoc.exists) {
          final slotData = slotDoc.data()!;
          try {
            final date = DateTime.parse(slotData['date']);
            _dateLabel = DateFormat('d MMM, yyyy').format(date);
          } catch (_) {}
          _timeLabel = slotData['startTime'] ?? '';
        }
      }

      // Lab tests for this appointment (IN_PERSON/WALK_IN only per schema)
      final testsSnap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('appointmentId', isEqualTo: widget.appointmentId)
          .get();
      _labTests =
          testsSnap.docs.map((d) => {'testId': d.id, ...d.data()}).toList();

      // Feedback uniqueness rule: doc ID == appointmentId
      final feedbackDoc = await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.appointmentId)
          .get();
      _hasFeedback = feedbackDoc.exists;

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ── Feedback: sirf Completed ke baad, sirf ek dafa ────────
  Future<void> _showFeedbackDialog() async {
    int rating = 5;
    final commentController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Rate your visit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    onPressed: () => setDialogState(() => rating = i + 1),
                    icon: Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 30,
                    ),
                  );
                }),
              ),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Comment (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              child:
                  const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (submitted != true) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final feedbackRef = FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.appointmentId); // feedbackId = appointmentId (rule)

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final existing = await transaction.get(feedbackRef);
        if (existing.exists) {
          throw Exception('Feedback already submitted for this appointment');
        }
        transaction.set(feedbackRef, {
          'feedbackId': widget.appointmentId,
          'appointmentId': widget.appointmentId,
          'patientId': uid,
          'doctorId': _appt!['doctorId'],
          'rating': rating,
          'comment': commentController.text.trim().isEmpty
              ? null
              : commentController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Thank you for your feedback!'),
        backgroundColor: _primary,
      ));
      setState(() => _hasFeedback = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: const Color(0xFFDB4437),
      ));
    }
  }

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
                  : _appt == null
                      ? const Center(child: Text('Appointment not found'))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDoctorCard(),
                              const SizedBox(height: 14),
                              _buildInfoRow(),
                              const SizedBox(height: 20),
                              _buildStatusBanner(),
                              if (_appt!['symptoms'] != null) ...[
                                const SizedBox(height: 20),
                                _sectionTitle('Symptoms'),
                                const SizedBox(height: 8),
                                _buildSymptomsCard(),
                              ],
                              if (_labTests.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                _sectionTitle('Lab tests'),
                                const SizedBox(height: 8),
                                ..._labTests.map(_testCard),
                              ],
                              if (_appt!['status'] == 'Completed' &&
                                  !_hasFeedback) ...[
                                const SizedBox(height: 20),
                                _buildFeedbackButton(),
                              ],
                              if (_hasFeedback) ...[
                                const SizedBox(height: 20),
                                const Center(
                                  child: Text(
                                    '✓ Feedback submitted',
                                    style: TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
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
          const Text('Appointment detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDoctorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _primary.withOpacity(0.15),
            child: const Icon(Icons.person, color: _primary, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_doctorName,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A))),
                const SizedBox(height: 2),
                Text(_specialization,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    final typeLabel = _appt!['appointmentType'] == 'VIDEO_CALL'
        ? 'Video call'
        : _appt!['appointmentType'] == 'WALK_IN'
            ? 'Walk-in'
            : 'In-clinic';
    return Row(
      children: [
        Expanded(
            child: _infoChip(Icons.calendar_today, 'Date',
                _dateLabel.isEmpty ? '—' : _dateLabel)),
        const SizedBox(width: 10),
        Expanded(
            child: _infoChip(Icons.access_time, 'Time',
                _timeLabel.isEmpty ? '—' : _timeLabel)),
        const SizedBox(width: 10),
        Expanded(child: _infoChip(Icons.business_outlined, 'Type', typeLabel)),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: _primary, size: 18),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2F3A)));
  }

  Widget _buildStatusBanner() {
    final status = _appt!['status'] ?? '';
    IconData icon;
    Color color;
    Color bg;
    String title;
    String message;

    switch (status) {
      case 'Requested':
        icon = Icons.access_time;
        color = const Color(0xFFB8860B);
        bg = const Color(0xFFFCEFD8);
        title = 'Awaiting confirmation';
        message =
            'Your request has been sent. You will be notified once the hospital confirms it.';
        break;
      case 'Confirmed':
        icon = Icons.check_circle_outline;
        color = _primary;
        bg = const Color(0xFFDCEFE9);
        title = 'Appointment confirmed';
        message = _appt!['appointmentType'] == 'VIDEO_CALL'
            ? 'Join the video call at your slot time.'
            : 'Please arrive 10 minutes early.';
        break;
      case 'InProgress':
        icon = Icons.videocam_outlined;
        color = const Color(0xFF7E57C2);
        bg = const Color(0xFFEAE3F7);
        title = 'Consultation in progress';
        message = 'Your video consultation has started.';
        break;
      case 'Completed':
        icon = Icons.check_circle;
        color = _primary;
        bg = const Color(0xFFDCEFE9);
        title = 'Visit completed';
        message = 'Prescriptions and reports are available in their sections.';
        break;
      case 'Cancelled':
        icon = Icons.cancel_outlined;
        color = const Color(0xFFD9534F);
        bg = const Color(0xFFFDE6E0);
        title = 'Appointment cancelled';
        message = 'This appointment has been cancelled.';
        break;
      case 'NoShow':
        icon = Icons.person_off_outlined;
        color = Colors.grey;
        bg = Colors.grey.withOpacity(0.15);
        title = 'Marked as no-show';
        message = 'You did not attend this appointment.';
        break;
      default:
        icon = Icons.info_outline;
        color = Colors.grey;
        bg = Colors.grey.withOpacity(0.15);
        title = status;
        message = '';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(message,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymptomsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Text(_appt!['symptoms'],
          style: const TextStyle(fontSize: 13, color: Colors.black87)),
    );
  }

  Widget _testCard(Map<String, dynamic> test) {
    final status = test['status'] ?? '';
    Color bg;
    Color textColor;
    switch (status) {
      case 'Completed':
        bg = const Color(0xFFDCEFE9);
        textColor = _primary;
        break;
      case 'In Progress':
        bg = const Color(0xFFD9ECF8);
        textColor = const Color(0xFF1565C0);
        break;
      case 'Cancelled':
        bg = const Color(0xFFFDE6E0);
        textColor = const Color(0xFFD9534F);
        break;
      default: // Pending
        bg = const Color(0xFFFCEFD8);
        textColor = const Color(0xFFB8860B);
    }

    final isPaid = test['paymentStatus'] == 'Paid';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.science_outlined, color: _primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(test['testType'] ?? '',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A2F3A))),
                const SizedBox(height: 2),
                Text(
                  isPaid
                      ? 'Rs. ${test['charge']} — Paid'
                      : 'Rs. ${test['charge']} — Pay at reception',
                  style: TextStyle(
                      fontSize: 11,
                      color: isPaid ? _primary : const Color(0xFFB8860B)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text(status,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackButton() {
    return Center(
      child: OutlinedButton.icon(
        onPressed: _showFeedbackDialog,
        icon: const Icon(Icons.star_border, color: _primary, size: 18),
        label: const Text(
          'Leave Feedback',
          style: TextStyle(color: _primary, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          side: const BorderSide(color: _primary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }
}
