import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ViewLabTestSummaryScreen extends StatefulWidget {
  const ViewLabTestSummaryScreen({super.key});

  @override
  State<ViewLabTestSummaryScreen> createState() =>
      _ViewLabTestSummaryScreenState();
}

class _ViewLabTestSummaryScreenState extends State<ViewLabTestSummaryScreen> {
  static const Color _primary = Color(0xFF0D6B6B);
  static const Color _bg = Color(0xFFF5F7FA);

  final Map<String, String> _userNameCache = {};

  String _statusFilter = 'All';

  static const List<String> _statusOptions = [
    'All',
    'Pending',
    'In Progress',
    'Completed',
    'Cancelled',
  ];

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('lab_tests');

    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    return query.orderBy('createdAt', descending: true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'View Lab Test Summary',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          // Status filter
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: _DropdownFilter(
                    label: 'Status',
                    value: _statusFilter,
                    options: _statusOptions,
                    color: _primary,
                    onChanged: (v) {
                      setState(() => _statusFilter = v);
                    },
                  ),
                ),
                if (_statusFilter != 'All') ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => setState(() => _statusFilter = 'All'),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDB4437).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: Color(0xFFDB4437)),
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
                          color: const Color(0xFFDB4437).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Error loading lab tests: ${snapshot.error}',
                          style: const TextStyle(
                            color: Color(0xFFDB4437),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _primary));
                }

                final docs = snapshot.data?.docs ?? [];

                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _enrichWithNames(docs),
                  builder: (context, nameSnapshot) {
                    if (nameSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: _primary));
                    }

                    final tests = nameSnapshot.data ?? [];

                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFEFF6F6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            '${tests.length} lab test${tests.length == 1 ? '' : 's'} found',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: tests.isEmpty
                              ? ListView(
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.55,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.biotech_outlined,
                                                size: 64,
                                                color:
                                                    _primary.withOpacity(0.3)),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'No lab tests found',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Try a different status filter',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF9CA3AF)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: tests.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final test = tests[index];
                                    final status = test['status'] ?? 'Unknown';
                                    return _LabTestCard(
                                      test: test,
                                      statusColor: _statusColor(status),
                                      statusIcon: _statusIcon(status),
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

class _DropdownFilter extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final Color color;
  final ValueChanged<String> onChanged;

  const _DropdownFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = value != 'All';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.1) : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? color : const Color(0xFFE5E7EB),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: isActive ? color : const Color(0xFF6B7280), size: 18),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isActive ? color : const Color(0xFF6B7280),
          ),
          items: options.map((opt) {
            final display = opt == 'All' ? '$label: All' : opt;
            return DropdownMenuItem(
              value: opt,
              child: Text(display, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _LabTestCard extends StatelessWidget {
  final Map<String, dynamic> test;
  final Color statusColor;
  final IconData statusIcon;

  const _LabTestCard({
    required this.test,
    required this.statusColor,
    required this.statusIcon,
  });

  static const Color _primary = Color(0xFF0D6B6B);

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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: test type + status
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.biotech_outlined,
                          color: _primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        test['testType'] ?? 'Unknown Test',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Patient row
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              const Text(
                'Patient: ',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              Expanded(
                child: Text(
                  test['patientName'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Doctor row
          Row(
            children: [
              const Icon(Icons.medical_services_outlined,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              const Text(
                'Doctor: ',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              Expanded(
                child: Text(
                  test['doctorName'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Date row
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Text(
                _formatDate(test['createdAt']),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom row: charge + payment status
          Row(
            children: [
              if (charge != null) ...[
                const Icon(Icons.payments_outlined,
                    size: 16, color: Color(0xFF0F9D58)),
                const SizedBox(width: 6),
                Text(
                  'Rs. $charge',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F9D58),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: paymentStatus == 'Paid'
                      ? const Color(0xFF0F9D58).withOpacity(0.1)
                      : const Color(0xFFF4B400).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  paymentStatus == 'Paid' ? 'Paid' : 'Payment Pending',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: paymentStatus == 'Paid'
                        ? const Color(0xFF0F9D58)
                        : const Color(0xFFF4B400),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
