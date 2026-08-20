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

/// ADMIN DASHBOARD — UI/UX redesign only, ALL logic unchanged.
///
/// Changes from before:
///  - No separate top AppBar (hospital name/logo removed) — single
///    gradient header card instead, matching Receptionist/Doctor style.
///  - Hamburger (opens Drawer) moved INSIDE the header card, left side.
///  - Bell icon moved INSIDE the header card, right side.
///  - 3-dot menu removed entirely (was non-functional).
///  - Bottom nav restyled to match the app-wide rounded/active-tab look
///    used elsewhere (Patient/Receptionist), same 3 items + same
///    navigation logic as before.
///  - Stat cards: same 4 values (_totalDoctors, _totalPatients,
///    _todayAppointments, _totalRevenue), same _loadStats() logic,
///    only the card's visual style updated to match Receptionist's
///    grid-card look (colored icon chip).
///  - Drawer: same items, same navigation, only re-themed to match
///    the app's green palette instead of the old teal.
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
  int _selectedIndex = 0;

  // Theme colors — matched to app-wide green (Receptionist/Doctor)
  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color primaryDark = Color(0xFF0D6B5A);
  static const Color bgColor = Color(0xFFF4F7F6);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadStats();
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
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThan: endOfDay)
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
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      drawer: _buildDrawer(),
      // No AppBar — header card inside the body carries menu/bell now
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          color: primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                const Text('Overview',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280))),
                const SizedBox(height: 10),
                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                            child:
                                CircularProgressIndicator(color: primaryColor)),
                      )
                    : GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.15,
                        children: [
                          _statCard(
                            title: 'Total doctors',
                            value: '$_totalDoctors',
                            icon: Icons.medical_services_outlined,
                            iconBg: const Color(0xFFD9ECF8),
                            iconColor: const Color(0xFF1565C0),
                          ),
                          _statCard(
                            title: 'Total patients',
                            value: '$_totalPatients',
                            icon: Icons.people_outline,
                            iconBg: const Color(0xFFDCEFE9),
                            iconColor: primaryColor,
                          ),
                          _statCard(
                            title: "Today's appointments",
                            value: '$_todayAppointments',
                            icon: Icons.calendar_today_outlined,
                            iconBg: const Color(0xFFFCEFD8),
                            iconColor: const Color(0xFFB8860B),
                          ),
                          _statCard(
                            title: 'Total revenue',
                            value: 'Rs ${_totalRevenue.toStringAsFixed(0)}',
                            icon: Icons.payments_outlined,
                            iconBg: const Color(0xFFFDE6E0),
                            iconColor: const Color(0xFFD9534F),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // Header card — replaces the old AppBar. Hamburger (left, opens
  // Drawer) + bell (right) live here now. Same _scaffoldKey.openDrawer()
  // call as before — only its visual position changed.
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryColor, primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Welcome back',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 4),
                Text('Admin',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Notifications coming soon'),
                backgroundColor: primaryColor,
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
        ],
      ),
    );
  }

  // Stat card — same 4 numeric values as before, re-styled to match
  // Receptionist's grid-card look (colored icon chip, not tinted card).
  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 2),
          Text(title,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
          );
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminProfileScreen()),
          );
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      backgroundColor: Colors.white,
      selectedItemColor: primaryColor,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.people_outline), label: 'Users'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }

  // ── DRAWER — same items, same navigation, re-themed colors only ──
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: primaryDark,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_hospital_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Family Well Care',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      Text('Hospital',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24),
            _drawerItem(
              icon: Icons.dashboard_rounded,
              title: 'Dashboard',
              onTap: () => Navigator.pop(context),
            ),
            _drawerItem(
              icon: Icons.business_rounded,
              title: 'Manage Departments',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ManageDepartmentsScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.attach_money_rounded,
              title: 'Manage Prices',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManagePricesScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.bed_rounded,
              title: 'Manage Rooms/Beds',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageRoomsScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.calendar_month_rounded,
              title: 'View Appointments',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ViewAppointmentsScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.biotech_rounded,
              title: 'View Lab Test Summary',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ViewLabTestSummaryScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.receipt_long_rounded,
              title: 'View Billing Records',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ViewPaymentRecordsScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.bar_chart_rounded,
              title: 'View Reports',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.star_rounded,
              title: 'View Feedback',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ViewFeedbackScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Icon(icon,
          color: isLogout ? Colors.red[300] : Colors.white, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? Colors.red[300] : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      horizontalTitleGap: 8,
    );
  }
}
