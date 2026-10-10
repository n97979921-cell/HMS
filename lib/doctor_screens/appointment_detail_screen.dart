// lib/doctor_screens/appointment_detail_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
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
import 'package:http/http.dart' as http;

class _DetailColors {
  static const primary = Color(0xFF0E6E68);
  static const error = Color(0xFFB23A1E);
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
    _wakeUpTokenServer(); // server ko pehle hi jaga do
  }

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
    } catch (_) {}
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

  bool get _canRequestLabTest =>
      _currentStatus == AppointmentStatus.confirmed ||
      _currentStatus == AppointmentStatus.checkedIn ||
      _currentStatus == AppointmentStatus.inProgress;

  bool get _admissionEditable =>
      _currentStatus == AppointmentStatus.confirmed ||
      _currentStatus == AppointmentStatus.checkedIn ||
      _currentStatus == AppointmentStatus.inProgress;

  /// VIDEO CALL: Start/Join buttons slot-time se 5 min PEHLE se active.
  /// Appointment ka waqt widget se seedha nahi milta (sirf slotTime
  /// string, jaise "15:00") — is liye dateLabel se date parse karke
  /// poora DateTime banate hain. Agar parse fail ho (unlikely), fail-open
  /// karte hain (button active rakhte hain) taake doctor block na ho.
  // Slot-time nikalne ka helper — dono naye getters is par depend karte
  // hain, is liye alag nikal liya (pehle _isWithinJoinWindow ke andar
  // hi tha).
  DateTime? get _slotDateTime {
    try {
      final timeParts = widget.appointment.slotTime.split(':');
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
      return DateTime(
          year, month, day, int.parse(timeParts[0]), int.parse(timeParts[1]));
    } catch (_) {
      return null;
    }
  }

  // Doctor ka "Start Consultation" — sirf pehli baar ke liye window:
  // slot-time se 5 min pehle se 5 min baad tak.
  bool get _isWithinJoinWindow {
    final slotDateTime = _slotDateTime;
    if (slotDateTime == null) return true; // fail-open
    final now = DateTime.now();
    final windowStart = slotDateTime.subtract(const Duration(minutes: 5));
    final windowEnd = slotDateTime.add(const Duration(minutes: 5));
    return now.isAfter(windowStart) && now.isBefore(windowEnd);
  }

  // "Patient Didn't Join" button — sirf window guzarne ke BAAD enable,
  // taake doctor jaldi mein ghalat na dabaye.
  bool get _isPastNoShowWindow {
    final slotDateTime = _slotDateTime;
    if (slotDateTime == null) return false;
    final windowEnd = slotDateTime.add(const Duration(minutes: 5));
    return DateTime.now().isAfter(windowEnd);
  }

  // ── APNI DETAILS YAHAN DAALEIN (jaise server.js mein daali thi) ──
  static const String _jaasAppId =
      'vpaas-magic-cookie-b97ea521398a41ffbf90f00437e433a7';
  // Emulator ke liye 'localhost' theek hai. Physical phone par test
  // karte waqt, isko apne laptop ka LAN IP se replace karein
  // (jaise 'http://192.168.1.5:3000').
  static const String _tokenServerUrl = 'https://jitsi-jwt-server-3.bonto.run';

  String get _roomName => 'FamilyWellCare-${widget.appointment.appointmentId}';

  // Free server so jata hai, pehli request par late jagta hai.
  // Screen khulte hi ek halki request bhej dete hain taake
  // "Start" dabane tak server jag chuka ho.
  void _wakeUpTokenServer() {
    http
        .get(Uri.parse(_tokenServerUrl))
        .timeout(const Duration(seconds: 30))
        .catchError((_) => http.Response('', 500));
  }

  // Token 3 dafa try karta hai, har dafa 20 second wait karta hai.
  Future<String?> _fetchToken() async {
    final uri = Uri.parse(
      '$_tokenServerUrl/token?room=$_roomName&name=Dr.${widget.doctorId}&moderator=true',
    );
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['token'] as String;
        }
      } catch (e) {
        print('TOKEN FETCH ERROR (try $attempt): $e');
      }
      if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<void> _openJitsi() async {
    final token = await _fetchToken();

    // Token na mile to meet.jit.si par NAHI bhejna — wahan
    // "moderator not set" aata hai. User ko dobara try karne ka bolo.
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Video server is starting. Please wait a moment and tap again.'),
            backgroundColor: _DetailColors.error,
          ),
        );
      }
      return;
    }

    final roomUrl = 'https://8x8.vc/$_jaasAppId/$_roomName?jwt=$token';

    final uri = Uri.parse(roomUrl);
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
  /// Doctor manually confirm karta hai ke patient nahi aaya (window
  /// guzarne ke baad hi enable hota hai). Status aur payment DONO ek
  /// hi transaction mein update hote hain — is se lazy-check jaisi
  /// reliability milti hai, aur payment kabhi 'Paid' pe atki nahi
  /// rehti (jo purani version ka bug tha).
  Future<void> _markPatientDidNotJoin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Patient did not join?',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
        content: const Text(
            'This will mark the appointment as a no-show. A HALF refund '
            'will be added to pending refunds for the patient.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A6D00), elevation: 0),
            child: const Text('Confirm — Half Refund',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isMarkingNoShow = true);
    bool alreadyJoined = false;
    try {
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointment.appointmentId);

      // Payment reference PEHLE nikalo (Firestore transaction ke andar
      // collection-query allowed nahi hoti, sirf single-doc .get()).
      final paySnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('appointmentId', isEqualTo: widget.appointment.appointmentId)
          .where('status', isEqualTo: 'Paid')
          .limit(1)
          .get();
      final payRef =
          paySnap.docs.isNotEmpty ? paySnap.docs.first.reference : null;
      final payAmount = paySnap.docs.isNotEmpty
          ? (paySnap.docs.first.data()['amount'] ?? 0)
          : 0;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Fresh read — safety-check: kahin isi waqt patient join na
        // kar chuka ho (race-condition se bachao).
        final apptSnap = await transaction.get(apptRef);
        if (!apptSnap.exists) throw Exception('Appointment not found');

        final data = apptSnap.data()!;
        if (data['status'] != 'InProgress') {
          throw Exception('Appointment is no longer in progress.');
        }
        if (data['patientJoinedAt'] != null) {
          alreadyJoined = true;
          return; // abort — patient already join kar chuka
        }

        transaction.update(apptRef, {
          'status': 'NoShow',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (payRef != null) {
          transaction.update(payRef, {
            'status': 'HalfRefunded',
            'refundAmount': payAmount / 2,
            'refundPaid': false,
          });
        }
      });

      if (!mounted) return;

      if (alreadyJoined) {
        setState(() => _isMarkingNoShow = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Patient has already joined — cannot mark as no-show.'),
            backgroundColor: _DetailColors.error,
          ),
        );
        return;
      }

      // ── NOTIFICATION: Video Missed → Receptionist ──
      final receptionistSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'receptionist')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (receptionistSnap.docs.isNotEmpty) {
        await NotificationService.send(
          userId: receptionistSnap.docs.first.id,
          type: 'VideoConsultation',
          referenceId: widget.appointment.appointmentId,
          message: 'A patient missed their video consultation.',
        );
      }

      setState(() {
        _currentStatus = AppointmentStatus.noShow;
        _isMarkingNoShow = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked as no-show — half refund queued'),
          backgroundColor: Color(0xFF8A6D00),
        ),
      );
      Navigator.pop(context, true); // list refresh ho
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

  ButtonStyle _darkBtn() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.header,
        disabledBackgroundColor: const Color(0xFFE6ECEC),
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  ButtonStyle _outlineBtn(Color border) => OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: BorderSide(color: border),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _banner(IconData icon, String text, Color fg, Color bg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: fg, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSection() {
    if (_isCompleted) {
      return Column(
        children: [
          _banner(Icons.check_circle_rounded, 'Visit completed',
              const Color(0xFF0B5E57), const Color(0xFFDDF3EE)),
          if (!_hasPrescription) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAddPrescription,
                icon: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.mint),
                label: const Text('Add Prescription',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                style: _darkBtn(),
              ),
            ),
          ],
        ],
      );
    }

    if (_currentStatus == AppointmentStatus.noShow) {
      return _banner(Icons.event_busy_outlined, 'Marked as no-show',
          const Color(0xFF8A6D00), const Color(0xFFF6F2E2));
    }

    if (!_isVideoCall) {
      // IN_PERSON / WALK_IN — doctor marks completed
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
                        color: AppColors.teal, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, color: AppColors.mint),
            label: const Text('Mark Completed',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            style: _darkBtn(),
          ),
        );
      }
      return _banner(
          Icons.info_outline,
          'Waiting for patient to check in at reception.',
          AppColors.muted,
          const Color(0xFFE6ECEC));
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
                        color: AppColors.teal, strokeWidth: 2))
                : Icon(Icons.videocam_rounded,
                    color: canStart ? AppColors.mint : AppColors.faint),
            label: Text(
              canStart
                  ? 'Start Consultation'
                  : 'Available 5 min before slot time',
              style: TextStyle(
                  color: canStart ? Colors.white : AppColors.faint,
                  fontSize: 15,
                  fontWeight: FontWeight.w800),
            ),
            style: _darkBtn(),
          ),
          if (!canStart) ...[
            const SizedBox(height: 8),
            const Text(
              'The Start button will activate 5 minutes before the '
              'scheduled time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.faint),
            ),
          ],
        ],
      );
    }

    if (_isInProgress) {
      final canMarkNoShow = _isPastNoShowWindow;
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openJitsi,
              icon: const Icon(Icons.videocam_rounded, color: AppColors.text),
              label: const Text('Rejoin Video Consultation',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              style: _outlineBtn(AppColors.border),
            ),
          ),
          const SizedBox(height: 8),
          // ── Advisory note: agar patient nahi aaya, call end karo ──
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'If the patient hasn\'t joined, please end the call within '
              '5 minutes of the appointment time to avoid an unfair charge.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, height: 1.45, color: AppColors.faint),
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
                          color: AppColors.teal, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline,
                      color: AppColors.mint),
              label: const Text('Mark Completed',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              style: _darkBtn(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_isMarkingNoShow || !canMarkNoShow)
                  ? null
                  : _markPatientDidNotJoin,
              icon: _isMarkingNoShow
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Color(0xFF8A6D00), strokeWidth: 2))
                  : Icon(Icons.person_off_outlined,
                      color: canMarkNoShow
                          ? const Color(0xFF8A6D00)
                          : AppColors.faint,
                      size: 18),
              label: Text(
                canMarkNoShow
                    ? 'Patient Didn\'t Join'
                    : 'Available 5 min after appointment time',
                style: TextStyle(
                    color: canMarkNoShow
                        ? const Color(0xFF8A6D00)
                        : AppColors.faint,
                    fontSize: 14,
                    fontWeight: FontWeight.w800),
              ),
              style: _outlineBtn(
                  canMarkNoShow ? const Color(0xFFE8D9A6) : AppColors.border),
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
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                _buildPatientCard(),
                const SizedBox(height: 12),
                if (widget.appointment.symptoms?.isNotEmpty ?? false) ...[
                  _buildAppointmentInfoCard(),
                  const SizedBox(height: 12),
                ],
                _buildInfoRow(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openPatientProfile,
                    icon: const Icon(Icons.person_search_outlined,
                        color: AppColors.text),
                    label: const Text('View Patient Profile',
                        style: TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    style: _outlineBtn(AppColors.border),
                  ),
                ),
                if (_visitIsActiveOrDone) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _admissionRecommended,
                      onChanged: (_isTogglingAdmission || !_admissionEditable)
                          ? null
                          : _toggleAdmissionRecommendation,
                      activeColor: Colors.white,
                      activeTrackColor: AppColors.teal,
                      secondary: const AppIconTile(
                        icon: Icons.bed_outlined,
                        color: Color(0xFF5B3FA8),
                        background: Color(0xFFEEE8FB),
                        size: 40,
                      ),
                      title: const Text('Recommend Admission',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text)),
                      subtitle: Text(
                        _admissionEditable
                            ? 'Flags this patient for receptionist to assign a room/bed'
                            : 'Locked — visit completed',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ),
                  if (!_isVideoCall && _canRequestLabTest) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openRequestLabTest,
                        icon: const Icon(Icons.science_outlined,
                            color: AppColors.text),
                        label: const Text('Request Lab Test',
                            style: TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        style: _outlineBtn(AppColors.border),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                _buildActionSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final appointment = widget.appointment;
    return AppHeader(
      title: 'Appointment Detail',
      subtitle:
          '${appointment.appointmentType.label} · ${appointment.slotTime}',
      onBack: () => Navigator.pop(
          context, _isCompleted || _currentStatus == AppointmentStatus.noShow),
    );
  }

  // UI only: status chip colours
  AppChipColors _statusChipColors() {
    switch (_currentStatus) {
      case AppointmentStatus.completed:
      case AppointmentStatus.confirmed:
        return const AppChipColors(Color(0xFF0B5E57), Color(0xFFDDF3EE));
      case AppointmentStatus.inProgress:
        return const AppChipColors(Color(0xFF5B3FA8), Color(0xFFEEE8FB));
      case AppointmentStatus.noShow:
        return const AppChipColors(Color(0xFF8A6D00), Color(0xFFF6F2E2));
      case AppointmentStatus.checkedIn:
        return const AppChipColors(AppColors.blue, AppColors.blueSoft);
      default:
        return const AppChipColors(AppColors.muted, Color(0xFFEEF1F1));
    }
  }

  Widget _buildPatientCard() {
    final appointment = widget.appointment;
    final Color typeColor = _isVideoCall ? AppColors.blue : AppColors.teal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.tealSoft,
            child: Text(
              appointment.patientName.isNotEmpty
                  ? appointment.patientName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w800,
                  fontSize: 19),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.patientName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                        _isVideoCall
                            ? Icons.videocam_outlined
                            : Icons.storefront_outlined,
                        size: 14,
                        color: typeColor),
                    const SizedBox(width: 5),
                    Text(appointment.appointmentType.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: typeColor)),
                  ],
                ),
              ],
            ),
          ),
          AppStatusChip(
            label: _currentStatus.name,
            colors: _statusChipColors(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Provided by patient',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal)),
          const SizedBox(height: 8),
          if (widget.appointment.symptoms?.isNotEmpty ?? false) ...[
            const Text('Symptoms',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.faint)),
            const SizedBox(height: 3),
            Text(widget.appointment.symptoms!,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.5, color: AppColors.text)),
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
        const SizedBox(width: 8),
        Expanded(
            child: _infoTile(
                Icons.access_time, 'Time', widget.appointment.slotTime)),
        const SizedBox(width: 8),
        Expanded(
            child:
                _infoTile(Icons.info_outline, 'Status', _currentStatus.name)),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.teal),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.faint)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
        ],
      ),
    );
  }
}
