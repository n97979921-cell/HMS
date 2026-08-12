// lib/doctor_screens/appointment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'doctor_repository.dart';
import 'add_prescription_screen.dart';
import 'patient_profile_view_screen.dart';
import 'request_lab_test_screen.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';

class _DetailColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const error = Color(0xFFD64545);
}

class AppointmentDetailScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String doctorId;
  final DoctorAppointmentListItem appointment;
  final String dateLabel;

  const AppointmentDetailScreen({
    super.key,
    required this.repository,
    required this.doctorId,
    required this.appointment,
    required this.dateLabel,
  });

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  late AppointmentStatus _currentStatus;
  late bool _admissionRecommended;
  bool _isStarting = false;
  bool _isCompleting = false;
  bool _isTogglingAdmission = false;
  bool _isMarkingNoShow = false;
  bool _hasPrescription = false; // check hoga initState mein

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.appointment.status;
    _admissionRecommended = widget.appointment.admissionRecommended;
    _checkExistingPrescription();
  }

  // Ek appointment ki sirf EK prescription honi chahiye (schema-rule).
  // Screen khulते hi check karo — agar pehle se ban chuki hai, "Add
  // Prescription" button poori tarah hide kar do.
  Future<void> _checkExistingPrescription() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('prescriptions')
          .where('appointmentId', isEqualTo: widget.appointment.appointmentId)
          .limit(1)
          .get();
      if (mounted && snap.docs.isNotEmpty) {
        setState(() => _hasPrescription = true);
      }
    } catch (_) {
      // fail ho to button dikhta rahega — silent, koi crash nahi
    }
  }

  bool get _isVideoCall =>
      widget.appointment.appointmentType == AppointmentType.videoCall;

  bool get _isCompleted => _currentStatus == AppointmentStatus.completed;
  bool get _isConfirmed => _currentStatus == AppointmentStatus.confirmed;
  bool get _isInProgress => _currentStatus == AppointmentStatus.inProgress;

  bool get _visitIsActiveOrDone =>
      _currentStatus == AppointmentStatus.confirmed ||
      _currentStatus == AppointmentStatus.checkedIn ||
      _currentStatus == AppointmentStatus.inProgress ||
      _currentStatus == AppointmentStatus.completed;

  /// Lab-test request sirf ACTIVE consultation ke dauran ho sakta hai
  /// — Completed hone ke baad "Request Lab Test" button poori tarah
  /// GHAYAB (Admission-toggle jaisa "locked-but-visible" nahi, balke
  /// bilkul hidden — kyunki naya lab-test request ek naya clinical
  /// decision hai jo consultation ke baad lena sahi nahi).
  bool get _canRequestLabTest =>
      _currentStatus == AppointmentStatus.confirmed ||
      _currentStatus == AppointmentStatus.checkedIn ||
      _currentStatus == AppointmentStatus.inProgress;

  /// Admission recommendation sirf ACTIVE consultation ke dauran editable
  /// hai. Completed hone ke baad LOCKED — sirf dekhne ke liye, kyunki
  /// receptionist is decision par bed/room assign kar sakta hai; baad
  /// mein badalna data inconsistent kar deta.
  bool get _admissionEditable =>
      _currentStatus == AppointmentStatus.confirmed ||
      _currentStatus == AppointmentStatus.checkedIn ||
      _currentStatus == AppointmentStatus.inProgress;

  /// VIDEO CALL: Start/Join buttons slot-time se 5 min PEHLE se active.
  /// Appointment ka waqt widget se seedha nahi milta (sirf slotTime
  /// string, jaise "15:00") — is liye dateLabel se date parse karke
  /// poora DateTime banate hain. Agar parse fail ho (unlikely), fail-open
  /// karte hain (button active rakhte hain) taake doctor block na ho.
  bool get _isWithinJoinWindow {
    try {
      final timeParts = widget.appointment.slotTime.split(':');
      // dateLabel format: "10 Aug 2026" — parse karo asal appointment
      // date nikalne ke liye, "aaj" assume mat karo.
      final dateParts = widget.dateLabel.split(' ');
      const months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final day = int.parse(dateParts[0]);
      final month = months[dateParts[1]]!;
      final year = int.parse(dateParts[2]);

      final slotDateTime = DateTime(
          year, month, day, int.parse(timeParts[0]), int.parse(timeParts[1]));
      final now = DateTime.now();
      final windowStart = slotDateTime.subtract(const Duration(minutes: 5));
      return now.isAfter(windowStart);
    } catch (_) {
      return true; // fail-open
    }
  }

  String get _roomUrl =>
      'https://meet.jit.si/FamilyWellCare-${widget.appointment.appointmentId}';

  Future<void> _openJitsi() async {
    final uri = Uri.parse(_roomUrl);
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open video call. Please try again.'),
          backgroundColor: _DetailColors.error,
        ),
      );
    }
  }

  Future<void> _startConsultation() async {
    setState(() => _isStarting = true);
    try {
      await widget.repository.startVideoConsultation(
        appointmentId: widget.appointment.appointmentId,
      );
      if (mounted) {
        setState(() {
          _currentStatus = AppointmentStatus.inProgress;
          _isStarting = false;
        });
        await _openJitsi();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start consultation: $e'),
            backgroundColor: _DetailColors.error,
          ),
        );
      }
    }
  }

  /// Doctor karta hai — in-person, walk-in, video, teeno ke liye
  /// (updated schema). In-person/walk-in: sirf CheckedIn se. Video:
  /// sirf InProgress se.
  Future<void> _markCompleted() async {
    setState(() => _isCompleting = true);
    try {
      await widget.repository.updateAppointmentStatus(
        appointmentId: widget.appointment.appointmentId,
        status: 'Completed',
      );
      if (mounted) {
        setState(() {
          _currentStatus = AppointmentStatus.completed;
          _isCompleting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment marked as completed'),
            backgroundColor: _DetailColors.primary,
          ),
        );
        // Screen par hi raho — doctor turant Add Prescription kar sake.
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: _DetailColors.error,
          ),
        );
      }
    }
  }

  /// VIDEO CALL ONLY: doctor Start kar chuka (InProgress) lekin patient
  /// join nahi hua. Manual foran-wala option (lazy-check bhi hai list
  /// screen mein, yeh us se pehle ka fast-path hai agar doctor khud
  /// dekh le ke patient nahi aaya). → NoShow + HALF refund.
  Future<void> _markPatientDidNotJoin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Patient did not join?'),
        content: const Text(
            'This will mark the appointment as a no-show. A HALF refund '
            'will be added to pending refunds for the patient.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8860B)),
            child: const Text('Confirm — Half Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isMarkingNoShow = true);
    try {
      await widget.repository.updateAppointmentStatus(
        appointmentId: widget.appointment.appointmentId,
        status: 'NoShow',
      );
      // NOTE: refund-status update repository ke through nahi ho raha
      // (DoctorRepository mein payment update ka method nahi hai — yeh
      // jaan-boojh kar hai, payment sirf receptionist-side se touch hoti
      // hai). Lazy-check list-screen mein isko HalfRefunded set kar dega
      // agli load par. Yahan sirf appointment-status set kar rahe hain.
      if (mounted) {
        setState(() {
          _currentStatus = AppointmentStatus.noShow;
          _isMarkingNoShow = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marked as no-show'),
            backgroundColor: Color(0xFFB8860B),
          ),
        );
        Navigator.pop(context, true); // list refresh ho
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isMarkingNoShow = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: _DetailColors.error,
          ),
        );
      }
    }
  }

  Widget _buildActionSection() {
    if (_isCompleted) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _DetailColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle,
                    color: _DetailColors.primary, size: 18),
                SizedBox(width: 8),
                Text('Visit completed',
                    style: TextStyle(
                        color: _DetailColors.primary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (!_hasPrescription) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAddPrescription,
                icon: const Icon(Icons.receipt_long_outlined,
                    color: Colors.white),
                label: const Text('Add Prescription',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _DetailColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ],
        ],
      );
    }

    if (_currentStatus == AppointmentStatus.noShow) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFB8860B).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined, color: Color(0xFFB8860B), size: 18),
            SizedBox(width: 8),
            Text('Marked as no-show',
                style: TextStyle(
                    color: Color(0xFFB8860B), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    if (!_isVideoCall) {
      // IN_PERSON / WALK_IN — doctor marks completed (updated schema).
      if (_currentStatus == AppointmentStatus.checkedIn) {
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isCompleting ? null : _markCompleted,
            icon: _isCompleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, color: Colors.white),
            label: const Text('Mark Completed',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _DetailColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: _DetailColors.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: _DetailColors.textMuted, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('Waiting for patient to check in at reception.',
                  style:
                      TextStyle(color: _DetailColors.textMuted, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // ── VIDEO_CALL, not yet completed ──
    if (_isConfirmed) {
      final canStart = _isWithinJoinWindow;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: (_isStarting || !canStart) ? null : _startConsultation,
            icon: _isStarting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.videocam, color: Colors.white),
            label: Text(
              canStart
                  ? 'Start Consultation'
                  : 'Available 5 min before slot time',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _DetailColors.primary,
              disabledBackgroundColor:
                  _DetailColors.textMuted.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
          if (!canStart) ...[
            const SizedBox(height: 8),
            const Text(
              'The Start button will activate 5 minutes before the '
              'scheduled time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _DetailColors.textMuted),
            ),
          ],
        ],
      );
    }

    if (_isInProgress) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openJitsi,
              icon: const Icon(Icons.videocam, color: _DetailColors.primary),
              label: const Text('Rejoin Video Consultation',
                  style: TextStyle(color: _DetailColors.primary)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _DetailColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCompleting ? null : _markCompleted,
              icon: _isCompleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, color: Colors.white),
              label: const Text('Mark Completed',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _DetailColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isMarkingNoShow ? null : _markPatientDidNotJoin,
              icon: _isMarkingNoShow
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Color(0xFFB8860B), strokeWidth: 2))
                  : const Icon(Icons.person_off_outlined,
                      color: Color(0xFFB8860B), size: 18),
              label: const Text('Patient Didn\'t Join',
                  style: TextStyle(color: Color(0xFFB8860B))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFB8860B)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  void _openPatientProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientProfileViewScreen(
          repository: widget.repository,
          patientId: widget.appointment.patientId,
        ),
      ),
    );
  }

  void _openRequestLabTest() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestLabTestScreen(
          repository: widget.repository,
          appointmentId: widget.appointment.appointmentId,
          doctorId: widget.doctorId,
          patientId: widget.appointment.patientId,
          patientName: widget.appointment.patientName,
        ),
      ),
    );
  }

  Future<void> _toggleAdmissionRecommendation(bool value) async {
    final previous = _admissionRecommended;
    setState(() {
      _admissionRecommended = value;
      _isTogglingAdmission = true;
    });
    try {
      await widget.repository.recommendAdmission(
        appointmentId: widget.appointment.appointmentId,
        recommended: value,
      );

      // ── NOTIFICATION: Admission Recommended → Receptionist ──
      // Sirf jab ON kiya jaye (value == true), OFF karne par nahi.
      if (value) {
        final receptionistSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'receptionist')
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();
        if (receptionistSnap.docs.isNotEmpty) {
          await NotificationService.send(
            userId: receptionistSnap.docs.first.id,
            type: 'RoomRecommendation',
            referenceId: widget.appointment.appointmentId,
            message:
                'Dr. recommends admission for ${widget.appointment.patientName}.',
          );
        }
      }

      if (mounted) setState(() => _isTogglingAdmission = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _admissionRecommended = previous;
          _isTogglingAdmission = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: _DetailColors.error,
          ),
        );
      }
    }
  }

  void _openAddPrescription() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPrescriptionScreen(
          repository: widget.repository,
          appointmentId: widget.appointment.appointmentId,
          doctorId: widget.doctorId,
          patientId: widget.appointment.patientId,
          patientName: widget.appointment.patientName,
        ),
      ),
    );
    // Prescription save ho chuki — turant button hide karo (screen
    // pe hi rukte huae bhi dobara-Add possible na ho).
    if (saved == true && mounted) {
      setState(() => _hasPrescription = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DetailColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPatientCard(),
                  const SizedBox(height: 16),
                  if ((widget.appointment.symptoms?.isNotEmpty ?? false) ||
                      widget.appointment.patientReportBase64 != null) ...[
                    _buildAppointmentInfoCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildInfoRow(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openPatientProfile,
                      icon: const Icon(Icons.person_search_outlined,
                          color: _DetailColors.primary),
                      label: const Text('View Patient Profile',
                          style: TextStyle(color: _DetailColors.primary)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _DetailColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  if (_visitIsActiveOrDone) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: _DetailColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _admissionRecommended,
                        onChanged: (_isTogglingAdmission || !_admissionEditable)
                            ? null
                            : _toggleAdmissionRecommendation,
                        activeColor: _DetailColors.primary,
                        title: const Text('Recommend Admission',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _admissionEditable
                              ? 'Flags this patient for receptionist to assign a room/bed'
                              : 'Locked — visit completed',
                          style: const TextStyle(
                              fontSize: 11, color: _DetailColors.textMuted),
                        ),
                      ),
                    ),
                    if (!_isVideoCall && _canRequestLabTest) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openRequestLabTest,
                          icon: const Icon(Icons.science_outlined,
                              color: _DetailColors.primary),
                          label: const Text('Request Lab Test',
                              style: TextStyle(color: _DetailColors.primary)),
                          style: OutlinedButton.styleFrom(
                            side:
                                const BorderSide(color: _DetailColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  _buildActionSection(),
                ],
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
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_DetailColors.primary, _DetailColors.primaryDark],
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
            onPressed: () => Navigator.pop(context,
                _isCompleted || _currentStatus == AppointmentStatus.noShow),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Text('Appointment Detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPatientCard() {
    final appointment = widget.appointment;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DetailColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _DetailColors.primary.withValues(alpha: 0.15),
            child: Text(
              appointment.patientName.isNotEmpty
                  ? appointment.patientName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: _DetailColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.patientName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                        _isVideoCall
                            ? Icons.videocam_outlined
                            : Icons.storefront_outlined,
                        size: 14,
                        color: _DetailColors.textMuted),
                    const SizedBox(width: 4),
                    Text(appointment.appointmentType.label,
                        style: const TextStyle(
                            fontSize: 12, color: _DetailColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DetailColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Provided by patient',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (widget.appointment.symptoms?.isNotEmpty ?? false) ...[
            const Text('Symptoms',
                style: TextStyle(fontSize: 11, color: _DetailColors.textMuted)),
            const SizedBox(height: 4),
            Text(widget.appointment.symptoms!,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
          ],
          if (widget.appointment.patientReportBase64 != null) ...[
            const Text('Attached report',
                style: TextStyle(fontSize: 11, color: _DetailColors.textMuted)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                base64Decode(widget.appointment.patientReportBase64!),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                    'Could not load attached image',
                    style: TextStyle(
                        fontSize: 12, color: _DetailColors.textMuted)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    return Row(
      children: [
        Expanded(
            child: _infoTile(
                Icons.calendar_today_outlined, 'Date', widget.dateLabel)),
        const SizedBox(width: 12),
        Expanded(
            child: _infoTile(
                Icons.access_time, 'Time', widget.appointment.slotTime)),
        const SizedBox(width: 12),
        Expanded(
            child:
                _infoTile(Icons.info_outline, 'Status', _currentStatus.name)),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: _DetailColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: _DetailColors.primary),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: _DetailColors.textMuted)),
          const SizedBox(height: 2),
          Text(value,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
