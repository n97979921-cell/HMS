import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  bool _isJoining = false;
  Map<String, dynamic>? _appt;
  Map<String, dynamic>? _slot;
  String _doctorName = '';

  @override
  void initState() {
    super.initState();
    _load();
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

  // Slot-time se 5 min pehle se allow
  bool get _isWithinJoinWindow {
    if (_slot == null) return false;
    try {
      final date = DateTime.parse(_slot!['date']);
      final timeParts = (_slot!['startTime'] as String).split(':');
      final slotDt = DateTime(date.year, date.month, date.day,
          int.parse(timeParts[0]), int.parse(timeParts[1]));
      final windowStart = slotDt.subtract(const Duration(minutes: 5));
      return DateTime.now().isAfter(windowStart);
    } catch (_) {
      return false;
    }
  }

  String get _roomUrl =>
      'https://meet.jit.si/FamilyWellCare-${widget.appointmentId}';

  Future<void> _joinCall() async {
    setState(() => _isJoining = true);
    try {
      // patientJoinedAt set karo — yeh "join hua" ka proxy hai
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .update({'patientJoinedAt': FieldValue.serverTimestamp()});

      final uri = Uri.parse(_roomUrl);
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
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _buildJoinSection() {
    if (!_isVideoCall) return const SizedBox.shrink();

    if (!_isInProgress) {
      // Session khatam ho chuki (NoShow/Cancelled) ya abhi shuru nahi hui
      final status = _appt?['status'];
      final ended =
          status == 'NoShow' || status == 'Cancelled' || status == 'Completed';
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey.shade600, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ended
                    ? 'This video session has ended.'
                    : 'Waiting for the doctor to start the consultation.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );
    }

    // InProgress — doctor ready hai
    final canJoin = _isWithinJoinWindow;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: (_isJoining || !canJoin) ? null : _joinCall,
            icon: _isJoining
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.videocam, color: Colors.white),
            label: Text(
              canJoin ? 'Join Video Call' : 'Available 5 min before slot time',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              disabledBackgroundColor: Colors.grey.shade400,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
          if (canJoin) ...[
            const SizedBox(height: 8),
            const Text('The doctor is ready for your consultation.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : _appt == null
                ? const Center(child: Text('Appointment not found'))
                : Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDoctorCard(),
                              const SizedBox(height: 16),
                              _buildInfoRow(),
                              _buildJoinSection(),
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
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primaryDark],
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
          const Text('Appointment Detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDoctorCard() {
    final type = _appt?['appointmentType'] ?? '';
    final typeLabel = type == 'VIDEO_CALL'
        ? 'Video consult'
        : type == 'WALK_IN'
            ? 'Walk-in'
            : 'In-clinic visit';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
            backgroundColor: _primary.withValues(alpha: 0.15),
            child: Text(
              _doctorName.isNotEmpty ? _doctorName[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: _primary, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_doctorName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(typeLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
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
        const SizedBox(width: 12),
        Expanded(
            child: _infoTile(
                Icons.access_time, 'Time', _slot?['startTime'] ?? '—')),
        const SizedBox(width: 12),
        Expanded(
            child: _infoTile(
                Icons.info_outline, 'Status', _appt?['status'] ?? '—')),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Icon(icon, size: 18, color: _primary),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
