import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import 'package:flutter/services.dart';
import 'appointments_today_screen.dart';
import 'receptionist_profile_screen.dart';
import '../widgets/app_ui.dart';

/// WALK-IN PATIENT SCREEN (Receptionist) — Phase 3
///
/// 3 stages ek screen par:
///  1. SEARCH   — CNIC ya phone se patient dhoondo (duplicate na bane)
///  2. REGISTER — na mile to naya walk-in patient banao (email NAHI)
///  3. BOOK     — doctor select → sirf AAJ ke available slots → cash →
///                appointment: Confirmed | slot: BOOKED | payment: Paid(Cash)
///
/// Lifecycle rules:
///  - Walk-in sirf AAJ ke slots par book hota hai (door-future nahi)
///  - "Booked" = cash li ja chuki (payment record Paid/Cash foran banta hai)
///  - Baad me appointment time par check-in na ho → HalfRefunded (Phase 4)
///
///  UI-ONLY CHANGE: Ab dashboard jaisi hi bottom nav bar add ki hai
/// (Home / Appointments / Walk-in / Profile) — "Walk-in" tab hamesha
/// highlighted rehta hai jab is screen par hon. Search/Register/Book
/// ka koi logic nahi chhua.
///
/// UI-ONLY CHANGE: Confirm walk-in booking dialog mein "Back" button
/// ab "Cash received — Book" jaisa hi oval/pill-shaped outlined button
/// hai (pehle plain TextButton tha) — koi logic nahi badla.
// CNIC ko type karte waqt auto-format karta hai: 12345-1234567-1
class _CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 13) digits = digits.substring(0, 13);

    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 5 || i == 12) formatted += '-';
      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// CNIC valid hai ya nahi — dashes hata kar sirf digits count karo
bool _isValidCnic(String value) {
  final digits = value.replaceAll('-', '');
  return RegExp(r'^\d{13}$').hasMatch(digits);
}

