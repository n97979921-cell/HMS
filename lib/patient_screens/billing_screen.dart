import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'bill_detail_screen.dart';
import '../widgets/app_ui.dart';

///  REAL-TIME (Rule 2): Data `payments` + `appointments` + `users` +
/// `departments` + `slots` se milkar banta hai, is liye poori screen
/// StreamBuilder mein convert NAHI ki. Iski jagah ek lightweight
/// listener `payments` collection ko sunta hai (patientId filter ke
/// saath) — yahin par status (Pending → Paid) badalta hai jab
/// receptionist verify karta hai. Jab bhi kuch badle, purana
/// `_loadBills()` khud-ba-khud dobara call ho jaata hai.
///
/// NAYA — DELETE (sirf "Paid" bills par): Har fully-paid bill card
/// par ek individual "Delete" icon — us appointment ke SAARE payment
/// records (consultation/lab/room jo bhi is bill mein shamil hain)
/// permanent delete karta hai (batch write). Jab list mein koi bhi
/// Paid bill ho, ek "Delete All" button bhi (header ke neeche) —
/// woh EK SATH saare currently-Paid bills ke payment records delete
/// kar deta hai. Dono jagah koi confirmation dialog nahi — seedha
/// permanent delete, jaisa app ke baaki delete-patterns (Refunds,
/// Lab Staff Completed tab) mein hai. "Pending" bills par delete
/// nahi dikhta — unhe abhi collect/verify hona baaki hai.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];

  // Real-time listener — sirf `payments` collection ko sunta hai
  // (patientId filter ke saath).
  StreamSubscription<QuerySnapshot>? _paymentsSub;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _paymentsSub?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Pehla event hi initial load ka kaam kar deta hai, is liye alag
    // se _loadBills() call karne ki zaroorat nahi.
    _paymentsSub = FirebaseFirestore.instance
        .collection('payments')
        .where('patientId', isEqualTo: uid)
        .snapshots()
        .listen((_) {
      _loadBills();
    }, onError: (_) {
      setState(() => _isLoading = false);
    });
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

      if (!mounted) return;
      setState(() {
        _groups = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error loading bills: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF9A2E16),
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

  // ── Delete ek bill (ek appointment ke SAARE payment records) —
  //    bina confirmation ke seedha permanent delete ──
  Future<void> _deleteBill(Map<String, dynamic> group) async {
    try {
      final payments = group['payments'] as List<Map<String, dynamic>>;
      final batch = FirebaseFirestore.instance.batch();
      for (final p in payments) {
        batch.delete(FirebaseFirestore.instance
            .collection('payments')
            .doc(p['paymentId']));
      }
      await batch.commit();
      _showSuccess('Bill deleted');
      _loadBills();
    } catch (e) {
      _showError('Error deleting bill: $e');
    }
  }

  // ── Delete All — SAARE currently-Paid bills ke payment records ek
  //    batch write mein, bina confirmation ke ──
  Future<void> _deleteAllPaidBills() async {
    try {
      final paidGroups = _groups.where((g) => g['hasPending'] == false);
      if (paidGroups.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (final group in paidGroups) {
        final payments = group['payments'] as List<Map<String, dynamic>>;
        for (final p in payments) {
          batch.delete(FirebaseFirestore.instance
              .collection('payments')
              .doc(p['paymentId']));
          count++;
        }
      }
      await batch.commit();
      _showSuccess('$count paid bill record(s) deleted');
      _loadBills();
    } catch (e) {
      _showError('Error deleting all: $e');
    }
  }

  bool get _hasAnyPaidBill => _groups.any((g) => g['hasPending'] == false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          if (!_isLoading && _hasAnyPaidBill) _buildDeleteAllBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _groups.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadBills,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              20, _hasAnyPaidBill ? 4 : 16, 20, 24),
                          itemCount: _groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) => _apptCard(_groups[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // UI only: header summary list se hi calculate hota hai
  num get _totalPaid => _groups.fold<num>(0, (sum, g) {
        final v = g['total'];
        return sum + (v is num ? v : 0);
      });

  int get _pendingCount => _groups.where((g) => g['hasPending'] == true).length;

  Widget _buildHeader() {
    return AppHeader(
      title: 'Billing',
      subtitle: 'Payments & dues',
      bottom: _isLoading
          ? null
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total paid',
                          style: TextStyle(
                              color: AppColors.headerMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Rs. $_totalPaid',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (_pendingCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.star.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$_pendingCount pending',
                        style: const TextStyle(
                            color: AppColors.star,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
    );
  }

  // "Delete All Paid" — same action, bina confirmation (pehle jaisa)
  Widget _buildDeleteAllBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: _deleteAllPaidBills,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_sweep_outlined,
                    size: 16, color: AppColors.danger),
                SizedBox(width: 6),
                Text('Delete All Paid',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No bills yet',
      ),
    );
  }

  Widget _apptCard(Map<String, dynamic> group) {
    final hasPending = group['hasPending'] as bool;
    final count = (group['payments'] as List).length;
    final String date = group['dateLabel'].isEmpty ? '' : group['dateLabel'];

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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group['doctorName'],
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(
                          date.isEmpty
                              ? '${group['department']}'
                              : '${group['department']} · $date',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AppStatusChip(
                  label: hasPending ? 'Pending' : 'Paid',
                  colors: hasPending
                      ? const AppChipColors(
                          Color(0xFF8A6D00), Color(0xFFF6F2E2))
                      : const AppChipColors(
                          Color(0xFF0B5E57), Color(0xFFDDF3EE)),
                ),
                // Individual delete — sirf Paid bills par
                if (!hasPending) ...[
                  const SizedBox(width: 6),
                  AppDeleteButton(
                    onTap: () => _deleteBill(group),
                    size: 30,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('$count bill${count == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ),
                  Text('Rs. ${group['total']}',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B5E57))),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.faint),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
