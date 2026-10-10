import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

class ViewLabTestSummaryScreen extends StatefulWidget {
  const ViewLabTestSummaryScreen({super.key});

  @override
  State<ViewLabTestSummaryScreen> createState() =>
      _ViewLabTestSummaryScreenState();
}

class _ViewLabTestSummaryScreenState extends State<ViewLabTestSummaryScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

  final Map<String, String> _userNameCache = {};

  String _statusFilter = 'All';

  static const List<String> _statusOptions = [
    'All',
    'Pending',
    'In Progress',
    'Completed',
    'Cancelled',
  ];

  // orderBy('createdAt') hata diya — status filter ke saath combine
  // hoke yeh Firestore composite index maangta tha (cloud_firestore/
  // failed-precondition error). Ab sirf 'where' lagta hai (single-field,
  // index ki zaroorat nahi), aur sorting neeche client-side (Dart mein)
  // ho rahi hai.
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('lab_tests');

    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    return query;
  }

  // Newest first — createdAt Timestamp ke hisaab se, client-side.
  void _sortByCreatedAtDesc(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    docs.sort((a, b) {
      final aTs = a.data()['createdAt'];
      final bTs = b.data()['createdAt'];
      if (aTs is! Timestamp || bTs is! Timestamp) return 0;
      return bTs.compareTo(aTs);
    });
  }

  Future<String> _getUserName(String? userId) async {
    if (userId == null || userId.isEmpty) return 'N/A';
    if (_userNameCache.containsKey(userId)) {
      return _userNameCache[userId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final name = doc.exists ? (doc.data()?['name'] ?? 'Unknown') : 'Unknown';
      _userNameCache[userId] = name;
      return name;
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<List<Map<String, dynamic>>> _enrichWithNames(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final List<Map<String, dynamic>> results = [];
    for (final doc in docs) {
      final data = doc.data();
      final patientName = await _getUserName(data['patientId']);
      final doctorName = await _getUserName(data['doctorId']);
      results.add({
        'id': doc.id,
        ...data,
        'patientName': patientName,
        'doctorName': doctorName,
      });
    }
    return results;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFF4B400);
      case 'In Progress':
        return const Color(0xFF1A73E8);
      case 'Completed':
        return const Color(0xFF0F9D58);
      case 'Cancelled':
        return const Color(0xFFDB4437);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Pending':
        return Icons.hourglass_empty_rounded;
      case 'In Progress':
        return Icons.science_outlined;
      case 'Completed':
        return Icons.check_circle_outline_rounded;
      case 'Cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline_rounded;
    }
  }

  // ── NAYA: Delete (single) — koi confirmation nahi, seedha permanent
  //    delete. Har card ke top par icon hamesha available, status se
  //    qata-nazar. StreamBuilder khud-ba-khud list refresh kar dega.
  Future<void> _deleteTest(BuildContext context, String id) async {
    try {
      await FirebaseFirestore.instance.collection('lab_tests').doc(id).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lab test deleted'),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting: $e'),
          backgroundColor: const Color(0xFFDB4437),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── NAYA: Delete All — jo bhi lab tests is waqt screen par (currently
  //    applied status filter ke baad) dikh rahe hain, sab ek batch write
  //    mein permanent delete — bina confirmation ke.
  Future<void> _deleteAllTests(
      BuildContext context, List<Map<String, dynamic>> tests) async {
    if (tests.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final t in tests) {
        batch.delete(
            FirebaseFirestore.instance.collection('lab_tests').doc(t['id']));
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tests.length} lab test(s) deleted'),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting all: $e'),
          backgroundColor: const Color(0xFFDB4437),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  AppChipColors _chipColors(String status) {
    switch (status) {
      case 'Pending':
        return AppChipColors.yellow;
      case 'In Progress':
        return AppChipColors.blue;
      case 'Completed':
        return AppChipColors.green;
      case 'Cancelled':
        return AppChipColors.red;
      default:
        return AppChipColors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          AppHeader(
            title: 'Lab test summary',
            subtitle: 'All tests ordered by doctors',
            // Status filter
            bottom: Row(
              children: [
                Expanded(
                  child: AppHeaderDropdown(
                    label: 'Status',
                    value: _statusFilter,
                    options: _statusOptions,
                    displayOf: (o) => o == 'All' ? 'All statuses' : o,
                    dotColorOf: (o) =>
                        o == 'All' ? AppColors.faint : _statusColor(o),
                    onChanged: (v) {
                      setState(() => _statusFilter = v);
                    },
                  ),
                ),
                if (_statusFilter != 'All') ...[
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFFFFB4A3).withOpacity(0.16),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _statusFilter = 'All'),
                      child: const SizedBox(
                        width: 54,
                        height: 54,
                        child: Icon(Icons.close_rounded,
                            color: Color(0xFFFFB4A3), size: 20),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Real-time stream of lab tests based on current filter.
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Error loading lab tests: ${snapshot.error}',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.teal));
                }

                final docs = snapshot.data?.docs ?? [];
                _sortByCreatedAtDesc(docs);

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _enrichWithNames(docs),
                  builder: (context, nameSnapshot) {
                    if (nameSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: AppColors.teal));
                    }

                    final tests = nameSnapshot.data ?? [];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${tests.length} lab test${tests.length == 1 ? '' : 's'} found',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.teal,
                                  ),
                                ),
                              ),
                              if (tests.isNotEmpty)
                                AppDeleteAllButton(
                                  onTap: () => _deleteAllTests(context, tests),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: tests.isEmpty
                              ? ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: const [
                                    AppEmptyState(
                                      icon: Icons.biotech_outlined,
                                      title: 'No lab tests found',
                                      subtitle: 'Try a different status filter',
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                  itemCount: tests.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final test = tests[index];
                                    final status = test['status'] ?? 'Unknown';
                                    return _LabTestCard(
                                      test: test,
                                      chipColors: _chipColors(status),
                                      onDelete: () =>
                                          _deleteTest(context, test['id']),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LabTestCard extends StatelessWidget {
  final Map<String, dynamic> test;
  final AppChipColors chipColors;
  final VoidCallback onDelete;

  const _LabTestCard({
    required this.test,
    required this.chipColors,
    required this.onDelete,
  });

  String _formatDate(dynamic ts) {
    if (ts == null) return 'N/A';
    try {
      final date = (ts as Timestamp).toDate();
      return DateFormat('MMM d, yyyy \u2022 h:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = test['status'] ?? 'Unknown';
    final paymentStatus = test['paymentStatus']; // null or 'Paid'
    final charge = test['charge'];
    final isPaid = paymentStatus == 'Paid';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: test type + status + delete
          Row(
            children: [
              const AppIconTile(
                icon: Icons.biotech_outlined,
                color: AppColors.blue,
                background: AppColors.blueSoft,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  test['testType'] ?? 'Unknown Test',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppStatusChip(label: status, colors: chipColors),
              const SizedBox(width: 8),
              AppDeleteButton(size: 34, onTap: onDelete),
            ],
          ),
          const SizedBox(height: 12),
          AppInfoRow(label: 'Patient', value: test['patientName'] ?? 'N/A'),
          AppInfoRow(label: 'Doctor', value: test['doctorName'] ?? 'N/A'),
          AppInfoRow(label: 'Ordered', value: _formatDate(test['createdAt'])),
          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),
          // Bottom row: charge + payment status
          Row(
            children: [
              if (charge != null)
                Text(
                  'Rs $charge',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B5E57),
                  ),
                ),
              const Spacer(),
              AppStatusChip(
                label: isPaid ? 'Paid' : 'Payment pending',
                colors: isPaid ? AppChipColors.green : AppChipColors.yellow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
