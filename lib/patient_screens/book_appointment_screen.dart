import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'payment_upload_screen.dart';

/// FIXES IS FILE MEIN:
/// 1. Past-time slots: aaj ki date par guzre hue times ab disabled hain
///    (pehle 3 baje bhi subah 9:00 ka slot book ho sakta tha)
/// 2. Live fee: checkout bar ab Firestore se load ki hui LIVE fee
///    dikhata hai (pehle purani widget.consultationFee dikhti thi,
///    lekin transaction naya rate charge karti thi — mismatch)
class BookAppointmentScreen extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final String specialization;
  final String appointmentType; // 'IN_PERSON' | 'VIDEO_CALL'
  final num consultationFee;
  final String departmentId;

  const BookAppointmentScreen({
    super.key,
    required this.doctorId,
    required this.doctorName,
    required this.specialization,
    required this.appointmentType,
    required this.consultationFee,
    required this.departmentId,
  });

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoadingSettings = true;
  bool _isLoadingSlots = false;
  bool _isBooking = false;

  String? _startTime; // "09:00"
  String? _endTime; // "17:00"

  // FIX 2: live fee — screen khulte hi Firestore se load hoti hai
  num? _displayFee;

  List<DateTime> _weekdays = [];
  int _selectedDateIndex = 0;

  List<String> _allTimes = []; // generated e.g. ["09:00","09:15",...]
  Set<String> _unavailableTimes = {}; // HELD or BOOKED for selected date
  String? _selectedTime;

  final _symptomsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _weekdays = _generateNextWeekdays(7);
    _displayFee = widget.consultationFee; // fallback jab tak live load ho
    _loadDoctorSettings();
    _loadLiveFee();
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    super.dispose();
  }

  // ── FIX 2: Live fee Firestore se load karo ────────────────
  // Taake screen wohi fee dikhaye jo transaction charge karegi.
  Future<void> _loadLiveFee() async {
    try {
      final feeDoc = await FirebaseFirestore.instance
          .collection('department_consultation_fees')
          .doc(widget.departmentId)
          .get();

      if (feeDoc.exists && mounted) {
        final feeData = feeDoc.data()!;
        setState(() {
          _displayFee = widget.appointmentType == 'VIDEO_CALL'
              ? (feeData['videoCallFee'] ?? widget.consultationFee)
              : (feeData['inPersonFee'] ?? widget.consultationFee);
        });
      }
    } catch (_) {
      // fail hua to fallback fee hi dikhegi — transaction phir bhi
      // live fee charge karegi, is liye galat charge kabhi nahi hoga
    }
  }

  // ── Next 7 weekdays, Sat/Sun skipped ──────────────────────
  List<DateTime> _generateNextWeekdays(int count) {
    final List<DateTime> result = [];
    DateTime cursor = DateTime.now();
    while (result.length < count) {
      if (cursor.weekday != DateTime.saturday &&
          cursor.weekday != DateTime.sunday) {
        result.add(DateTime(cursor.year, cursor.month, cursor.day));
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── FIX 1: kya yeh time aaj ke liye guzar chuka hai? ──────
  bool _isPastTime(String time) {
    final selectedDate = _weekdays[_selectedDateIndex];
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
    if (!isToday) return false; // future dates par sab times valid

    final parts = time.split(':').map(int.parse).toList();
    final slotDateTime = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, parts[0], parts[1]);
    return slotDateTime.isBefore(now);
  }

  // ── Load doctor_settings, then load slots for first date ──
  Future<void> _loadDoctorSettings() async {
    setState(() => _isLoadingSettings = true);
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('doctor_settings')
          .doc(widget.doctorId)
          .get();

      if (!settingsDoc.exists) {
        _showError('This doctor has no timing configured.');
        setState(() => _isLoadingSettings = false);
        return;
      }

      final data = settingsDoc.data()!;
      _startTime = data['appointmentStartTime'];
      _endTime = data['appointmentEndTime'];
      _allTimes = _generateTimes(_startTime!, _endTime!);

      setState(() => _isLoadingSettings = false);
      await _loadSlotsForSelectedDate();
    } catch (e) {
      setState(() => _isLoadingSettings = false);
      _showError('Error loading doctor availability: $e');
    }
  }

  // ── Generate 15-min interval times between start and end ──
  List<String> _generateTimes(String start, String end) {
    final startParts = start.split(':').map(int.parse).toList();
    final endParts = end.split(':').map(int.parse).toList();
    DateTime cursor = DateTime(2000, 1, 1, startParts[0], startParts[1]);
    final endTime = DateTime(2000, 1, 1, endParts[0], endParts[1]);

    final List<String> times = [];
    while (cursor.isBefore(endTime)) {
      times.add(
          '${cursor.hour.toString().padLeft(2, '0')}:${cursor.minute.toString().padLeft(2, '0')}');
      cursor = cursor.add(const Duration(minutes: 15));
    }
    return times;
  }

  // ── Fetch HELD/BOOKED slots for the selected date only ────
  Future<void> _loadSlotsForSelectedDate() async {
    setState(() {
      _isLoadingSlots = true;
      _selectedTime = null;
      _unavailableTimes = {};
    });
    try {
      final dateStr = _dateKey(_weekdays[_selectedDateIndex]);

      final slotsSnap = await FirebaseFirestore.instance
          .collection('slots')
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('date', isEqualTo: dateStr)
          .get();

      final Set<String> taken = {};
      for (final doc in slotsSnap.docs) {
        final status = doc.data()['slotStatus'];
        if (status == 'HELD' || status == 'BOOKED') {
          taken.add(doc.data()['startTime']);
        }
      }

      setState(() {
        _unavailableTimes = taken;
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => _isLoadingSlots = false);
      _showError('Error loading slots: $e');
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

  // ── Book: slot + appointment created atomically ───────────
  Future<void> _bookAppointment() async {
    if (_selectedTime == null) {
      _showError('Please select a time slot');
      return;
    }

    // FIX 1 (safety net): agar user ne slot select kiya aur phir
    // itni der screen par baitha raha ke time guzar gaya
    if (_isPastTime(_selectedTime!)) {
      _showError('This time has passed. Please pick another slot.');
      setState(() => _selectedTime = null);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showError('You must be logged in to book an appointment');
      return;
    }

    setState(() => _isBooking = true);

    final dateStr = _dateKey(_weekdays[_selectedDateIndex]);
    final timeKey = _selectedTime!.replaceAll(':', '');
    // Deterministic slot ID — lets us check-and-lock this exact
    // slot inside the transaction without needing a query.
    final slotId = '${widget.doctorId}_${dateStr}_$timeKey';

    final slotRef = FirebaseFirestore.instance.collection('slots').doc(slotId);
    final feeRef = FirebaseFirestore.instance
        .collection('department_consultation_fees')
        .doc(widget.departmentId);
    final apptRef = FirebaseFirestore.instance.collection('appointments').doc();

    num chargedFee = widget.consultationFee; // payment screen ko dene ke liye

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 1. Check slot isn't already taken (re-verify inside transaction)
        final slotSnap = await transaction.get(slotRef);
        if (slotSnap.exists) {
          final status = slotSnap.data()?['slotStatus'];
          if (status == 'HELD' || status == 'BOOKED') {
            throw Exception('This slot was just taken. Please pick another.');
          }
        }

        // 2. Read live consultation fee — never trust a value
        // fetched before the transaction started.
        final feeSnap = await transaction.get(feeRef);
        num liveFee = widget.consultationFee;
        if (feeSnap.exists) {
          final feeData = feeSnap.data()!;
          liveFee = widget.appointmentType == 'VIDEO_CALL'
              ? (feeData['videoCallFee'] ?? widget.consultationFee)
              : (feeData['inPersonFee'] ?? widget.consultationFee);
        }
        chargedFee = liveFee; // transaction ke bahar payment screen ko denge

        final endTimeIndex = _allTimes.indexOf(_selectedTime!);
        final slotEndTime = endTimeIndex + 1 < _allTimes.length
            ? _allTimes[endTimeIndex + 1]
            : _endTime!;

        // 3. Create appointment
        transaction.set(apptRef, {
          'appointmentId': apptRef.id,
          'patientId': uid,
          'doctorId': widget.doctorId,
          'departmentId': widget.departmentId,
          'slotId': slotId,
          'status': 'Requested',
          'consultationFee': liveFee,
          'symptoms': _symptomsController.text.trim().isEmpty
              ? null
              : _symptomsController.text.trim(),
          'patientReportUrl': null,
          'appointmentType': widget.appointmentType,
          'admissionRecommended': false,
          'consultationStartedAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // 4. Create/update slot as HELD, linked to this appointment
        transaction.set(slotRef, {
          'slotId': slotId,
          'doctorId': widget.doctorId,
          'date': dateStr,
          'startTime': _selectedTime,
          'endTime': slotEndTime,
          'slotStatus': 'HELD',
          'heldByAppointmentId': apptRef.id,
          'heldAt': FieldValue.serverTimestamp(),
          'appointmentId': null,
        });
      });

      if (!mounted) return;
      setState(() => _isBooking = false);

      // Appointment (Requested) + slot (HELD) ban gaye. Ab FORAN payment
      // screen kholo. Wahan se: submit → payment Pending record; cancel →
      // appointment + slot delete (clean exit).
      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentUploadScreen(
            appointmentId: apptRef.id,
            slotId: slotId,
            amount: chargedFee,
            doctorName: widget.doctorName,
          ),
        ),
      );

      if (!mounted) return;

      if (paid == true) {
        // Payment submit ho gayi
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Booking requested! Awaiting reception confirmation.'),
          backgroundColor: _primary,
        ));
        Navigator.pop(context);
      } else {
        // Cancel hua (payment nahi ki) — slot/appointment delete ho chuke
        // payment screen me. Bas slots refresh karo.
        _loadSlotsForSelectedDate();
      }
    } catch (e) {
      setState(() => _isBooking = false);
      _showError(e is String ? e : 'Booking failed: $e');
      // Refresh slots so the user sees updated availability
      _loadSlotsForSelectedDate();
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
              child: _isLoadingSettings
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDoctorCard(),
                          const SizedBox(height: 20),
                          const Text('Select date',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2F3A))),
                          const SizedBox(height: 10),
                          _buildDateSelector(),
                          const SizedBox(height: 20),
                          const Text('Available slots',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2F3A))),
                          const SizedBox(height: 10),
                          _isLoadingSlots
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: _primary)),
                                )
                              : _buildSlotsGrid(),
                          const SizedBox(height: 20),
                          const Text('Symptoms (optional)',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2F3A))),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _symptomsController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Briefly describe your symptoms...',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            if (!_isLoadingSettings) _buildCheckoutBar(),
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
          const Text('Book appointment',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDoctorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.doctorName,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 2),
          Text(
            '${widget.specialization} - ${widget.appointmentType == 'VIDEO_CALL' ? 'Video consult' : 'In-clinic visit'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _weekdays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final isSelected = i == _selectedDateIndex;
          final d = _weekdays[i];
          const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          return GestureDetector(
            onTap: () {
              setState(() => _selectedDateIndex = i);
              _loadSlotsForSelectedDate();
            },
            child: Container(
              width: 48,
              decoration: BoxDecoration(
                color: isSelected ? _primary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(dayNames[d.weekday - 1],
                      style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white70 : Colors.grey)),
                  const SizedBox(height: 2),
                  Text('${d.day}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF1A2F3A))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlotsGrid() {
    if (_allTimes.isEmpty) {
      return const Text('No slots configured for this doctor.',
          style: TextStyle(color: Colors.grey));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _allTimes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (context, index) {
        final time = _allTimes[index];
        // FIX 1: slot unavailable hai agar HELD/BOOKED hai
        // YA aaj ki date par time guzar chuka hai
        final isAvailable =
            !_unavailableTimes.contains(time) && !_isPastTime(time);
        final isSelected = time == _selectedTime && isAvailable;

        return GestureDetector(
          onTap:
              isAvailable ? () => setState(() => _selectedTime = time) : null,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? _primary
                  : isAvailable
                      ? Colors.white
                      : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(10),
              boxShadow: isAvailable
                  ? [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]
                  : [],
            ),
            alignment: Alignment.center,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : isAvailable
                        ? const Color(0xFF1A2F3A)
                        : Colors.grey,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Consultation fee',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              // FIX 2: live fee dikhao, purani widget wali nahi
              Text('Rs. ${_displayFee ?? widget.consultationFee}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2F3A))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBooking ? null : _bookAppointment,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isBooking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('Request appointment',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
