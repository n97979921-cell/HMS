import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BillDetailScreen extends StatefulWidget {
  final String appointmentId;

  const BillDetailScreen({super.key, required this.appointmentId});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  String _doctorName = '';
  String _department = '';
  String _dateLabel = '';
  List<Map<String, dynamic>> _payments = [];
  num _total = 0;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
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
      final apptData = apptDoc.data()!;

      final doctorDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(apptData['doctorId'])
          .get();
      _doctorName = doctorDoc.data()?['name'] ?? 'Doctor';

      final deptDoc = await FirebaseFirestore.instance
          .collection('departments')
          .doc(apptData['departmentId'])
          .get();
      _department = deptDoc.exists ? (deptDoc.data()?['name'] ?? '') : '';

      final slotId = apptData['slotId'];
      if (slotId != null) {
        final slotDoc = await FirebaseFirestore.instance
            .collection('slots')
            .doc(slotId)
            .get();
        if (slotDoc.exists) {
          final dateStr = slotDoc.data()!['date'];
          if (dateStr != null) {
            try {
              _dateLabel =
                  DateFormat('d MMM, yyyy').format(DateTime.parse(dateStr));
            } catch (_) {}
          }
        }
      }

      final paySnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('appointmentId', isEqualTo: widget.appointmentId)
          .get();

      final List<Map<String, dynamic>> payments = [];
      num total = 0;
      for (final doc in paySnap.docs) {
        final data = doc.data();
        payments.add({'paymentId': doc.id, ...data});
        total += (data['amount'] ?? 0) as num;
      }

      // Consultation first, then Lab, then Room
      const order = {'Consultation': 0, 'Lab': 1, 'Room': 2};
      payments.sort(
          (a, b) => (order[a['type']] ?? 3).compareTo(order[b['type']] ?? 3));

      setState(() {
        _payments = payments;
        _total = total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryCard(),
                          const SizedBox(height: 20),
                          const Text('Charge breakdown',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2F3A))),
                          const SizedBox(height: 10),
                          _buildBreakdownCard(),
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
          const Text('Bill detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          Text(_doctorName,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 2),
          Text(_department,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(_dateLabel,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text('Rs. $_total',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const Text('Total for this appointment',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    return Container(
      width: double.infinity,
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
        children: List.generate(_payments.length, (i) {
          final p = _payments[i];
          final isPending = p['status'] == 'Pending';
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['type'] ?? '',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A2F3A))),
                          const SizedBox(height: 2),
                          Text(
                            p['paymentMethod'] ?? '',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Rs. ${p['amount']}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A2F3A))),
                        const SizedBox(height: 2),
                        Text(
                          p['status'] ?? '',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isPending
                                  ? const Color(0xFFB8860B)
                                  : const Color(0xFF1F8A70)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (i != _payments.length - 1)
                const Divider(height: 1, indent: 14, endIndent: 14),
            ],
          );
        }),
      ),
    );
  }
}
