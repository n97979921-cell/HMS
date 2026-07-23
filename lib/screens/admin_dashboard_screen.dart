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

  // Theme Colors
  static const Color primaryColor = Color(0xFF0D6B6B);
  static const Color bgColor = Color(0xFFBDD8D8);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      // Total Doctors
      final doctors = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'doctor')
          .where('status', isEqualTo: 'active')
          .get();

      // Total Patients
      final patients = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .where('status', isEqualTo: 'active')
          .get();

      // Today's Appointments
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final appointments = await _firestore
          .collection('appointments')
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThan: endOfDay)
          .get();

      // Total Revenue
      final payments = await _firestore
          .collection('payments') // ← PAYMENTS naya
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
      // DRAWER (Sidebar)
      drawer: _buildDrawer(),
      // APP BAR
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_hospital_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              'Family Well Care',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: Colors.white, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: Colors.white, size: 24),
            onPressed: () {},
          ),
        ],
      ),
      // BODY
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back!',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Dashboard Title
              const Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2F5A),
                ),
              ),
              const Text(
                'Family Well Care Hospital',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5A7A7A),
                ),
              ),

              const SizedBox(height: 16),

              // Stats Cards Grid
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: primaryColor))
                  : GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.4,
                      children: [
                        _statCard(
                          title: 'Total Doctors',
                          value: '$_totalDoctors',
                          icon: Icons.medical_services_rounded,
                          color: const Color(0xFF1A73E8),
                        ),
                        _statCard(
                          title: 'Total Patients',
                          value: '$_totalPatients',
                          icon: Icons.people_rounded,
                          color: const Color(0xFF0F9D58),
                        ),
                        _statCard(
                          title: "Today's Appointments",
                          value: '$_todayAppointments',
                          icon: Icons.calendar_today_rounded,
                          color: const Color(0xFFF4B400),
                        ),
                        _statCard(
                          title: 'Total Revenue',
                          value: 'Rs ${_totalRevenue.toStringAsFixed(0)}',
                          icon: Icons.attach_money_rounded,
                          color: const Color(0xFFDB4437),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
      // BOTTOM NAV BAR
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
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
          }
        },
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_rounded),
            label: 'Users',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // DRAWER WIDGET
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: primaryColor,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_hospital_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Family Well Care',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Hospital',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white24),

            // Menu Items
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

            const Spacer(),
            const Divider(color: Colors.white24),

            // Logout
            _drawerItem(
              icon: Icons.logout_rounded,
              title: 'Logout',
              onTap: _logout,
              isLogout: true,
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

  // STAT CARD WIDGET
  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2F5A),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF5A7A7A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
