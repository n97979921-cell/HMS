import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verify_payments_screen.dart';
import 'appointments_today_screen.dart';
import 'walk_in_screen.dart';
import 'lab_payments_screen.dart';
import 'admissions_screen.dart';
import 'refunds_pending_screen.dart';
import 'receptionist_profile_screen.dart';
import '../widgets/notification_bell_icon.dart';

/// RECEPTIONIST DASHBOARD — professional layout
///
/// Header (gradient, name + bell + profile) → compact stat-chip row
/// (Pending / Today / Refunds) → 2x2 quick-action grid (Verify, Check-in,
/// Walk-in, Lab Payments) → 2 full-width cards (Admissions, Pending
/// Refunds), consistent style — no mismatched card shapes.
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

  int _pendingPayments = 0;
  int _todayAppointments = 0;
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
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        _receptionistName = userDoc.data()?['name'] ?? 'Receptionist';
      }

      final paymentsSnap = await FirebaseFirestore.instance
          .collection('payments')
          .where('status', isEqualTo: 'Pending')
          .get();
      _pendingPayments = paymentsSnap.docs.length;

      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final slotsSnap = await FirebaseFirestore.instance
          .collection('slots')
          .where('date', isEqualTo: dateStr)
          .where('slotStatus', isEqualTo: 'BOOKED')
          .get();
      _todayAppointments = slotsSnap.docs.length;

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
                const SizedBox(height: 16),
                _buildStatChips(),
                const SizedBox(height: 20),
                const Text(
                  'Quick actions',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 10),
                _buildActionGrid(),
                const SizedBox(height: 10),
                _buildListCard(
                  icon: Icons.bed_outlined,
                  iconBg: const Color(0xFFEAE3F7),
                  iconColor: const Color(0xFF7E57C2),
                  title: 'Admissions',
                  subtitle: 'Assign and release beds',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdmissionsScreen(),
                      ),
                    );
                    _loadData();
                  },
                ),
                const SizedBox(height: 10),
                _buildListCard(
                  icon: Icons.currency_exchange_outlined,
                  iconBg: const Color(0xFFFDE6E0),
                  iconColor: const Color(0xFFD9534F),
                  title: 'Pending refunds',
                  subtitle: 'Pay and mark done',
                  badge: _pendingRefunds,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RefundsPendingScreen(),
                      ),
                    );
                    _loadData();
                  },
                ),
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
                const Text(
                  'Reception desk',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoading ? 'Loading...' : _receptionistName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Notification Bell
          // Uses the existing reusable NotificationBellIcon.
          // Unread notifications will show a red count badge.
          const NotificationBellIcon(
            iconColor: Colors.white,
            backgroundColor: Color(0x26FFFFFF),
            size: 20,
          ),

          const SizedBox(width: 10),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReceptionistProfileScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChips() {
    return Row(
      children: [
        _statChip(
          'Pending',
          _pendingPayments,
          const Color(0xFFB8860B),
        ),
        const SizedBox(width: 8),
        _statChip(
          'Today',
          _todayAppointments,
          _primary,
        ),
        const SizedBox(width: 8),
        _statChip(
          'Refunds',
          _pendingRefunds,
          const Color(0xFFD9534F),
        ),
      ],
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              _isLoading ? '—' : '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
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
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        _gridCard(
          icon: Icons.payments_outlined,
          iconBg: const Color(0xFFFCEFD8),
          iconColor: const Color(0xFFB8860B),
          title: 'Verify payments',
          subtitle: 'Confirm bookings',
          badge: _pendingPayments,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const VerifyPaymentsScreen(),
              ),
            );
            _loadData();
          },
        ),
        _gridCard(
          icon: Icons.event_note_outlined,
          iconBg: const Color(0xFFDCEFE9),
          iconColor: _primary,
          title: 'Appointments',
          subtitle: 'Check-in patients',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppointmentsTodayScreen(),
              ),
            );
            _loadData();
          },
        ),
        _gridCard(
          icon: Icons.person_add_alt_1_outlined,
          iconBg: const Color(0xFFEAE3F7),
          iconColor: const Color(0xFF7E57C2),
          title: 'Walk-in patient',
          subtitle: 'Register and book',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WalkInScreen(),
              ),
            );
            _loadData();
          },
        ),
        _gridCard(
          icon: Icons.science_outlined,
          iconBg: const Color(0xFFD9ECF8),
          iconColor: const Color(0xFF1565C0),
          title: 'Lab payments',
          subtitle: 'Collect and forward',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LabPaymentsScreen(),
              ),
            );
            _loadData();
          },
        ),
      ],
    );
  }

  Widget _gridCard({
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 18,
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9534F),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A2F3A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Full-width list-style card — Admissions + Pending Refunds share this
  // (consistent look, no mismatched shapes on the dashboard)
  Widget _buildListCard({
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2F3A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9534F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF9CA3AF),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}