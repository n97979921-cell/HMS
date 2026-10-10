import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'manage_users_screen.dart';
import 'manage_departments_screen.dart';
import 'package:hospital_management_app/screens/manage_prices_screen.dart';
import 'manage_rooms_screen.dart';
import 'view_appointments_screen.dart';
import 'view_lab_test_summary_screen.dart';
import 'view_payment_records_screen.dart';
import 'view_feedback_screen.dart';
import 'reports_screen.dart';
import 'admin_profile_screen.dart';
import '../widgets/app_ui.dart';
import 'package:intl/intl.dart';

/// ADMIN DASHBOARD — UI redesign only (Option B), ALL logic unchanged.
///
///  - Dark rounded header: menu button, logo, admin name, and the same
///    Total revenue value (_totalRevenue) shown large.
///  - Stats card: same _totalDoctors, _totalPatients, _todayAppointments.
///  - "Manage hospital" shortcuts open the SAME screens the drawer opens.
///  - Bottom nav: same 3 items, same onTap navigation.
///  - Drawer: same items + same navigation, grouped into sections.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _totalDoctors = 0;
  int _totalPatients = 0;
  int _todayAppointments = 0;
  double _totalRevenue = 0;
  bool _isLoading = true;

  // ── NAYA (sirf dikhane ke liye): Revenue chart — Daily / Monthly ──
  // Purana _loadStats() bilkul wahi hai; yeh alag read-only query hai.
  bool _revDaily = false;
  bool _revLoading = true;
  List<double> _revBars = [];
  List<String> _revLabels = [];
  double _revPeriodTotal = 0;
  int _selectedIndex = 0;

  // Logged-in admin name
  String _adminName = 'Admin';

  // Theme colors — matched to app-wide green (Receptionist/Doctor)
  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color primaryDark = Color(0xFF0D6B5A);
  static const Color bgColor = Color(0xFFF4F7F6);

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAdminName();
    _loadRevenueChart();
  }

  // ── LOAD LOGGED-IN ADMIN NAME ──
  Future<void> _loadAdminName() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) return;

      final userDoc = await _firestore.collection('users').doc(uid).get();

      if (!mounted) return;

      setState(() {
        _adminName = userDoc.data()?['name'] ?? 'Admin';
      });
    } catch (_) {
      // Keep default name as Admin if loading fails
    }
  }

  // ── UNCHANGED LOGIC ──
  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final doctors = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .where('status', isEqualTo: 'active')
          .get();

      final patients = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .where('status', isEqualTo: 'active')
          .get();

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final appointments = await _firestore
          .collection('appointments')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: startOfDay,
          )
          .where(
            'createdAt',
            isLessThan: endOfDay,
          )
          .get();

      final payments = await _firestore
          .collection('payments')
          .where('status', isEqualTo: 'Paid')
          .get();

      double revenue = 0;

      for (var doc in payments.docs) {
        revenue += (doc.data()['amount'] ?? 0).toDouble();
      }

      setState(() {
        _totalDoctors = doctors.docs.length;
        _totalPatients = patients.docs.length;
        _todayAppointments = appointments.docs.length;
        _totalRevenue = revenue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ── UNCHANGED LOGIC ──
  void _logout() async {
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
        (route) => false,
      );
    }
  }

  // ── NAYA: Revenue chart data (Paid payments) ──
  // Daily  = pichle 7 din (aaj tak), har din ka total.
  // Monthly = pichle 6 mahine (is mahine tak), har mahine ka total.
  Future<void> _loadRevenueChart() async {
    if (mounted) setState(() => _revLoading = true);
    try {
      final now = DateTime.now();
      final List<DateTime> starts = [];
      if (_revDaily) {
        final today = DateTime(now.year, now.month, now.day);
        for (int i = 6; i >= 0; i--) {
          starts.add(today.subtract(Duration(days: i)));
        }
      } else {
        for (int i = 5; i >= 0; i--) {
          starts.add(DateTime(now.year, now.month - i, 1));
        }
      }
      final rangeStart = starts.first;
      final rangeEnd = _revDaily
          ? starts.last.add(const Duration(days: 1))
          : DateTime(now.year, now.month + 1, 1);

      final snap = await _firestore
          .collection('payments')
          .where('status', isEqualTo: 'Paid')
          .where('createdAt', isGreaterThanOrEqualTo: rangeStart)
          .where('createdAt', isLessThan: rangeEnd)
          .get();

      final bars = List<double>.filled(starts.length, 0);
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['createdAt'];
        if (ts is! Timestamp) continue;
        final d = ts.toDate();
        int idx;
        if (_revDaily) {
          final day = DateTime(d.year, d.month, d.day);
          idx = starts.indexWhere((s) => s == day);
        } else {
          idx =
              starts.indexWhere((s) => s.year == d.year && s.month == d.month);
        }
        if (idx >= 0) bars[idx] += (data['amount'] ?? 0).toDouble();
      }

      if (!mounted) return;
      setState(() {
        _revBars = bars;
        _revLabels = starts
            .map((s) => _revDaily
                ? DateFormat('E').format(s)
                : DateFormat('MMM').format(s))
            .toList();
        _revPeriodTotal = bars.isEmpty ? 0 : bars.last;
        _revLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _revLoading = false);
    }
  }

  void _setRevMode(bool daily) {
    if (_revDaily == daily) return;
    setState(() => _revDaily = daily);
    _loadRevenueChart();
  }

  String _formatRs(double v) {
    return 'Rs ${NumberFormat.decimalPattern('en_IN').format(v.round())}';
  }

  // ── UI ONLY: shortcut list ka ek row ──
  void _open(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawer: _buildDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStats();
          await _loadRevenueChart();
        },
        color: AppColors.teal,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              // Stats card — header ke upar thora overlap karta hai
              Transform.translate(
                offset: const Offset(0, -34),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _isLoading
                      ? Container(
                          height: 92,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.teal,
                            ),
                          ),
                        )
                      : _buildStatsCard(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Manage hospital',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _scaffoldKey.currentState?.openDrawer(),
                          child: const Text(
                            'See all',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          _shortcutTile(
                            icon: Icons.people_outline_rounded,
                            color: AppColors.teal,
                            title: 'Users & invites',
                            subtitle: 'Doctors, staff, admins',
                            onTap: () => _open(const ManageUsersScreen()),
                          ),
                          _shortcutTile(
                            icon: Icons.calendar_month_rounded,
                            color: AppColors.blue,
                            title: 'Appointments',
                            subtitle: 'All bookings and status',
                            onTap: () => _open(const ViewAppointmentsScreen()),
                          ),
                          _shortcutTile(
                            icon: Icons.bed_rounded,
                            color: const Color(0xFF7E57C2),
                            title: 'Rooms & beds',
                            subtitle: 'Room types, rooms and beds',
                            onTap: () => _open(const ManageRoomsScreen()),
                          ),
                          _shortcutTile(
                            icon: Icons.bar_chart_rounded,
                            color: const Color(0xFF8A5A00),
                            title: 'Reports',
                            subtitle: 'Revenue, doctors, lab, beds',
                            onTap: () => _open(const ReportsScreen()),
                            isLast: true,
                          ),
                        ],
                      ),
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

  // Header — dark rounded block. Same hamburger → openDrawer().
  Widget _buildHeader() {
    final now = DateTime.now();
    final periodLabel = _revDaily
        ? 'Revenue · Today'
        : 'Revenue · ${DateFormat('MMMM yyyy').format(now)}';
    final maxBar =
        _revBars.isEmpty ? 0.0 : _revBars.reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 58),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppHeaderIconButton(
                    icon: Icons.menu_rounded,
                    tooltip: 'Menu',
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'FAMILY WELL CARE',
                          style: TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _adminName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Logo mark (same asset + crop as before)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Transform.scale(
                        scale: 1.6,
                        child: Image.asset(
                          'assets/Logo.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          periodLabel,
                          style: const TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _revLoading ? '—' : _formatRs(_revPeriodTotal),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLoading
                              ? ''
                              : 'All time: ${_formatRs(_totalRevenue)}',
                          style: const TextStyle(
                            color: AppColors.mint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        _revToggle('Daily', _revDaily, () => _setRevMode(true)),
                        _revToggle(
                            'Monthly', !_revDaily, () => _setRevMode(false)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 96,
                child: _revLoading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: AppColors.mint, strokeWidth: 2),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(_revBars.length, (i) {
                          final isLast = i == _revBars.length - 1;
                          final frac = maxBar <= 0 ? 0.0 : _revBars[i] / maxBar;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: 10 + 62 * frac,
                                    decoration: BoxDecoration(
                                      color: isLast
                                          ? AppColors.mint
                                          : Colors.white.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _revLabels[i],
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isLast
                                          ? Colors.white
                                          : AppColors.headerMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _revToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: active ? AppColors.header : Colors.white,
          ),
        ),
      ),
    );
  }

  // Stats — same 3 numeric values.
  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.header.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _statCard(title: 'Doctors', value: '$_totalDoctors'),
          _statDivider(),
          _statCard(title: 'Patients', value: '$_totalPatients'),
          _statDivider(),
          _statCard(title: "Today's visits", value: '$_todayAppointments'),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 1, height: 44, color: AppColors.divider);
  }

  Widget _statCard({
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            AppIconTile(icon: icon, color: color, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
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
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.muted, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManageUsersScreen(),
              ),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminProfileScreen(),
              ),
            );
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people_rounded),
            label: 'Users',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ── DRAWER — same items, same navigation, grouped + re-styled ──
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  // Hospital logo — same asset + crop as before
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Transform.scale(
                        scale: 1.6,
                        child: Image.asset(
                          'assets/Logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Family Well Care',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Hospital · Admin panel',
                          style: TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _drawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    selected: true,
                    onTap: () => Navigator.pop(context),
                  ),
                  _drawerSection('MANAGE'),
                  _drawerItem(
                    icon: Icons.business_rounded,
                    title: 'Departments',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ManageDepartmentsScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.sell_outlined,
                    title: 'Prices',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ManagePricesScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.bed_rounded,
                    title: 'Rooms & beds',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ManageRoomsScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerSection('RECORDS'),
                  _drawerItem(
                    icon: Icons.calendar_month_rounded,
                    title: 'Appointments',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViewAppointmentsScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.biotech_rounded,
                    title: 'Lab tests',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViewLabTestSummaryScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'Billing records',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViewPaymentRecordsScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerSection('INSIGHTS'),
                  _drawerItem(
                    icon: Icons.bar_chart_rounded,
                    title: 'Reports',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.star_rounded,
                    title: 'Feedback',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViewFeedbackScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            // Admin card (sirf naam dikhata hai)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.mint,
                    child: Text(
                      _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        color: AppColors.header,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _adminName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Admin',
                          style: TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.headerLabel,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLogout = false,
    bool selected = false,
  }) {
    final Color fg = isLogout
        ? const Color(0xFFFFB4A3)
        : selected
            ? AppColors.header
            : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.mint : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(icon, color: fg, size: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
