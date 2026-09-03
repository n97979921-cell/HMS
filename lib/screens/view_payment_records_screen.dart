import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = _typeFilter != 'All' || _statusFilter != 'All';

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
          'Payment Records',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          // Filters section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DropdownFilter(
                        label: 'Type',
                        value: _typeFilter,
                        options: _typeOptions,
                        color: _primary,
                        onChanged: (v) {
                          setState(() => _typeFilter = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DropdownFilter(
                        label: 'Status',
                        value: _statusFilter,
                        options: _statusOptions,
                        color: _primary,
                        displayLabel: _statusLabel,
                        onChanged: (v) {
                          setState(() => _statusFilter = v);
                        },
                      ),
                    ),
                  ],
                ),
                if (hasActiveFilters) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 13, color: Color(0xFF6B7280)),
                      const SizedBox(width: 5),
                      const Expanded(
                        child: Text(
                          'Showing full appointment bills that have a matching payment',
                          style:
                              TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _typeFilter = 'All';
                            _statusFilter = 'All';
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFDB4437),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                          color: const Color(0xFFDB4437).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Error loading payments: ${snapshot.error}',
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

                return FutureBuilder<List<_PaymentGroup>>(
                  future: _buildGroups(docs),
                  builder: (context, groupSnapshot) {
                    if (groupSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: _primary));
                    }

                    final groups = groupSnapshot.data ?? [];

                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFDCEFE9),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            '${groups.length} appointment bill${groups.length == 1 ? '' : 's'} found',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: groups.isEmpty
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
                                            Icon(Icons.receipt_long_outlined,
                                                size: 64,
                                                color:
                                                    _primary.withOpacity(0.3)),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'No payment records found',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Try adjusting your filters',
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
                                  itemCount: groups.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    return _PaymentGroupCard(
                                      group: groups[index],
                                      statusColor: _statusColor,
                                      statusLabel: _statusLabel,
                                      typeIcon: _typeIcon,
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

class _DropdownFilter extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final Color color;
  final ValueChanged<String> onChanged;
  final String Function(String)? displayLabel;

  const _DropdownFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.color,
    required this.onChanged,
    this.displayLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = value != 'All';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.1) : const Color(0xFFF4F7F6),
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
            final display =
                opt == 'All' ? '$label: All' : (displayLabel?.call(opt) ?? opt);
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

class _PaymentGroupCard extends StatelessWidget {
  final _PaymentGroup group;
  final Color Function(String) statusColor;
  final String Function(String) statusLabel;
  final IconData Function(String) typeIcon;

  const _PaymentGroupCard({
    required this.group,
    required this.statusColor,
    required this.statusLabel,
    required this.typeIcon,
  });

  static const Color _primary = Color(0xFF1F8A70);

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
    return Container(
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
          // Header: patient name + date
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      color: _primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.patientName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        _formatDate(group.payments.first['createdAt']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Each payment line within the group
          ...group.payments.map((p) {
            final isHighlighted = group.matchingIds.contains(p['id']);
            final type = p['type'] ?? 'Unknown';
            final status = p['status'] ?? 'Unknown';
            final amount = p['amount'] ?? 0;
            final method = p['paymentMethod'] ?? 'N/A';

            return Container(
              decoration: BoxDecoration(
                color: isHighlighted
                    ? _primary.withOpacity(0.05)
                    : Colors.transparent,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(typeIcon(type),
                      size: 16, color: const Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        Text(
                          method,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs. $amount',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel(status),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor(status),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          // Total row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F6),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Bill',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  'Rs. ${group.total}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}