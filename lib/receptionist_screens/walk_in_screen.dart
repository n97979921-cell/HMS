import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key});

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

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
        if (deptId != '') {
          final feeDoc = await FirebaseFirestore.instance
              .collection('department_consultation_fees')
              .doc(deptId)
              .get();
          fee = feeDoc.data()?['inPersonFee'] ?? 0;
        }
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
      final available = allTimes.where((t) {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm walk-in booking'),
        content: Text('Patient: $_patientName\n'
            'Doctor: ${doctor['name']}\n'
            'Today at $_selectedTime\n\n'
            'Cash received: Rs. $fee?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Cash received — Book',
                style: TextStyle(color: Colors.white)),
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
      backgroundColor: _primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ════════ UI ════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: _stage == 0
                    ? _buildSearchStage()
                    : _stage == 1
                        ? _buildRegisterStage()
                        : _buildBookStage(),
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
            onTap: () {
              if (_stage == 0) {
                Navigator.pop(context);
              } else {
                setState(() => _stage = _stage == 2 &&
                        _patientId != null &&
                        _nameController.text.isEmpty
                    ? 0
                    : _stage - 1);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            _stage == 0
                ? 'Walk-in: Find Patient'
                : _stage == 1
                    ? 'Walk-in: Register'
                    : 'Walk-in: Book (Today)',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ── Stage 0 UI ──
  Widget _buildSearchStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Search by CNIC',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A))),
        const SizedBox(height: 4),
        const Text('Pehle dhoondo — duplicate patient na bane.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'CNIC (e.g. 3520212345671)',
            prefixIcon: const Icon(Icons.search, color: _primary),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSearching ? null : _searchPatient,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSearching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Search Patient',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── Stage 1 UI ──
  Widget _buildRegisterStage() {
    return Form(
      key: _regFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New walk-in patient',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 4),
          const Text('No Email Required',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 14),
          _regField(_nameController, 'Full name', Icons.person_outline,
              validator: (v) => v!.trim().isEmpty ? 'Name required' : null),
          const SizedBox(height: 12),
          _regField(_phoneController, 'Phone', Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) => v!.trim().isEmpty ? 'Phone required' : null),
          const SizedBox(height: 12),
          _regField(_cnicController, 'CNIC', Icons.badge_outlined,
              keyboardType: TextInputType.number,
              validator: (v) => v!.trim().isEmpty ? 'CNIC required' : null),
          const SizedBox(height: 12),
          _regField(_ageController, 'Age', Icons.cake_outlined,
              keyboardType: TextInputType.number, validator: (v) {
            final age = int.tryParse(v!.trim());
            if (age == null || age <= 0 || age > 120) return 'Valid age';
            return null;
          }),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _gender,
                isExpanded: true,
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isRegistering ? null : _registerPatient,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isRegistering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Register & Continue',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _regField(TextEditingController controller, String hint, IconData icon,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: _primary, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ── Stage 2 UI ──
  Widget _buildBookStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Patient chip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.person, color: _primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Patient: $_patientName',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF1A2F3A))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Select doctor',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A))),
        const SizedBox(height: 10),
        _isLoadingDoctors
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: _primary),
                ),
              )
            : _doctors.isEmpty
                ? const Text('No doctors available',
                    style: TextStyle(color: Colors.grey))
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
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSel ? _primary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['name'],
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isSel
                                                ? Colors.white
                                                : const Color(0xFF1A2F3A))),
                                    Text(d['specialization'],
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isSel
                                                ? Colors.white70
                                                : Colors.black54)),
                                  ],
                                ),
                              ),
                              Text('Rs. ${d['fee']}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSel ? Colors.white : _primary)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
        if (_selectedDoctor != null) ...[
          const SizedBox(height: 16),
          const Text("Today's available slots",
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 10),
          _isLoadingSlots
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: _primary),
                  ),
                )
              : _availableTimes.isEmpty
                  ? const Text('No slots left today',
                      style: TextStyle(color: Colors.grey))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableTimes.map((t) {
                        final isSel = t == _selectedTime;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedTime = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? _primary : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isSel
                                        ? Colors.white
                                        : const Color(0xFF1A2F3A))),
                          ),
                        );
                      }).toList(),
                    ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBooking ? null : _bookWalkIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isBooking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(
                      _selectedDoctor == null
                          ? 'Book'
                          : 'Collect Rs. ${_selectedDoctor!['fee']} & Book',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }
}
