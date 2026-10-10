import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

/// BILL DETAIL — Simple version
/// - Grand total = sirf PAID payments ka sum (Pending/Cancelled/
///   Refunded shaamil nahi)
/// - Breakdown list mein SAB payments dikhte hain (status ke saath),
///   Lab-type ke liye asal test-ka-naam bhi (referenceId se
///   lab_tests collection se fetch karke), na ke generic "Lab"
class BillDetailScreen extends StatefulWidget {
  final String appointmentId;

  const BillDetailScreen({super.key, required this.appointmentId});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
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

        // Lab-type payment ke liye asal test-naam fetch karo
        // (referenceId = testId → lab_tests collection)
        String displayName = data['type'] ?? '';
        if (data['type'] == 'Lab' && data['referenceId'] != null) {
          try {
            final testDoc = await FirebaseFirestore.instance
                .collection('lab_tests')
                .doc(data['referenceId'])
                .get();
            if (testDoc.exists) {
              displayName = testDoc.data()?['testType'] ?? 'Lab';
            }
          } catch (_) {
            // fetch fail ho to generic "Lab" hi dikha do
          }
        }

        payments.add({
          'paymentId': doc.id,
          'displayName': displayName,
          ...data,
        });

        // Sirf PAID payments hi grand-total mein count hoti hain —
        // Pending (abhi collect nahi hui), Cancelled/Refunded (paisa
        // wapas ya kabhi liya hi nahi) shamil nahi.
        if (data['status'] == 'Paid') {
          total += (data['amount'] ?? 0) as num;
        }
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

  Color _statusColor(String status) {
    switch (status) {
      case 'Paid':
        return const Color(0xFF0B5E57);
      case 'Pending':
        return const Color(0xFF8A6D00);
      case 'Cancelled':
      case 'Rejected':
        return Colors.grey;
      case 'Refunded':
      case 'HalfRefunded':
        return const Color(0xFF9A2E16);
      default:
        return Colors.grey;
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCard(),
                        const SizedBox(height: 20),
                        const Text('CHARGE BREAKDOWN',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppColors.muted)),
                        const SizedBox(height: 10),
                        _buildBreakdownCard(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Bill detail',
      subtitle: _isLoading ? null : _doctorName,
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_doctorName,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          const SizedBox(height: 2),
          Text(_dateLabel.isEmpty ? _department : '$_department · $_dateLabel',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.header,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rs. $_total',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                const Text('Total for this appointment (paid so far)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.headerMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppChipColors _typeColors(String type) {
    switch (type) {
      case 'Lab':
        return const AppChipColors(AppColors.blue, AppColors.blueSoft);
      case 'Room':
        return const AppChipColors(Color(0xFF5B3FA8), Color(0xFFEEE8FB));
      default:
        return const AppChipColors(AppColors.teal, AppColors.tealSoft);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Lab':
        return Icons.science_outlined;
      case 'Room':
        return Icons.bed_outlined;
      default:
        return Icons.medical_services_outlined;
    }
  }

  Widget _buildBreakdownCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: List.generate(_payments.length, (i) {
          final p = _payments[i];
          final status = p['status'] ?? '';
          final String type = '${p['type'] ?? ''}';
          final c = _typeColors(type);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: i != _payments.length - 1
                  ? const Border(bottom: BorderSide(color: AppColors.divider))
                  : null,
            ),
            child: Row(
              children: [
                AppIconTile(
                  icon: _typeIcon(type),
                  color: c.fg,
                  background: c.bg,
                  size: 38,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['displayName'] ?? p['type'] ?? '',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(
                        p['paymentMethod'] ?? '',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.faint),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Rs. ${p['amount']}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(status)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
