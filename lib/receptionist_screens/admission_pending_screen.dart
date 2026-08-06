import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'assign_bed_screen.dart';

/// ADMISSION PENDING (Receptionist)
///
/// Doctor ne "Recommend Admission" ON kiya (Completed appointments mein).
/// Yahan woh saare patients dikhte hain jinhe abhi tak koi bed
/// assign NAHI hui.
///
/// "Pending" ka matlab:
///   admissionRecommended == true  AND
///   koi Occupied bed is appointmentId ko point nahi karta (abhi admit nahi) AND
///   koi Paid Room-type payment is appointmentId ke liye nahi (pehle
///   discharge ho chuka to dobara pending mein nahi aana chahiye)
class AdmissionPendingScreen extends StatefulWidget {
  const AdmissionPendingScreen({super.key});

  @override
  State<AdmissionPendingScreen> createState() => _AdmissionPendingScreenState();
}

class _AdmissionPendingScreenState extends State<AdmissionPendingScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _pending = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      // Doctor ne recommend kiya + consultation complete
      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('admissionRecommended', isEqualTo: true)
          .where('status', isEqualTo: 'Completed')
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final doc in apptSnap.docs) {
        final appt = doc.data();
        final apptId = doc.id;

        // Kya abhi koi Occupied bed isko point karta hai? (already admit)
        final occupiedBedSnap = await FirebaseFirestore.instance
            .collection('beds')
            .where('appointmentId', isEqualTo: apptId)
            .where('availability', isEqualTo: 'Occupied')
            .limit(1)
            .get();
        if (occupiedBedSnap.docs.isNotEmpty) continue; // Occupied list mein hai

        // Kya pehle discharge ho chuka (Room payment Paid hai)?
        final roomPaymentSnap = await FirebaseFirestore.instance
            .collection('payments')
            .where('appointmentId', isEqualTo: apptId)
            .where('type', isEqualTo: 'Room')
            .where('status', isEqualTo: 'Paid')
            .limit(1)
            .get();
        if (roomPaymentSnap.docs.isNotEmpty) continue; // already discharged

        // Patient + doctor naam
        String patientName = 'Patient';
        String doctorName = 'Doctor';
        try {
          final p = await FirebaseFirestore.instance
              .collection('users')
              .doc(appt['patientId'])
              .get();
          patientName = p.data()?['name'] ?? 'Patient';
          final d = await FirebaseFirestore.instance
              .collection('users')
              .doc(appt['doctorId'])
              .get();
          doctorName = d.data()?['name'] ?? 'Doctor';
        } catch (_) {}

        result.add({
          'appointmentId': apptId,
          'patientId': appt['patientId'],
          'patientName': patientName,
          'doctorName': doctorName,
          'appointmentType': appt['appointmentType'] ?? '',
        });
      }

      setState(() {
        _pending = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading admissions: $e');
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
                  : _pending.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _pending.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _card(_pending[i]),
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
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Admission Pending',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bed_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No admissions pending',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE6E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_hospital_outlined,
                color: Color(0xFFD9534F), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['patientName'],
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A))),
                const SizedBox(height: 2),
                Text('Recommended by Dr. ${p['doctorName']}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final assigned = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => AssignBedScreen(
                    appointmentId: p['appointmentId'],
                    patientId: p['patientId'],
                    patientName: p['patientName'],
                  ),
                ),
              );
              if (assigned == true) _load();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Assign Bed',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
