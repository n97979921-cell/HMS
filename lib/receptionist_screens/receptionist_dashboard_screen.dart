import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verify_payments_screen.dart';
import 'refunds_pending_screen.dart';
import 'receptionist_profile_screen.dart';
import 'walk_in_screen.dart';
import 'appointments_today_screen.dart';

/// RECEPTIONIST DASHBOARD
/// Patient-side green theme, lekin dashboard-style (doosron ka data manage).
/// 4 core kaam (schema ke mutabiq):
///   1. Pending Payments  → EasyPaisa screenshot verify → appointment Confirm
///   2. Appointments      → saari appointments dekhna/manage
///   3. Walk-in Patient   → CNIC check → register → book
///   4. Lab Payments      → unpaid lab test cash collect → Paid
///
/// NOTE: abhi cards ke destination screens (#2 onwards) ban rahe hain —
/// Lab Payments card abhi _comingSoon par hai (doctor lab-request ke baad banega).
class ReceptionistDashboardScreen extends StatefulWidget {
  const ReceptionistDashboardScreen({super.key});

  @override
  State<ReceptionistDashboardScreen> createState() =>
      _ReceptionistDashboardScreenState();
}

class _ReceptionistDashboardScreenState
    extends State<ReceptionistDashboardScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  String _receptionistName = '';
  bool _isLoading = true;

  // Live counts — dashboard cards par badge dikhane ke liye
  int _pendingPayments = 0;
  int _todayAppointments = 0;
  int _unpaidLabTests = 0;
  int _pendingRefunds = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        _receptionistName = userDoc.data()?['name'] ?? 'Receptionist';
      }

      // Pending consultation payments (verify karne wale)
      final paymentsSnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'Pending')
          .get();
      _pendingPayments = paymentsSnap.docs.length;

      // Aaj ki appointments
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final slotsSnap = await FirebaseFirestore.instance
          .collection('slots')
          .where('date', isEqualTo: dateStr)
          .where('slotStatus', isEqualTo: 'BOOKED')
          .get();
      _todayAppointments = slotsSnap.docs.length;

      // Unpaid lab tests
      final labSnap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('paymentStatus', isNull: true)
          .get();
      _unpaidLabTests = labSnap.docs.length;

      // Pending refunds (dena baaki)
      final refundsSnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', whereIn: ['Refunded', 'HalfRefunded'])
          .where('refundPaid', isEqualTo: false)
          .get();
      _pendingRefunds = refundsSnap.docs.length;
    } catch (e) {
      // Silent — counts 0 reh jayenge, dashboard phir bhi chalega
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Coming soon'),
      backgroundColor: _primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: _primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildStatsRow(),
                const SizedBox(height: 24),
                const Text(
                  'Quick actions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2F3A),
                  ),
                ),
                const SizedBox(height: 14),
                _buildActionGrid(),
                const SizedBox(height: 12),
                _buildRefundsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reception Desk',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _isLoading ? 'Loading...' : _receptionistName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text('Manage appointments & payments',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          // Bell (notifications — abhi coming soon)
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Notifications coming soon'),
                backgroundColor: _primary,
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          // Profile
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ReceptionistProfileScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard('Pending\nPayments', _pendingPayments,
            const Color(0xFFFCEFD8), const Color(0xFFB8860B)),
        const SizedBox(width: 10),
        _statCard('Today\nBooked', _todayAppointments, const Color(0xFFDCEFE9),
            _primary),
        const SizedBox(width: 10),
        _statCard('Unpaid\nLab Tests', _unpaidLabTests, const Color(0xFFD9ECF8),
            const Color(0xFF1565C0)),
      ],
    );
  }

  Widget _statCard(String label, int count, Color bg, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              _isLoading ? '—' : '$count',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor.withValues(alpha: 0.9),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        _actionCard(
          icon: Icons.payments_outlined,
          iconBg: const Color(0xFFFCEFD8),
          iconColor: const Color(0xFFB8860B),
          title: 'Verify Payments',
          subtitle: 'Confirm consultations',
          badge: _pendingPayments,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerifyPaymentsScreen()),
            );
            _loadData();
          },
        ),
        _actionCard(
          icon: Icons.event_note_outlined,
          iconBg: const Color(0xFFDCEFE9),
          iconColor: _primary,
          title: 'Appointments',
          subtitle: 'Check-in & no-show',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AppointmentsTodayScreen()),
            );
            _loadData();
          },
        ),
        _actionCard(
          icon: Icons.person_add_alt_1_outlined,
          iconBg: const Color(0xFFEAE3F7),
          iconColor: const Color(0xFF7E57C2),
          title: 'Walk-in Patient',
          subtitle: 'Register & book',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalkInScreen()),
            );
            _loadData();
          },
        ),
        _actionCard(
          icon: Icons.science_outlined,
          iconBg: const Color(0xFFD9ECF8),
          iconColor: const Color(0xFF1565C0),
          title: 'Lab Payments',
          subtitle: 'Collect & forward',
          badge: _unpaidLabTests,
          onTap: _comingSoon, // #4 banega
        ),
      ],
    );
  }

  // Pending Refunds — full-width card (grid ke neeche, akela latakta nahi)
  Widget _buildRefundsCard() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RefundsPendingScreen()),
        );
        _loadData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDE6E0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.currency_exchange_outlined,
                  color: Color(0xFFD9534F), size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pending Refunds',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2F3A))),
                  SizedBox(height: 2),
                  Text('Pay & mark done',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            if (_pendingRefunds > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9534F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_pendingRefunds',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                if (badge > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9534F),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
