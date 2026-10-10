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
import '../widgets/app_ui.dart';
import 'package:intl/intl.dart';

/// RECEPTIONIST DASHBOARD — professional layout
///
/// Header (compact bar, logo + name/role + bell) → compact stat-chip row
/// (Pending / Today / Refunds) → 2-item quick-action grid (Verify
/// Payments, Lab Payments) → 2 full-width cards (Admissions, Pending
/// Refunds) → bottom nav bar (Home, Appointments, Walk-in, Profile).
///
///  UI-ONLY CHANGE: Saare "Quick action" style cards (Verify
/// payments, Lab payments, Admissions, Pending refunds) ab EK JAISE
/// full-color tinted background use karte hain (jaisa Patient
/// dashboard ke "Our services" cards mein hai) — pehle sirf upar
/// wale 2 grid-cards rangeen the, neeche wale 2 list-cards plain
/// white the sirf icon-chip rangeen thi. Koi logic, koi navigation,
/// koi data change nahi hua — sirf colors/background style.
///
/// ✅ UI-ONLY CHANGE: Header ab compact bar style mein hai — gradient
/// ki jagah solid color, aur left side pe app logo (Logo.png) hai
/// (is screen pe sidebar nahi hai isliye hamburger icon nahi laga),
/// name k neechay "Receptionist" role tag add kiya gaya hai. Bell
/// icon aur uska logic bilkul waisa hi hai.
class ReceptionistDashboardScreen extends StatefulWidget {
  const ReceptionistDashboardScreen({super.key});

  @override
  State<ReceptionistDashboardScreen> createState() =>
      _ReceptionistDashboardScreenState();
}

class _ReceptionistDashboardScreenState
    extends State<ReceptionistDashboardScreen> {
  String _receptionistName = '';
  bool _isLoading = true;

  int _pendingPayments = 0;
  int _todayAppointments = 0;
  int _pendingRefunds = 0;

  int _selectedIndex = 0;

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

  // ── Navigation helpers (same push + reload as before) ──
  Future<void> _openVerify() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerifyPaymentsScreen()),
    );
    _loadData();
  }

  Future<void> _openLab() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LabPaymentsScreen()),
    );
    _loadData();
  }

  Future<void> _openAdmissions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdmissionsScreen()),
    );
    _loadData();
  }

  Future<void> _openRefunds() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RefundsPendingScreen()),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.teal,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Quick actions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _gridCard(
                            icon: Icons.payments_outlined,
                            tint: const Color(0xFFF6F2E2),
                            iconColor: const Color(0xFF8A6D00),
                            title: 'Verify payments',
                            subtitle: 'Review screenshots',
                            badge: _pendingPayments,
                            onTap: _openVerify,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _gridCard(
                            icon: Icons.science_outlined,
                            tint: AppColors.blueSoft,
                            iconColor: AppColors.blue,
                            title: 'Lab payments',
                            subtitle: 'Collect and forward',
                            onTap: _openLab,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildListCard(
                      icon: Icons.bed_outlined,
                      tint: const Color(0xFFEEE8FB),
                      iconColor: const Color(0xFF5B3FA8),
                      title: 'Admissions',
                      subtitle: 'Assign and release beds',
                      onTap: _openAdmissions,
                    ),
                    const SizedBox(height: 12),
                    _buildListCard(
                      icon: Icons.currency_exchange_outlined,
                      tint: const Color(0xFFFBE6E0),
                      iconColor: const Color(0xFF9A2E16),
                      title: 'Pending refunds',
                      subtitle: 'Pay and mark done',
                      badge: _pendingRefunds,
                      onTap: _openRefunds,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // Dark header: logo + date/name + bell, then 3 stat tiles.
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Transform.scale(
                        scale: 1.6,
                        child: Image.asset(
                          'assets/Logo.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.local_hospital,
                              color: AppColors.header,
                              size: 22,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Front desk · ${DateFormat('EEE, d MMM').format(DateTime.now())}',
                          style: const TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLoading ? 'Loading...' : _receptionistName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification Bell (same reusable widget + logic)
                  const NotificationBellIcon(
                    iconColor: Colors.white,
                    backgroundColor: Color(0x14FFFFFF),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _statChip('Pending', _pendingPayments, AppColors.star),
                  const SizedBox(width: 8),
                  _statChip('Today', _todayAppointments, AppColors.mint),
                  const SizedBox(width: 8),
                  _statChip(
                      'Refunds', _pendingRefunds, const Color(0xFFFFB4A3)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isLoading ? '—' : '$count',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.headerMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF9A2E16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _gridCard({
    required IconData icon,
    required Color tint,
    required Color iconColor,
    required String title,
    required String subtitle,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppIconTile(
                    icon: icon, color: iconColor, background: tint, size: 44),
                if (badge > 0) _badge(badge),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard({
    required IconData icon,
    required Color tint,
    required Color iconColor,
    required String title,
    required String subtitle,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AppIconTile(icon: icon, color: iconColor, background: tint),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (badge > 0) ...[_badge(badge), const SizedBox(width: 6)],
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.faint, size: 22),
        ],
      ),
    );
  }

  // Bottom nav — Home / Appointments / Walk-in / Profile.
  // "Payments" ab yahan nahi (Quick actions grid mein move ho gaya),
  // is ki jagah "Walk-in" tab yahan aa gaya hai.
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
          if (index == 0) {
            setState(() => _selectedIndex = 0);
            return;
          }
          if (index == 1) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AppointmentsTodayScreen(),
              ),
            );
          } else if (index == 2) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WalkInScreen(),
              ),
            );
          } else if (index == 3) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReceptionistProfileScreen(),
              ),
            );
          }
          setState(() => _selectedIndex = 0);
          _loadData();
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.event_note_outlined),
              activeIcon: Icon(Icons.event_note_rounded),
              label: 'Appointments'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_add_alt_1_outlined),
              activeIcon: Icon(Icons.person_add_alt_1_rounded),
              label: 'Walk-in'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile'),
        ],
      ),
    );
  }
}
