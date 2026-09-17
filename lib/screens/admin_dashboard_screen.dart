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
///  - 3-dot menu removed entirely (was non-functional).
///  - Bottom nav restyled to match the app-wide rounded/active-tab look
///    used elsewhere (Patient/Receptionist), same 3 items + same
///    navigation logic as before.
///  - Stat cards: same 4 values (_totalDoctors, _totalPatients,
///    _todayAppointments, _totalRevenue), same _loadStats() logic.
///    Style updated to match the Patient dashboard's full-colour
///    card look (whole card tinted, icon in a small white chip)
///    instead of a white card with just a coloured icon chip.
///  - Drawer: same items, same navigation, only re-themed to match
///    the app's green palette instead of the old teal.
///  - Header: compact bar, no gradient — bigger circular logo mark
///    (assets/Logo.png) next to the hamburger, and a role tag
///    ("Admin") shown under the name.
///  - ✅ REMOVED: notification bell icon — admin doesn't receive
///    notifications, so it's taken out of the header entirely.
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
  }

  // ── LOAD LOGGED-IN ADMIN NAME ──
  Future<void> _loadAdminName() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) return;

      final userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      drawer: _buildDrawer(),

      // No AppBar — header card inside the body carries the menu now
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

                const Text(
                  'Overview',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 10),

                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: primaryColor,
                          ),
                        ),
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
                            cardColor: const Color(0xFFD9ECF8),
                            iconColor: const Color(0xFF1565C0),
                          ),

                          _statCard(
                            title: 'Total patients',
                            value: '$_totalPatients',
                            icon: Icons.people_outline,
                            cardColor: const Color(0xFFE3DFF5),
                            iconColor: const Color(0xFF7E57C2),
                          ),

                          _statCard(
                            title: "Today's appointments",
                            value: '$_todayAppointments',
                            icon: Icons.calendar_today_outlined,
                            cardColor: const Color(0xFFFDE6E0),
                            iconColor: const Color(0xFFD9534F),
                          ),

                          _statCard(
                            title: 'Total revenue',
                            value:
                                'Rs ${_totalRevenue.toStringAsFixed(0)}',
                            icon: Icons.payments_outlined,
                            cardColor: const Color(0xFFFCEFD8),
                            iconColor: const Color(0xFFB8860B),
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

  // Header — compact bar, no gradient (solid primaryDark), bigger
  // circular logo mark (assets/Logo.png) next to the hamburger, name
  // + role tag ("Admin") stacked. Same hamburger → openDrawer() as
  // before — only the visual style changed, and the bell icon has
  // been removed (admin doesn't receive notifications).
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: primaryDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Hamburger — no permanent circle background.
          // Circle only appears as a ripple while pressed.
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.menu_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Logo mark — enlarged. The source asset has its own
          // built-in white margin around the FWC mark, which was
          // showing as a double ring alongside the container's white
          // backing. Scaling the image up inside the clip crops that
          // baked-in whitespace away so only the FWC circle shows.
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
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _adminName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 2),

                // Role tag — always "Admin" on this dashboard.
                const Text(
                  'Admin',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Stat card — same 4 numeric values as before, re-styled to match
  // the Patient dashboard's full-colour card look: the whole card is
  // tinted with `cardColor`, and the icon sits in a small white chip
  // on top instead of a white card with just a coloured icon chip.
  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color cardColor,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: iconColor,
              size: 16,
            ),
          ),

          const Spacer(),

          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2F3A),
            ),
          ),

          const SizedBox(height: 2),

          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF5B6B76),
            ),
          ),
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
      backgroundColor: Colors.white,
      selectedItemColor: primaryColor,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          label: 'Users',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
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
                  // Hospital logo — enlarged, with a solid white
                  // backing. The asset's own baked-in white margin is
                  // cropped out with a scale-up inside the clip (same
                  // fix as the header logo) so no double ring shows.
                  Container(
                    width: 64,
                    height: 64,
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

                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Family Well Care',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Hospital',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
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
                    builder: (_) => const ManageDepartmentsScreen(),
                  ),
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
                  MaterialPageRoute(
                    builder: (_) => const ManagePricesScreen(),
                  ),
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
                  MaterialPageRoute(
                    builder: (_) => const ManageRoomsScreen(),
                  ),
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
                    builder: (_) => const ViewAppointmentsScreen(),
                  ),
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
                    builder: (_) => const ViewLabTestSummaryScreen(),
                  ),
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
                    builder: (_) => const ViewPaymentRecordsScreen(),
                  ),
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
                  MaterialPageRoute(
                    builder: (_) => const ReportsScreen(),
                  ),
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
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isLogout ? Colors.red[300] : Colors.white,
        size: 22,
      ),
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