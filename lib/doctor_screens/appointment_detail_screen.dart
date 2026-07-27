// lib/doctor_screens/appointment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'doctor_repository.dart';
import 'add_prescription_screen.dart';
import 'patient_profile_view_screen.dart';
import 'request_lab_test_screen.dart';

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

  /// Human-readable date label for this appointment (e.g. "20 Jul 2026").
  /// Passed in from the Home screen's currently selected date, since the
  /// list item itself only carries the slot time, not the full date.
  final String dateLabel;

  const AppointmentDetailScreen({
    super.key,
    required this.repository,
    required this.doctorId,
    required this.appointment,
    required this.dateLabel,
  });

  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  late AppointmentStatus _currentStatus;
  late bool _admissionRecommended;
  bool _isStarting = false;
  bool _isCompleting = false;
  bool _isTogglingAdmission = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.appointment.status;
    _admissionRecommended = widget.appointment.admissionRecommended;
  }

  bool get _isVideoCall =>
      widget.appointment.appointmentType == AppointmentType.videoCall;

  bool get _isCompleted => _currentStatus == AppointmentStatus.completed;
  bool get _isConfirmed => _currentStatus == AppointmentStatus.confirmed;
  bool get _isInProgress => _currentStatus == AppointmentStatus.inProgress;

  /// True once the doctor has actually met/is meeting the patient
  /// (Confirmed, InProgress, or Completed) — as opposed to a pending
  /// Requested appointment, or one that was Cancelled/NoShow. Lab test
  /// requests and admission recommendations only make sense at this point.
  bool get _visitIsActiveOrDone =>
      _currentStatus == AppointmentStatus.confirmed ||
      _currentStatus == AppointmentStatus.inProgress ||
      _currentStatus == AppointmentStatus.completed;

  /// Builds a stable Jitsi Meet room name from the appointment ID, so the
  /// same room is reused if the doctor or patient rejoins later, but it's
  /// unique per appointment. Uses the free public meet.jit.si server —
  /// no account, API key, or extra backend setup required.
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

  /// Doctor.startVideoConsultation() — per the schema's video call rule,
  /// pressing this moves the appointment Confirmed → InProgress and records
  /// consultationStartedAt, then opens the Jitsi room.
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

  Future<void> _markCompleted() async {
    // Schema rule: "VIDEO_CALL: Doctor marks completed" — IN_PERSON and
    // WALK_IN appointments are completed by the Receptionist instead, so
    // this should never be reachable for those types (UI also hides the
    // button), but we guard here too in case this is ever called elsewhere.
    if (!_isVideoCall) return;

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
        // Let the Home screen know it should refresh its list.
        Navigator.pop(context, true);
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

  /// Implements the schema's appointment lifecycle for the doctor's view:
  ///
  /// VIDEO_CALL: Requested → Confirmed → [Start Consultation] → InProgress
  ///             → [Mark Completed] → Completed → [Add Prescription]
  ///   ("VIDEO_CALL: Doctor marks completed")
  ///
  /// IN_PERSON / WALK_IN: the Receptionist marks these completed, not the
  /// doctor — so no completion button is shown here for those types; once
  /// completed, the doctor can still add a prescription.
  Widget _buildActionSection() {
    if (_isCompleted) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _DetailColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: _DetailColors.primary, size: 18),
                SizedBox(width: 8),
                Text(
                  'Visit completed',
                  style: TextStyle(
                    color: _DetailColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openAddPrescription,
              icon: const Icon(Icons.receipt_long_outlined, color: Colors.white),
              label: const Text(
                'Add Prescription',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _DetailColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!_isVideoCall) {
      // IN_PERSON / WALK_IN — doctor has no completion action here.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: _DetailColors.textMuted.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: _DetailColors.textMuted, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'This appointment will be marked completed by the receptionist.',
                style: TextStyle(color: _DetailColors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    // VIDEO_CALL, not yet completed:
    if (_isConfirmed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isStarting ? null : _startConsultation,
          icon: _isStarting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.videocam, color: Colors.white),
          label: const Text(
            'Start Consultation',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _DetailColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
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
              label: const Text(
                'Rejoin Video Consultation',
                style: TextStyle(color: _DetailColors.primary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _DetailColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
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
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline, color: Colors.white),
              label: const Text(
                'Mark Completed',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _DetailColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Requested / Cancelled / NoShow — no doctor action applicable.
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
      if (mounted) setState(() => _isTogglingAdmission = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _admissionRecommended = previous; // revert on failure
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

  void _openAddPrescription() {
    Navigator.push(
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
                  _buildInfoRow(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openPatientProfile,
                      icon: const Icon(Icons.person_search_outlined, color: _DetailColors.primary),
                      label: const Text(
                        'View Patient Profile',
                        style: TextStyle(color: _DetailColors.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _DetailColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  if (_visitIsActiveOrDone) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: _DetailColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _admissionRecommended,
                        onChanged: _isTogglingAdmission ? null : _toggleAdmissionRecommendation,
                        activeColor: _DetailColors.primary,
                        title: const Text(
                          'Recommend Admission',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Flags this patient for receptionist to assign a room/bed',
                          style: TextStyle(fontSize: 11, color: _DetailColors.textMuted),
                        ),
                      ),
                    ),
                    if (!_isVideoCall) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openRequestLabTest,
                          icon: const Icon(Icons.science_outlined, color: _DetailColors.primary),
                          label: const Text(
                            'Request Lab Test',
                            style: TextStyle(color: _DetailColors.primary),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _DetailColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
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
            onPressed: () => Navigator.pop(context, _isCompleted),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Text(
            'Appointment Detail',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _DetailColors.primary.withOpacity(0.15),
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
                      color: _DetailColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      appointment.appointmentType.label,
                      style: const TextStyle(
                          fontSize: 12, color: _DetailColors.textMuted),
                    ),
                  ],
                ),
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
        Expanded(child: _infoTile(Icons.calendar_today_outlined, 'Date', widget.dateLabel)),
        const SizedBox(width: 12),
        Expanded(child: _infoTile(Icons.access_time, 'Time', widget.appointment.slotTime)),
        const SizedBox(width: 12),
        Expanded(
            child: _infoTile(Icons.info_outline, 'Status', _currentStatus.name)),
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: _DetailColors.primary),
          const SizedBox(height: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: _DetailColors.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}