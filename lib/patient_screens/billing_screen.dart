import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'bill_detail_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      final paySnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('patientId', isEqualTo: uid)
          .get();

      // Group payments by appointmentId
      final Map<String, List<Map<String, dynamic>>> byAppt = {};
      for (final doc in paySnap.docs) {
        final data = doc.data();
        final apptId = data['appointmentId'] as String?;
        if (apptId == null) continue;
        byAppt.putIfAbsent(apptId, () => []).add({
          'paymentId': doc.id,
          ...data,
        });
      }

      final List<Map<String, dynamic>> result = [];

      for (final entry in byAppt.entries) {
        final apptId = entry.key;
        final payments = entry.value;

        final apptDoc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(apptId)
            .get();
        if (!apptDoc.exists) continue;
        final apptData = apptDoc.data()!;

        final doctorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(apptData['doctorId'])
            .get();

        final deptDoc = await FirebaseFirestore.instance
            .collection('departments')
            .doc(apptData['departmentId'])
            .get();

        String dateLabel = '';
        final slotId = apptData['slotId'];
        if (slotId != null) {
          final slotDoc = await FirebaseFirestore.instance
              .collection('slots')
              .doc(slotId)
              .get();
          if (slotDoc.exists) {
            final slotData = slotDoc.data()!;
            final dateStr = slotData['date'];
            if (dateStr != null) {
              try {
                dateLabel =
                    DateFormat('d MMM, yyyy').format(DateTime.parse(dateStr));
              } catch (_) {}
            }
          }
        }

        // Sirf PAID payments hi bill mein count hote hain — Pending
        // (abhi collect nahi hui), Rejected (fake thi) aur
        // Refunded/HalfRefunded (paisa wapas ho gaya) shamil nahi.
        num total = 0;
        bool hasPending = false;
        for (final p in payments) {
          if (p['status'] == 'Paid') {
            total += (p['amount'] ?? 0) as num;
          }
          if (p['status'] == 'Pending') hasPending = true;
        }

        // Agar is appointment ka koi bhi payment abhi tak Paid nahi
        // hua, koi bill-card mat dikhao — abhi "confirmed kharcha"
        // hai hi nahi.
        if (total == 0 && !hasPending) continue;

        result.add({
          'appointmentId': apptId,
          'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
          'department': deptDoc.exists ? (deptDoc.data()?['name'] ?? '') : '',
          'dateLabel': dateLabel,
          'payments': payments,
          'total': total,
          'hasPending': hasPending,
        });
      }

      setState(() {
        _groups = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading bills: $e');
    }
  }

  void _showError(String msg) {
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
                  : _groups.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadBills,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _groups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _apptCard(_groups[i]),
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
          const Text('Billing',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64, color: _primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('No bills yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _apptCard(Map<String, dynamic> group) {
    final hasPending = group['hasPending'] as bool;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BillDetailScreen(appointmentId: group['appointmentId']),
          ),
        );
      },
      child: Container(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group['doctorName'],
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2F3A))),
                      const SizedBox(height: 2),
                      Text(group['department'],
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: hasPending
                        ? const Color(0xFFFCEFD8)
                        : const Color(0xFFDCEFE9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasPending ? 'Pending' : 'Paid',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasPending
                            ? const Color(0xFFB8860B)
                            : const Color(0xFF1F8A70)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(group['dateLabel'].isEmpty ? '' : group['dateLabel'],
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    '${(group['payments'] as List).length} bill${(group['payments'] as List).length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text('Rs. ${group['total']}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2F3A))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
