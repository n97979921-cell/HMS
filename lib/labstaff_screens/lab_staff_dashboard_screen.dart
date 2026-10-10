import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'lab_test_detail_screen.dart';
import 'lab_staff_profile_screen.dart';
import '../widgets/notification_bell_icon.dart';
import '../widgets/app_ui.dart';

/// LAB STAFF DASHBOARD — aaj/sab Confirmed tests dikhata hai
///
/// Sirf status: Ready | In Progress | Completed wale tests dikhte
/// hain (Pending abhi receptionist ke paas hai, patient ne pay nahi kiya).
///
/// Tabs: "Pending" (Confirmed — kaam shuru karna hai) |
///       "In Progress" (chal raha hai) |
///       "Completed" (report ban chuki)
///
///  REAL-TIME (Rule 2): Data `lab_tests` + `users` (patient/doctor
/// naam) se milkar banta hai, is liye poori screen StreamBuilder mein
/// convert NAHI ki. Iski jagah ek lightweight listener `lab_tests`
/// collection ko sunta hai (teeno relevant statuses ek sath —
/// Confirmed/In Progress/Completed), taake tab badalne par listener
/// dobara banane ki zaroorat na pade. Jab bhi kuch badle, purana
/// `_loadData()` khud-ba-khud dobara call ho jaata hai.
///
/// NAYA — DELETE (sirf "Completed" tab par):
///   - Har completed test card par ek chhota delete icon — us akele
///     test ka record permanent delete karta hai.
///   - "Delete All" button (Completed tab ke header mein, jab list
///     khali na ho) — us tab ke SAARE Completed records ek sath
///     permanent delete kar deta hai (batch write).
///   - Dono jagah koi confirmation dialog nahi — seedha delete, jaisa
///     request kiya gaya. Purana completed data halka rehta hai.
class LabStaffDashboardScreen extends StatefulWidget {
  const LabStaffDashboardScreen({super.key});

  @override
  State<LabStaffDashboardScreen> createState() =>
      _LabStaffDashboardScreenState();
}

class _LabStaffDashboardScreenState extends State<LabStaffDashboardScreen> {
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
        .where(
          'status',
          whereIn: ['Confirmed', 'In Progress', 'Completed'],
        )
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF9A2E16),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ── Delete ek test — bina confirmation ke seedha permanent delete ──
  Future<void> _deleteTest(String testId) async {
    try {
      await FirebaseFirestore.instance
          .collection('lab_tests')
          .doc(testId)
          .delete();
      _showSuccess('Test record deleted');
      // Real-time listener khud-ba-khud _loadData() call kar dega,
      // lekin turant feel ke liye yahan bhi rakh sakte hain.
      _loadData();
    } catch (e) {
      _showError('Error deleting: $e');
    }
  }

  // ── Delete All — sirf "Completed" tab ke saare records, ek batch
  //    write mein, bina confirmation ke ──
  Future<void> _deleteAllCompleted() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lab_tests')
          .where('status', isEqualTo: 'Completed')
          .get();

      if (snap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      _showSuccess('${snap.docs.length} completed record(s) deleted');
      _loadData();
    } catch (e) {
      _showError('Error deleting all: $e');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to continue.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB23A1E),
            ),
            child: const Text(
              'Log out',
              style: TextStyle(color: Colors.white),
            ),
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
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          if (_selectedTab == 'Completed' && !_isLoading && _tests.isNotEmpty)
            _buildDeleteAllBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal),
                  )
                : _tests.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppColors.teal,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              20, _selectedTab == 'Completed' ? 4 : 16, 20, 24),
                          itemCount: _tests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) => _card(_tests[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // Dark header: logo, "Welcome,", name, tagline, bell, profile button
  // + Ready / In Progress / Completed toggle (same actions as before)
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 50,
                      height: 50,
                      color: Colors.white,
                      child: Image.asset(
                        'assets/Logo.png',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.local_hospital,
                            color: AppColors.header,
                            size: 24,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome,',
                          style: TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _isLoading ? 'Loading...' : _staffName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Lab Test Management',
                          style: TextStyle(
                            color: AppColors.headerLabel,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Notification Bell (unread count automatic)
                  const NotificationBellIcon(
                    iconColor: Colors.white,
                    backgroundColor: Color(0x26FFFFFF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LabStaffProfileScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
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
              const SizedBox(height: 18),
              _buildTabToggle(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.header : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // "Delete All" — sirf Completed tab par, bina confirmation (pehle jaisa)
  Widget _buildDeleteAllBar() {
    final n = _tests.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$n completed record${n == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted),
            ),
          ),
          GestureDetector(
            onTap: _deleteAllCompleted,
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
                  Text('Delete All',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.science_outlined,
        title: 'No ${_selectedTab.toLowerCase()} tests',
      ),
    );
  }

  Widget _card(Map<String, dynamic> test) {
    final isCompleted = test['status'] == 'Completed';

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LabTestDetailScreen(
              testId: test['testId'],
            ),
          ),
        );

        if (result == true) _loadData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const AppIconTile(
              icon: Icons.science_outlined,
              color: AppColors.blue,
              background: AppColors.blueSoft,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test['patientName'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${test['testType']} · Dr. ${test['doctorName']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            // Individual delete — sirf Completed cards par (pehle jaisa)
            if (isCompleted) ...[
              const SizedBox(width: 6),
              AppDeleteButton(
                onTap: () => _deleteTest(test['testId']),
                size: 32,
              ),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.faint,
            ),
          ],
        ),
      ),
    );
  }
}
