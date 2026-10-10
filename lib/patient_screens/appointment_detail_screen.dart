import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

/// PATIENT — APPOINTMENT DETAIL SCREEN
/// (lib/patient_screens/appointment_detail_screen.dart)
///
/// VIDEO CALL JOIN:
///  - Sirf VIDEO_CALL type + status InProgress mein active hota hai
///    (doctor pehle Start kar chuka ho).
///  - Slot-time se 5 min PEHLE se allow (jaise doctor side).
///  - Join dabate hi patientJoinedAt set hota hai (Firestore) — yeh
///    proxy hai "patient join hua" ke liye, kyunki Jitsi app se bahar
///    khulta hai aur wapas signal nahi deta.
///  - Agar status ab InProgress nahi hai (NoShow/Cancelled ho chuki,
///    lazy-check ne process kar diya), button DISABLED — "session ended".
class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailScreen({super.key, required this.appointmentId});

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  bool _isLoading = true;
  bool _isJoining = false;
  Map<String, dynamic>? _appt;
  Map<String, dynamic>? _slot;
  String _doctorName = '';
  StreamSubscription<DocumentSnapshot>? _apptSub;
  @override
  void initState() {
    super.initState();
    _load();
    _listenToAppointment();
    _wakeUpTokenServer(); // server ko pehle hi jaga do
  }

  // Real-time listener — sirf is appointment document ko sunta hai.
  // Doctor koi action le (Start/Complete/NoShow), yahan turant
  // reflect ho jayega — patient ko manually refresh nahi karna padega.
  void _listenToAppointment() {
    _apptSub = FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      setState(() => _appt = doc.data());
    });
  }

  @override
  void dispose() {
    _apptSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
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

      if (_appt!['slotId'] != null) {
        final slotDoc = await FirebaseFirestore.instance
            .collection('slots')
            .doc(_appt!['slotId'])
            .get();
        if (slotDoc.exists) _slot = slotDoc.data();
      }

      final doctorDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_appt!['doctorId'])
          .get();
      _doctorName = doctorDoc.data()?['name'] ?? 'Doctor';

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading appointment: $e');
    }
  }

  bool get _isVideoCall => _appt?['appointmentType'] == 'VIDEO_CALL';
  bool get _isInProgress => _appt?['status'] == 'InProgress';

  // Patient pehle ek dafa join kar chuka — matlab yeh ab rejoin hai.
  bool get _hasJoinedBefore => _appt?['patientJoinedAt'] != null;

  // SIRF pehli baar join karne ke liye window: slot-time se 5 min
  // pehle se 5 min baad tak. Rejoin par yeh window lagu NAHI hoti.
  bool get _isWithinJoinWindow {
    if (_slot == null) return false;
    try {
      final date = DateTime.parse(_slot!['date']);
      final timeParts = (_slot!['startTime'] as String).split(':');
      final slotDt = DateTime(date.year, date.month, date.day,
          int.parse(timeParts[0]), int.parse(timeParts[1]));
      final windowStart = slotDt.subtract(const Duration(minutes: 5));
      final windowEnd = slotDt.add(const Duration(minutes: 5));
      final now = DateTime.now();
      return now.isAfter(windowStart) && now.isBefore(windowEnd);
    } catch (_) {
      return false;
    }
  }

  // Final decision: agar patient pehle join kar chuka hai aur
  // consultation abhi InProgress hai → rejoin hamesha allowed
  // (koi window nahi). Warna sirf window ke andar.
  bool get _canJoinNow {
    if (_isInProgress && _hasJoinedBefore) return true;
    return _isWithinJoinWindow;
  }

  // ── APNI DETAILS (Doctor wali file jaisi hi honi chahiye) ──
  static const String _jaasAppId =
      'vpaas-magic-cookie-b97ea521398a41ffbf90f00437e433a7';
  static const String _tokenServerUrl = 'https://jitsi-jwt-server-3.bonto.run';

  String get _roomName => 'FamilyWellCare-${widget.appointmentId}';

  // Free server so jata hai, pehli request par late jagta hai.
  void _wakeUpTokenServer() {
    http
        .get(Uri.parse(_tokenServerUrl))
        .timeout(const Duration(seconds: 30))
        .catchError((_) => http.Response('', 500));
  }

  // Token 3 dafa try karta hai, har dafa 20 second wait karta hai.
  Future<String?> _fetchToken() async {
    final patientEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final uri = Uri.parse(
      '$_tokenServerUrl/token?room=$_roomName&name=$_doctorName-Patient&email=$patientEmail&moderator=false',
    );
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['token'] as String;
        }
      } catch (_) {}
      if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<void> _joinCall() async {
    setState(() => _isJoining = true);
    try {
      final token = await _fetchToken();

      // Token na mile to meet.jit.si par NAHI bhejna — wahan
      // "moderator not set" aata hai.
      if (token == null) {
        _showError(
            'Video server is starting. Please wait a moment and tap Join again.');
        return;
      }

      // patientJoinedAt set karo — yeh "join hua" ka proxy hai
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .update({'patientJoinedAt': FieldValue.serverTimestamp()});

      final roomUrl = 'https://8x8.vc/$_jaasAppId/$_roomName?jwt=$token';

      final uri = Uri.parse(roomUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!launched && mounted) {
        _showError('Could not open video call. Please try again.');
      }
    } catch (e) {
      _showError('Error joining call: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _buildJoinSection() {
    if (!_isVideoCall) return const SizedBox.shrink();

    final status = _appt?['status'];
    final ended =
        status == 'NoShow' || status == 'Cancelled' || status == 'Completed';

    // Session khatam, ya abhi Requested (payment verify baaki)
    if (ended || status == 'Requested') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _sectionLabel('VIDEO CONSULTATION'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam_outlined,
                    color: AppColors.faint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ended
                        ? 'This video session has ended.'
                        : 'Waiting for payment/booking confirmation.',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Confirmed YA InProgress — same 5-min window logic
    final canJoin = _canJoinNow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        _sectionLabel('VIDEO CONSULTATION'),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed: (_isJoining || !canJoin) ? null : _joinCall,
            icon: _isJoining
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Icon(Icons.videocam_rounded,
                    color: canJoin ? AppColors.mint : AppColors.faint),
            label: Text(
              canJoin ? 'Join Video Call' : 'Available 5 min before slot time',
              style: TextStyle(
                color: canJoin ? Colors.white : AppColors.faint,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              disabledBackgroundColor: const Color(0xFFE6ECEC),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (canJoin) ...[
          const SizedBox(height: 8),
          Text(
            status == 'InProgress'
                ? 'The doctor is ready for your consultation.'
                : 'You can join now — the doctor will join shortly.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.teal),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.muted));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal))
          : _appt == null
              ? const Center(child: Text('Appointment not found'))
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDoctorCard(),
                            const SizedBox(height: 12),
                            _buildInfoRow(),
                            _buildJoinSection(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    final type = _appt?['appointmentType'] ?? '';
    return AppHeader(
      title: 'Appointment Detail',
      subtitle: type == 'VIDEO_CALL'
          ? 'Video consult'
          : type == 'WALK_IN'
              ? 'Walk-in'
              : 'In-clinic visit',
    );
  }

  Map<String, Color> _statusColors(String status) {
    switch (status) {
      case 'Confirmed':
        return {'bg': const Color(0xFFDDF3EE), 'text': const Color(0xFF0B5E57)};
      case 'Completed':
        return {'bg': AppColors.blueSoft, 'text': AppColors.blue};
      case 'Requested':
        return {'bg': const Color(0xFFF6F2E2), 'text': const Color(0xFF8A6D00)};
      case 'Cancelled':
        return {'bg': const Color(0xFFFBE6E0), 'text': const Color(0xFF9A2E16)};
      case 'InProgress':
        return {'bg': const Color(0xFFEEE8FB), 'text': const Color(0xFF5B3FA8)};
      default:
        return {'bg': const Color(0xFFEEF1F1), 'text': AppColors.muted};
    }
  }

  Widget _buildDoctorCard() {
    final type = _appt?['appointmentType'] ?? '';
    final typeLabel = type == 'VIDEO_CALL'
        ? 'Video consult'
        : type == 'WALK_IN'
            ? 'Walk-in'
            : 'In-clinic visit';
    final String status = '${_appt?['status'] ?? '—'}';
    final sc = _statusColors(status);

    return Container(
      width: double.infinity,
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
              _doctorName.isNotEmpty ? _doctorName[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w800,
                  fontSize: 19),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_doctorName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text(typeLabel,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          AppStatusChip(
            label: status,
            colors: AppChipColors(sc['text']!, sc['bg']!),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    return Row(
      children: [
        Expanded(
            child: _infoTile(
                Icons.calendar_today_outlined, 'Date', _slot?['date'] ?? '—')),
        const SizedBox(width: 8),
        Expanded(
            child: _infoTile(
                Icons.access_time, 'Time', _slot?['startTime'] ?? '—')),
        const SizedBox(width: 8),
        Expanded(
            child: _infoTile(
                Icons.info_outline, 'Status', _appt?['status'] ?? '—')),
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