class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key});

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  // ── Stage control ──
  int _stage = 0; // 0=search, 1=register, 2=book

  // ── Stage 0: search ──
  final _searchController = TextEditingController();
  bool _isSearching = false;

  // ── Selected/created patient ──
  String? _patientId;
  String _patientName = '';

  // ── Stage 1: register form ──
  final _regFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cnicController = TextEditingController();
  final _ageController = TextEditingController();
  String _gender = 'Male';
  bool _isRegistering = false;

  // ── Stage 2: booking ──
  bool _isLoadingDoctors = false;
  List<Map<String, dynamic>> _doctors = [];
  Map<String, dynamic>? _selectedDoctor;
  bool _isLoadingSlots = false;
  List<String> _availableTimes = [];
  String? _selectedTime;
  bool _isBooking = false;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _cnicController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  String _todayStr() {
    final t = DateTime.now();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  // ════════ STAGE 0: SEARCH ════════
  Future<void> _searchPatient() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showError('Enter CNIC');
      return;
    }
    if (!_isValidCnic(query)) {
      _showError('Enter a valid 13-digit CNIC (e.g. 12345-1234567-1)');
      return;
    }
    setState(() => _isSearching = true);
    try {
      // Sirf CNIC se check (schema rule)
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .where('cnic', isEqualTo: query)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        setState(() {
          _patientId = snap.docs.first.id;
          _patientName = data['name'] ?? 'Patient';
          _stage = 2; // seedha booking par
        });
        _loadDoctors();
        _showSuccess('Patient found: $_patientName');
      } else {
        // Nahi mila → register stage, CNIC pre-fill
        setState(() {
          _cnicController.text = query;
          _stage = 1;
        });
      }
    } catch (e) {
      _showError('Search error: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ════════ STAGE 1: REGISTER ════════
  Future<void> _registerPatient() async {
    if (!_regFormKey.currentState!.validate()) return;
    setState(() => _isRegistering = true);
    try {
      // Duplicate CNIC double-check (race se bachao)
      final dup = await FirebaseFirestore.instance
          .collection('users')
          .where('cnic', isEqualTo: _cnicController.text.trim())
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty) {
        final data = dup.docs.first.data();
        setState(() {
          _patientId = dup.docs.first.id;
          _patientName = data['name'] ?? 'Patient';
          _stage = 2;
        });
        _loadDoctors();
        _showSuccess('Patient already exists: $_patientName — using record');
        return;
      }

      // Walk-in patient: Firebase Auth NAHI — sirf Firestore doc
      final userRef = FirebaseFirestore.instance.collection('users').doc();
      final uid = userRef.id;

      final batch = FirebaseFirestore.instance.batch();
      batch.set(userRef, {
        'uid': uid,
        'email': null, // walk-in ka email nahi hota
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'cnic': _cnicController.text.trim(),
        'role': 'patient',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid, // receptionist
      });
      batch.set(
          FirebaseFirestore.instance.collection('patient_profiles').doc(uid), {
        'patientId': uid,
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'gender': _gender,
        'bloodGroup': null,
        'allergies': null,
        'chronicConditions': null,
        'patientType': 'WALK_IN',
      });
      await batch.commit();

      setState(() {
        _patientId = uid;
        _patientName = _nameController.text.trim();
        _stage = 2;
      });
      _loadDoctors();
      _showSuccess('Patient registered');
    } catch (e) {
      _showError('Registration error: $e');
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  // ════════ STAGE 2: BOOK ════════
  Future<void> _loadDoctors() async {
    setState(() => _isLoadingDoctors = true);
    try {
      final settingsSnap =
          await FirebaseFirestore.instance.collection('doctor_settings').get();

      final List<Map<String, dynamic>> result = [];
      for (final doc in settingsSnap.docs) {
        final doctorId = doc.id;
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(doctorId)
            .get();
        if (!userDoc.exists || userDoc.data()?['status'] != 'active') continue;

        final profileDoc = await FirebaseFirestore.instance
            .collection('doctor_profiles')
            .doc(doctorId)
            .get();

        // In-person fee
        num fee = 0;
        final deptId = profileDoc.data()?['departmentId'] ?? '';

        final feeDoc = await FirebaseFirestore.instance
            .collection('doctor_consultation_fees')
            .doc(doctorId)
            .get();
        fee = feeDoc.data()?['inPersonFee'] ?? 0;

        if (fee == 0) continue; // fee set nahi → skip (patient side jaisa rule)

        result.add({
          'doctorId': doctorId,
          'name': userDoc.data()?['name'] ?? 'Doctor',
          'specialization': profileDoc.data()?['specialization'] ?? '',
          'departmentId': deptId,
          'fee': fee,
          'startTime': doc.data()['appointmentStartTime'],
          'endTime': doc.data()['appointmentEndTime'],
        });
      }

      setState(() {
        _doctors = result;
        _isLoadingDoctors = false;
      });
    } catch (e) {
      setState(() => _isLoadingDoctors = false);
      _showError('Error loading doctors: $e');
    }
  }

  Future<void> _loadTodaySlots() async {
    if (_selectedDoctor == null) return;
    setState(() {
      _isLoadingSlots = true;
      _selectedTime = null;
      _availableTimes = [];
    });
    try {
      final doctorId = _selectedDoctor!['doctorId'];
      final dateStr = _todayStr();

      // Doctor ke saare times generate karo (15-min)
      final allTimes = _generateTimes(
          _selectedDoctor!['startTime'], _selectedDoctor!['endTime']);

      // Aaj ke HELD/BOOKED slots
      final slotsSnap = await FirebaseFirestore.instance
          .collection('slots')
          .where('doctorId', isEqualTo: doctorId)
          .where('date', isEqualTo: dateStr)
          .get();

      final Set<String> taken = {};
      for (final doc in slotsSnap.docs) {
        final status = doc.data()['slotStatus'];
        if (status == 'HELD' || status == 'BOOKED') {
          taken.add(doc.data()['startTime']);
        }
      }

      // Available = sab − taken − guzre hue times
      final now = DateTime.now();
      // Weekend (Sat/Sun) par koi slot nahi — patient booking jaisa rule
      final isWeekend =
          now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
      final available = isWeekend
          ? <String>[]
          : allTimes.where((t) {
              if (taken.contains(t)) return false;
              final parts = t.split(':').map(int.parse).toList();
              final slotDt =
                  DateTime(now.year, now.month, now.day, parts[0], parts[1]);
              return slotDt.isAfter(now);
            }).toList();

      setState(() {
        _availableTimes = available;
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => _isLoadingSlots = false);
      _showError('Error loading slots: $e');
    }
  }

  List<String> _generateTimes(String start, String end) {
    final s = start.split(':').map(int.parse).toList();
    final e = end.split(':').map(int.parse).toList();
    DateTime cursor = DateTime(2000, 1, 1, s[0], s[1]);
    final endT = DateTime(2000, 1, 1, e[0], e[1]);
    final List<String> times = [];
    while (cursor.isBefore(endT)) {
      times.add(
          '${cursor.hour.toString().padLeft(2, '0')}:${cursor.minute.toString().padLeft(2, '0')}');
      cursor = cursor.add(const Duration(minutes: 15));
    }
    return times;
  }

  // Book: cash confirm → transaction (appointment+slot+payment)
  Future<void> _bookWalkIn() async {
    if (_selectedTime == null) {
      _showError('Select a time slot');
      return;
    }
    final doctor = _selectedDoctor!;
    final fee = doctor['fee'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Confirm walk-in booking',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
        content: Text(
            'Patient: $_patientName\n'
            'Doctor: ${doctor['name']}\n'
            'Today at $_selectedTime\n\n'
            'Cash received: Rs. $fee?',
            style: const TextStyle(
                fontSize: 14, height: 1.5, color: AppColors.muted)),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.header,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const FittedBox(
                    child: Text('Cash received — Book',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isBooking = true);
    final dateStr = _todayStr();
    final timeKey = _selectedTime!.replaceAll(':', '');
    final slotId = '${doctor['doctorId']}_${dateStr}_$timeKey';

    final slotRef = FirebaseFirestore.instance.collection('slots').doc(slotId);
    final apptRef = FirebaseFirestore.instance.collection('appointments').doc();
    final paymentRef = FirebaseFirestore.instance.collection('payments').doc();

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // READ: slot taken to nahi (race se bachao)
        final slotSnap = await transaction.get(slotRef);
        if (slotSnap.exists) {
          final status = slotSnap.data()?['slotStatus'];
          if (status == 'HELD' || status == 'BOOKED') {
            throw Exception('Slot just taken. Pick another.');
          }
        }

        final allTimes = _generateTimes(doctor['startTime'], doctor['endTime']);
        final idx = allTimes.indexOf(_selectedTime!);
        final slotEnd =
            idx + 1 < allTimes.length ? allTimes[idx + 1] : doctor['endTime'];

        // WRITES: appointment Confirmed + slot BOOKED + payment Paid(Cash)
        transaction.set(apptRef, {
          'appointmentId': apptRef.id,
          'patientId': _patientId,
          'doctorId': doctor['doctorId'],
          'departmentId': doctor['departmentId'],
          'slotId': slotId,
          'status': 'Confirmed', // cash mili = confirmed
          'consultationFee': fee,
          'symptoms': null,
          'patientReportUrl': null,
          'appointmentType': 'WALK_IN',
          'admissionRecommended': false,
          'consultationStartedAt': null,
          'checkedInAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(slotRef, {
          'slotId': slotId,
          'doctorId': doctor['doctorId'],
          'date': dateStr,
          'startTime': _selectedTime,
          'endTime': slotEnd,
          'slotStatus': 'BOOKED', // seedha booked (HELD skip)
          'heldByAppointmentId': null,
          'heldAt': null,
          'appointmentId': apptRef.id,
        });

        transaction.set(paymentRef, {
          'paymentId': paymentRef.id,
          'appointmentId': apptRef.id,
          'patientId': _patientId,
          'type': 'Consultation',
          'amount': fee,
          'paymentMethod': 'Cash',
          'status': 'Paid', // cash foran
          'referenceId': null,
          'transactionId': null,
          'screenshotBase64': null,
          'refundAmount': null,
          'refundPaid': false,
          'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'paidAt': FieldValue.serverTimestamp(),
        });
      });

      // ── NOTIFICATION: Walk-in Booked → Doctor only ──
      // Walk-in patient ke paas app nahi (email null), isliye Patient
      // ko koi notification NAHI jaati — sirf Doctor ko.
      await NotificationService.send(
        userId: doctor['doctorId'] ?? '',
        type: 'Appointment',
        referenceId: apptRef.id,
        message: 'A walk-in patient ($_patientName) has been booked '
            'for today at $_selectedTime.',
      );

      if (!mounted) return;
      _showSuccess('Walk-in booked — today $_selectedTime');
      Navigator.pop(context);
    } catch (e) {
      _showError('Booking failed: $e');
      _loadTodaySlots(); // refresh
    } finally {
      if (mounted) setState(() => _isBooking = false);
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

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ════════ UI ════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: _stage == 0
                  ? _buildSearchStage()
                  : _stage == 1
                      ? _buildRegisterStage()
                      : _buildBookStage(),
            ),
          ),
        ],
      ),
      // ── Dashboard jaisi bottom nav bar — "Walk-in" tab selected.
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    const labels = ['Find', 'Register', 'Book'];
    return AppHeader(
      title: _stage == 0
          ? 'Walk-in: Find Patient'
          : _stage == 1
              ? 'Walk-in: Register'
              : 'Walk-in: Book (Today)',
      subtitle: 'Walk-in patient',
      onBack: () {
        if (_stage == 0) {
          Navigator.pop(context);
        } else {
          setState(() => _stage =
              _stage == 2 && _patientId != null && _nameController.text.isEmpty
                  ? 0
                  : _stage - 1);
        }
      },
      bottom: Row(
        children: List.generate(3, (i) {
          final done = i <= _stage;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: done
                          ? AppColors.mint
                          : Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: done ? Colors.white : AppColors.headerLabel,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _stageTitle(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
        const SizedBox(height: 3),
        Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      ],
    );
  }

  Widget _primaryButton(
      {required String label,
      required bool busy,
      required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.header,
          disabledBackgroundColor: AppColors.header.withOpacity(0.6),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.faint, fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.teal, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      border: b(AppColors.border),
      enabledBorder: b(AppColors.border),
      focusedBorder: b(AppColors.teal),
      errorBorder: b(const Color(0xFFE2A090)),
      focusedErrorBorder: b(AppColors.danger),
    );
  }

  // ── Stage 0 UI ──
  Widget _buildSearchStage() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stageTitle('Search by CNIC',
              'Search first to avoid duplicate patient records.'),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            keyboardType: TextInputType.number,
            inputFormatters: [_CnicInputFormatter()],
            decoration: _fieldDecoration(
                'CNIC (e.g. 12345-1234567-1)', Icons.search_rounded),
          ),
          const SizedBox(height: 14),
          _primaryButton(
            label: 'Search Patient',
            busy: _isSearching,
            onPressed: _isSearching ? null : _searchPatient,
          ),
        ],
      ),
    );
  }

  // ── Stage 1 UI ──
  Widget _buildRegisterStage() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _regFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stageTitle('New walk-in patient', 'No Email Required'),
            const SizedBox(height: 14),
            _regField(_nameController, 'Full name', Icons.person_outline,
                validator: (v) => v!.trim().isEmpty ? 'Name required' : null),
            const SizedBox(height: 12),
            _regField(_phoneController, 'Phone', Icons.phone_outlined,
                keyboardType: TextInputType.phone, validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Phone required';
              if (!RegExp(r'^03\d{9}$').hasMatch(v.trim())) {
                return 'Enter valid Pakistani number (03XXXXXXXXX)';
              }
              return null;
            }),
            const SizedBox(height: 12),
            _regField(_cnicController, 'CNIC (e.g. 12345-1234567-1)',
                Icons.badge_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [_CnicInputFormatter()], validator: (v) {
              if (v == null || v.trim().isEmpty) return 'CNIC required';
              if (!_isValidCnic(v.trim())) {
                return 'Enter a valid 13-digit CNIC';
              }
              return null;
            }),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _gender,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _gender = v!),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _primaryButton(
              label: 'Register & Continue',
              busy: _isRegistering,
              onPressed: _isRegistering ? null : _registerPatient,
            ),
          ],
        ),
      ),
    );
  }

  Widget _regField(TextEditingController controller, String hint, IconData icon,
      {TextInputType? keyboardType,
      String? Function(String?)? validator,
      List<TextInputFormatter>? inputFormatters}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      decoration: _fieldDecoration(hint, icon),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: AppColors.muted,
      ),
    );
  }

  // ── Stage 2 UI ──
  Widget _buildBookStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Patient chip
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.tealSoft,
                child: Text(
                  _patientName.isNotEmpty ? _patientName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.teal, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Patient',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                    Text('$_patientName',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionLabel('Select doctor'),
        const SizedBox(height: 10),
        _isLoadingDoctors
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: AppColors.teal),
                ),
              )
            : _doctors.isEmpty
                ? const Text('No doctors available',
                    style: TextStyle(color: AppColors.faint))
                : Column(
                    children: _doctors.map((d) {
                      final isSel =
                          _selectedDoctor?['doctorId'] == d['doctorId'];
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedDoctor = d);
                          _loadTodaySlots();
                        },
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.header : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['name'],
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: isSel
                                                ? Colors.white
                                                : AppColors.text)),
                                    const SizedBox(height: 2),
                                    Text(d['specialization'],
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isSel
                                                ? AppColors.headerMuted
                                                : AppColors.muted)),
                                  ],
                                ),
                              ),
                              Text('Rs. ${d['fee']}',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: isSel
                                          ? AppColors.mint
                                          : AppColors.teal)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
        if (_selectedDoctor != null) ...[
          const SizedBox(height: 8),
          _sectionLabel("Today's available slots"),
          const SizedBox(height: 10),
          _isLoadingSlots
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppColors.teal),
                  ),
                )
              : _availableTimes.isEmpty
                  ? Text(
                      (DateTime.now().weekday == DateTime.saturday ||
                              DateTime.now().weekday == DateTime.sunday)
                          ? 'No slots on weekends (Saturday / Sunday)'
                          : 'No slots left today',
                      style: const TextStyle(color: AppColors.faint))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableTimes.map((t) {
                        final isSel = t == _selectedTime;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedTime = t),
                          child: Container(
                            width: 76,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.mint : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isSel
                                      ? AppColors.mint
                                      : AppColors.border),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: isSel
                                        ? AppColors.header
                                        : AppColors.text)),
                          ),
                        );
                      }).toList(),
                    ),
          const SizedBox(height: 20),
          _primaryButton(
            label: _selectedDoctor == null
                ? 'Book'
                : 'Collect Rs. ${_selectedDoctor!['fee']} & Book',
            busy: _isBooking,
            onPressed: _isBooking ? null : _bookWalkIn,
          ),
        ],
      ],
    );
  }

  // ── Bottom nav — dashboard jaisi hi. "Walk-in" is screen par
  // hamesha selected hai (currentIndex: 2). Home = wapis dashboard
  // (pop), Appointments/Profile = navigate, Walk-in tap = no-op
  // (already yahan hain).
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Colors.white,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        currentIndex: 2,
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
          if (index == 2) return; // already on Walk-in

          if (index == 0) {
            // Dashboard seedha neeche stack mein hai (yahan se push hua
            // tha), is liye pop hi Home par wapis le jata hai.
            Navigator.pop(context);
            return;
          }
          if (index == 1) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppointmentsTodayScreen(),
              ),
            );
          } else if (index == 3) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReceptionistProfileScreen(),
              ),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.event_note_outlined),
              activeIcon: Icon(Icons.event_note_rounded),
              label: 'Appointments'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_add_alt_1_outlined),
              activeIcon: Icon(Icons.person_add_alt_1_rounded),
              label: 'Walk-in'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile'),
        ],
      ),
    );
  }
}
