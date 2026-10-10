import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'payment_upload_screen.dart';
import '../widgets/app_ui.dart';

/// FIXES IS FILE MEIN:
/// 1. Past-time slots: aaj ki date par guzre hue times ab disabled hain
///    (pehle 3 baje bhi subah 9:00 ka slot book ho sakta tha)
/// 2. Live fee: checkout bar ab Firestore se load ki hui LIVE fee
///    dikhata hai (pehle purani widget.consultationFee dikhti thi,
///    lekin transaction naya rate charge karti thi — mismatch)
/// 3. Fee ab PER-DOCTOR hai (doctor_consultation_fees), department-wide
///     nahi — dono jagah update kiya.
/// 4. IN_PERSON notice: agar appointmentType == 'IN_PERSON' hai to ek
///    simple banner dikhta hai jo patient ko batata hai ke appointment
///    time se 10 min pehle pohanchna hai, warna cancellation ho sakti hai.
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
  Set<String> _patientBookedTimes =
      {}; // is date, patient ki apni doosri bookings
  String? _selectedTime;

  final _symptomsController = TextEditingController();
  final _picker = ImagePicker();
  // Optional: patient purani medical report attach kar sakta hai.
  // Storage avoid karne ke liye base64 me Firestore me jaati hai
  // (jaise payment screenshot) — schema: patientReportUrl → base64.
  String? _reportBase64;
  String? _reportType;
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

  // ── FIX 2 + 3: Live fee Firestore se load karo — PER-DOCTOR ────
  // Taake screen wohi fee dikhaye jo transaction charge karegi.
  Future<void> _loadLiveFee() async {
    try {
      final feeDoc = await FirebaseFirestore.instance
          .collection('doctor_consultation_fees')
          .doc(widget.doctorId)
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

  // ── Next 7 weekdays, Sat/Sun skipped
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
      // Sirf tab add karo jab poora 15-min slot end-time ke andar
      // fit ho jaye — warna aisa slot na bane jo doctor ki asal
      // availability se bahar chala jaye (jaise 11:45 slot jab
      // doctor sirf 11:50 tak available hai).
      final slotEnd = cursor.add(const Duration(minutes: 15));
      if (slotEnd.isAfter(endTime)) break;

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
      _patientBookedTimes = {};
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

      // ── PATIENT SELF-COLLISION CHECK ──
      // Isi patient ki, isی date ki, KISI BHI doctor ke saath
      // (chahe alag department ho) Requested/Confirmed appointment
      // ho to us time ko is patient ke liye disable karo — ek waqt
      // pe do jagah nahi ho sakta.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final Set<String> patientTimes = {};
      if (uid != null) {
        final patientApptSnap = await FirebaseFirestore.instance
            .collection('appointments')
            .where('patientId', isEqualTo: uid)
            .where('status', whereIn: ['Requested', 'Confirmed']).get();

        for (final apptDoc in patientApptSnap.docs) {
          final apptSlotId = apptDoc.data()['slotId'];
          if (apptSlotId == null) continue;
          final apptSlotDoc = await FirebaseFirestore.instance
              .collection('slots')
              .doc(apptSlotId)
              .get();
          if (!apptSlotDoc.exists) continue;
          final apptSlotData = apptSlotDoc.data()!;
          if (apptSlotData['date'] == dateStr) {
            patientTimes.add(apptSlotData['startTime']);
          }
        }
      }

      setState(() {
        _unavailableTimes = taken;
        _patientBookedTimes = patientTimes;
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
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Report pick (gallery image) ──
  Future<void> _pickReport() async {
    await _pickImageReport();
  }

// ── Gallery image pick (purana image_picker wala logic) ──
  Future<void> _pickImageReport() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 65,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > 700 * 1024) {
        _showError('Image too large. Please choose a smaller file.');
        return;
      }
      setState(() {
        _reportBase64 = base64Encode(bytes);
        _reportType = 'image';
      });
    } catch (e) {
      _showError('Could not load image: $e');
    }
  }

  void _removeReport() => setState(() {
        _reportBase64 = null;
        _reportType = null;
      });

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
    // FIX 3: fee ab per-doctor collection se, department se nahi
    final feeRef = FirebaseFirestore.instance
        .collection('doctor_consultation_fees')
        .doc(widget.doctorId);
    final apptRef = FirebaseFirestore.instance.collection('appointments').doc();

    num chargedFee = widget.consultationFee; // payment screen ko dene ke liye

    try {
      // Patient collision-check: transaction se PEHLE karna hoga
      // (Firestore transaction ke andar collection-query allowed
      // nahi hoti, sirf .get() single-documents ki). Yeh guaranteed
      // check hai, UI-check ke alawa ek aur safety-layer.
      final patientApptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: uid)
          .where('status', whereIn: ['Requested', 'Confirmed']).get();

      for (final apptDoc in patientApptSnap.docs) {
        final apptSlotId = apptDoc.data()['slotId'];
        if (apptSlotId == null) continue;
        final apptSlotDoc = await FirebaseFirestore.instance
            .collection('slots')
            .doc(apptSlotId)
            .get();
        if (!apptSlotDoc.exists) continue;
        final apptSlotData = apptSlotDoc.data()!;
        if (apptSlotData['date'] == dateStr &&
            apptSlotData['startTime'] == _selectedTime) {
          _showError(
              'You already have an appointment at this time on this date.');
          setState(() => _isBooking = false);
          return;
        }
      }

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
        // fetched before the transaction started. Ab PER-DOCTOR.
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
          'patientReportBase64': _reportBase64,
          'patientReportType': _reportType,
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
          backgroundColor: AppColors.teal,
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
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoadingSettings
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDoctorCard(),
                        // ── IN_PERSON ARRIVAL NOTICE ── (sirf in-clinic)
                        if (widget.appointmentType == 'IN_PERSON') ...[
                          const SizedBox(height: 12),
                          _buildArrivalNotice(),
                        ],
                        const SizedBox(height: 20),
                        _sectionLabel('SELECT DATE'),
                        const SizedBox(height: 10),
                        _buildDateSelector(),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _sectionLabel('AVAILABLE SLOTS')),
                            _legendDot(Colors.white, 'Free', border: true),
                            const SizedBox(width: 10),
                            _legendDot(const Color(0xFFE6ECEC), 'Taken'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _isLoadingSlots
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                    child: CircularProgressIndicator(
                                        color: AppColors.teal)),
                              )
                            : _buildSlotsGrid(),
                        const SizedBox(height: 20),
                        _sectionLabel('SYMPTOMS (OPTIONAL)'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _symptomsController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Briefly describe your symptoms...',
                            hintStyle: const TextStyle(color: AppColors.faint),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                  color: AppColors.teal, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _sectionLabel('ATTACH PREVIOUS REPORT (OPTIONAL)'),
                        const SizedBox(height: 3),
                        const Text(
                          'Share an old prescription or test result, if relevant.',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.faint),
                        ),
                        const SizedBox(height: 10),
                        _buildReportPicker(),
                      ],
                    ),
                  ),
          ),
          if (!_isLoadingSettings) _buildCheckoutBar(),
        ],
      ),
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

  Widget _legendDot(Color color, String label, {bool border = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: border ? Border.all(color: AppColors.border) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.faint)),
      ],
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Book appointment',
      subtitle: widget.appointmentType == 'VIDEO_CALL'
          ? 'Video consult'
          : 'In-clinic visit',
    );
  }

  Widget _buildDoctorCard() {
    final name = widget.doctorName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.tealSoft,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppColors.teal,
                  fontSize: 17,
                  fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text(
                  '${widget.specialization} - ${widget.appointmentType == 'VIDEO_CALL' ? 'Video consult' : 'In-clinic visit'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Sirf IN_PERSON ke liye — informational, booking logic par asar nahi.
  Widget _buildArrivalNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2E2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.access_time_rounded, color: Color(0xFF8A6D00), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please arrive 10 minutes before your appointment time. '
              'Arriving late may result in your appointment being cancelled.',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF6B5500),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 66,
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.header : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(dayNames[d.weekday - 1],
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? AppColors.headerMuted
                              : AppColors.faint)),
                  const SizedBox(height: 2),
                  Text('${d.day}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : AppColors.text)),
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
          style: TextStyle(color: AppColors.faint));
    }
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _allTimes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (context, index) {
        final time = _allTimes[index];
        // Slot unavailable: HELD/BOOKED, time guzar gaya, ya patient ki
        // apni booking — same check as before
        final isAvailable = !_unavailableTimes.contains(time) &&
            !_isPastTime(time) &&
            !_patientBookedTimes.contains(time);
        final isSelected = time == _selectedTime && isAvailable;

        return GestureDetector(
          onTap:
              isAvailable ? () => setState(() => _selectedTime = time) : null,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.mint
                  : isAvailable
                      ? Colors.white
                      : const Color(0xFFE6ECEC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.header
                    : isAvailable
                        ? AppColors.border
                        : const Color(0xFFE6ECEC),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isAvailable ? AppColors.header : const Color(0xFF9DB0B0),
                decoration: isAvailable
                    ? TextDecoration.none
                    : TextDecoration.lineThrough,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportPicker() {
    if (_reportBase64 != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                base64Decode(_reportBase64!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _smallAction(Icons.refresh_rounded, 'Change',
                      AppColors.teal, AppColors.tealSoft, _pickReport),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _smallAction(Icons.close_rounded, 'Remove',
                      AppColors.danger, AppColors.dangerSoft, _removeReport),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickReport,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: Container(
          width: double.infinity,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.attach_file_rounded, size: 24, color: AppColors.muted),
              SizedBox(height: 6),
              Text('Tap to attach a report',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallAction(
      IconData icon, String label, Color fg, Color bg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Consultation fee',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
              // live fee — same value as before
              Text('Rs. ${_displayFee ?? widget.consultationFee}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B5E57))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isBooking ? null : _bookAppointment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.header,
                disabledBackgroundColor: AppColors.header.withOpacity(0.5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
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
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed rounded border for the "attach report" box (UI only).
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB9CFCC)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
