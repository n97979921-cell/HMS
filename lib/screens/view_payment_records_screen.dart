import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

class ViewPaymentRecordsScreen extends StatefulWidget {
  const ViewPaymentRecordsScreen({super.key});

  @override
  State<ViewPaymentRecordsScreen> createState() =>
      _ViewPaymentRecordsScreenState();
}

class _ViewPaymentRecordsScreenState extends State<ViewPaymentRecordsScreen> {
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

  final Map<String, String> _userNameCache = {};

  String _typeFilter = 'All';
  String _statusFilter = 'All';

  static const List<String> _typeOptions = [
    'All',
    'Consultation',
    'Lab',
    'Room',
  ];

  static const List<String> _statusOptions = [
    'All',
    'Pending',
    'Paid',
    'Refunded',
    'HalfRefunded',
    'Rejected',
    'Cancelled',
  ];

  // No where() filters here — filtering happens client-side after
  // grouping, since a filter should highlight matches within a group
  // rather than break appointments apart.
  Query<Map<String, dynamic>> _buildQuery() {
    return FirebaseFirestore.instance
        .collection('payments')
        .orderBy('createdAt', descending: true);
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

  // Groups raw payment docs by appointmentId, resolves the patient
  // name once per group, and figures out which payments in each
  // group match the active filters (for highlighting).
  Future<List<_PaymentGroup>> _buildGroups(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final doc in docs) {
      final data = doc.data();
      final apptId = data['appointmentId'] ?? 'unknown_${doc.id}';
      grouped.putIfAbsent(apptId, () => []).add({'id': doc.id, ...data});
    }

    final List<_PaymentGroup> groups = [];

    for (final entry in grouped.entries) {
      final payments = entry.value;
      final patientId = payments.first['patientId'];
      final patientName = await _getUserName(patientId);

      // Does this group have at least one payment matching filters?
      final matchingPayments = payments.where((p) {
        final typeMatch = _typeFilter == 'All' || p['type'] == _typeFilter;
        final statusMatch =
            _statusFilter == 'All' || p['status'] == _statusFilter;
        return typeMatch && statusMatch;
      }).toList();

      // Skip the whole group only if filters are active AND nothing
      // in this group matches them.
      final filtersActive = _typeFilter != 'All' || _statusFilter != 'All';
      if (filtersActive && matchingPayments.isEmpty) continue;

      // Sort payments within group: Consultation, Lab, Room
      payments.sort((a, b) {
        const order = {'Consultation': 0, 'Lab': 1, 'Room': 2};
        return (order[a['type']] ?? 99).compareTo(order[b['type']] ?? 99);
      });

      groups.add(_PaymentGroup(
        appointmentId: entry.key,
        patientName: patientName,
        payments: payments,
        matchingIds: matchingPayments.map((p) => p['id'] as String).toSet(),
      ));
    }

    // Sort groups by most recent payment first
    groups.sort((a, b) {
      final aTime = a.payments.first['createdAt'] as Timestamp?;
      final bTime = b.payments.first['createdAt'] as Timestamp?;
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });

    return groups;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFF4B400);
      case 'Paid':
        return const Color(0xFF0F9D58);
      case 'Refunded':
        return const Color(0xFF1A73E8);
      case 'HalfRefunded':
        return const Color(0xFF7C4DFF);
      case 'Rejected':
        return const Color(0xFFDB4437);
      case 'Cancelled':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'HalfRefunded':
        return 'Half Refunded';
      default:
        return status;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Consultation':
        return Icons.medical_services_outlined;
      case 'Lab':
        return Icons.biotech_outlined;
      case 'Room':
        return Icons.bed_outlined;
      default:
        return Icons.payments_outlined;
    }
  }

  // ── NAYA: Delete (single payment line) — koi confirmation nahi,
  //    seedha permanent delete. StreamBuilder khud-ba-khud refresh
  //    kar dega.
  Future<void> _deletePayment(BuildContext context, String id) async {
    try {
      await FirebaseFirestore.instance.collection('payments').doc(id).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment record deleted'),
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

  // ── NAYA: Delete All — jo bhi groups is waqt screen par (currently
  //    applied type/status filters ke baad) dikh rahe hain, un sab
  //    groups ki SAARI payment lines ek batch write mein permanent
  //    delete — bina confirmation ke.
  Future<void> _deleteAllPayments(
      BuildContext context, List<_PaymentGroup> groups) async {
    if (groups.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (final g in groups) {
        for (final p in g.payments) {
          batch.delete(
              FirebaseFirestore.instance.collection('payments').doc(p['id']));
          count++;
        }
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count payment record(s) deleted'),
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

  // Type ke hisaab se chhota rang wala dot (sirf design).
  Color _typeColor(String type) {
    switch (type) {
      case 'Consultation':
        return AppColors.teal;
      case 'Lab':
        return AppColors.blue;
      case 'Room':
        return const Color(0xFF8A5A00);
      default:
        return AppColors.faint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = _typeFilter != 'All' || _statusFilter != 'All';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Filters section
          AppHeader(
            title: 'Billing records',
            subtitle: 'Grouped by appointment',
            bottom: Row(
              children: [
                Expanded(
                  child: AppHeaderDropdown(
                    label: 'Type',
                    value: _typeFilter,
                    options: _typeOptions,
                    displayOf: (o) => o == 'All' ? 'All types' : o,
                    dotColorOf: _typeColor,
                    onChanged: (v) {
                      setState(() => _typeFilter = v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppHeaderDropdown(
                    label: 'Status',
                    value: _statusFilter,
                    options: _statusOptions,
                    displayOf: (o) =>
                        o == 'All' ? 'All statuses' : _statusLabel(o),
                    dotColorOf: (o) =>
                        o == 'All' ? AppColors.faint : _statusColor(o),
                    onChanged: (v) {
                      setState(() => _statusFilter = v);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Real-time stream of payments, grouped by appointment.
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
                          'Error loading payments: ${snapshot.error}',
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

                return FutureBuilder<List<_PaymentGroup>>(
                  future: _buildGroups(docs),
                  builder: (context, groupSnapshot) {
                    if (groupSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: AppColors.teal));
                    }

                    final groups = groupSnapshot.data ?? [];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Column(
                            children: [
                              if (hasActiveFilters) ...[
                                AppInfoNote(
                                  text:
                                      'Showing full appointment bills that have a matching payment',
                                  trailing: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setState(() {
                                          _typeFilter = 'All';
                                          _statusFilter = 'All';
                                        });
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        child: Text(
                                          'Clear',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${groups.length} appointment bill${groups.length == 1 ? '' : 's'} found',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.teal,
                                      ),
                                    ),
                                  ),
                                  if (groups.isNotEmpty)
                                    AppDeleteAllButton(
                                      onTap: () =>
                                          _deleteAllPayments(context, groups),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: groups.isEmpty
                              ? ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: const [
                                    AppEmptyState(
                                      icon: Icons.receipt_long_outlined,
                                      title: 'No payment records found',
                                      subtitle: 'Try adjusting your filters',
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                  itemCount: groups.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final group = groups[index];
                                    return _PaymentGroupCard(
                                      group: group,
                                      filtersActive: hasActiveFilters,
                                      statusColor: _statusColor,
                                      statusLabel: _statusLabel,
                                      typeColor: _typeColor,
                                      // Ek bill = ek delete. Wahi purana
                                      // _deleteAllPayments function, sirf
                                      // is ek bill ke saath.
                                      onDeleteBill: () =>
                                          _deleteAllPayments(context, [group]),
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

class _PaymentGroup {
  final String appointmentId;
  final String patientName;
  final List<Map<String, dynamic>> payments;
  final Set<String> matchingIds;

  _PaymentGroup({
    required this.appointmentId,
    required this.patientName,
    required this.payments,
    required this.matchingIds,
  });

  num get total {
    num sum = 0;
    for (final p in payments) {
      sum += (p['amount'] ?? 0) as num;
    }
    return sum;
  }
}

class _PaymentGroupCard extends StatelessWidget {
  final _PaymentGroup group;
  final bool filtersActive;
  final Color Function(String) statusColor;
  final String Function(String) statusLabel;
  final Color Function(String) typeColor;
  final VoidCallback onDeleteBill;

  const _PaymentGroupCard({
    required this.group,
    required this.filtersActive,
    required this.statusColor,
    required this.statusLabel,
    required this.typeColor,
    required this.onDeleteBill,
  });

  String _formatDate(dynamic ts) {
    if (ts == null) return 'N/A';
    try {
      final date = (ts as Timestamp).toDate();
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = group.payments.length;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: patient name + date | total + delete
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.patientName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(group.payments.first['createdAt'])} · $count payment${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.faint,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.faint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs ${group.total}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              AppDeleteButton(
                tooltip: 'Delete this bill',
                onTap: onDeleteBill,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Each payment line within the group
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (int i = 0; i < group.payments.length; i++)
                  _line(group.payments[i], i == 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(Map<String, dynamic> p, bool isFirst) {
    final isHighlighted = group.matchingIds.contains(p['id']);
    final type = p['type'] ?? 'Unknown';
    final status = p['status'] ?? 'Unknown';
    final amount = p['amount'] ?? 0;
    final method = p['paymentMethod'] ?? 'N/A';

    return Opacity(
      opacity: filtersActive && !isHighlighted ? 0.45 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: isFirst
              ? null
              : const Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: typeColor(type),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$method · '),
                        TextSpan(
                          text: statusLabel(status),
                          style: TextStyle(
                            color: statusColor(status),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.faint,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Rs $amount',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
