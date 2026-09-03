import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'lab_test_detail_screen.dart';
import 'lab_staff_profile_screen.dart';
import '../screens/notifications_screen.dart';

/// LAB STAFF DASHBOARD — aaj/sab Confirmed tests dikhata hai
///
/// Sirf status: Ready | In Progress | Completed wale tests dikhte
/// hain (Pending abhi receptionist ke paas hai, patient ne pay nahi kiya).
///
/// Tabs: "Pending" (Confirmed — kaam shuru karna hai) |
///       "In Progress" (chal raha hai) |
///       "Completed" (report ban chuki)
///
/// ✅ REAL-TIME (Rule 2): Data `lab_tests` + `users` (patient/doctor
/// naam) se milkar banta hai, is liye poori screen StreamBuilder mein
/// convert NAHI ki. Iski jagah ek lightweight listener `lab_tests`
/// collection ko sunta hai (teeno relevant statuses ek sath —
/// Confirmed/In Progress/Completed), taake tab badalne par listener
/// dobara banane ki zaroorat na pade. Jab bhi kuch badle, purana
/// `_loadData()` khud-ba-khud dobara call ho jaata hai.
class LabStaffDashboardScreen extends StatefulWidget {
  const LabStaffDashboardScreen({super.key});

  @override
  State<LabStaffDashboardScreen> createState() =>
      _LabStaffDashboardScreenState();
}

class _LabStaffDashboardScreenState extends State<LabStaffDashboardScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  String _staffName = '';
  bool _isLoading = true;
  String _selectedTab = 'Confirmed'; // Confirmed | In Progress | Completed

  List<Map<String, dynamic>> _tests = [];

  // Real-time listener — `lab_tests` collection ko sunta hai, teeno
  // relevant statuses ke sath ek sath (chahe kisi bhi tab pe ho,
  // koi bhi change ho to list refresh ho jaati hai).
  StreamSubscription<QuerySnapshot>? _labTestsSub;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _labTestsSub?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    // Pehla event hi initial load ka kaam kar deta hai, is liye alag
    // se _loadData() call karne ki zaroorat nahi.
    _labTestsSub = FirebaseFirestore.instance
        .collection('lab_tests')
        .where('status', whereIn: ['Confirmed', 'In Progress', 'Completed'])
        .snapshots()
        .listen((_) {
      _loadData();
    }, onError: (_) {
      setState(() => _isLoading = false);
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        _staffName = userDoc.data()?['name'] ?? 'Lab Staff';
      }

      final snap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('status', isEqualTo: _selectedTab)
          .get();

      final List<Map<String, dynamic>> result = [];
      for (final doc in snap.docs) {
        final data = doc.data();

        String patientName = 'Patient';
        String doctorName = '';
        try {
          final p = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['patientId'])
              .get();
          patientName = p.data()?['name'] ?? 'Patient';
          final d = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['doctorId'])
              .get();
          doctorName = d.data()?['name'] ?? '';
        } catch (_) {}

        result.add({
          'testId': doc.id,
          'patientName': patientName,
          'doctorName': doctorName,
          'testType': data['testType'] ?? '',
          'status': data['status'],
        });
      }

      if (!mounted) return;
      setState(() {
        _tests = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error loading tests: $e');
    }
  }

  void _changeTab(String tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
    _loadData();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabToggle(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _tests.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                            itemCount: _tests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => _card(_tests[i]),
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
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
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
                const Text('Welcome,',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _isLoading ? 'Loading...' : _staffName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text('Lab Test Management',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
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
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LabStaffProfileScreen()),
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

  Widget _buildTabToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          _tabButton('Ready', 'Confirmed'),
          _tabButton('In Progress', 'In Progress'),
          _tabButton('Completed', 'Completed'),
        ],
      ),
    );
  }

  // label = display text, value = actual status filter
  Widget _tabButton(String label, String value) {
    final isSelected = _selectedTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTab(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No ${_selectedTab.toLowerCase()} tests',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> test) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LabTestDetailScreen(testId: test['testId']),
          ),
        );
        if (result == true) _loadData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD9ECF8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.science_outlined,
                  color: Color(0xFF1565C0), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test['patientName'],
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2F3A))),
                  Text('${test['testType']} · Dr. ${test['doctorName']}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}