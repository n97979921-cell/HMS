import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ViewAppointmentsScreen extends StatefulWidget {
  const ViewAppointmentsScreen({super.key});

  @override
  State<ViewAppointmentsScreen> createState() => _ViewAppointmentsScreenState();
}

class _ViewAppointmentsScreenState extends State<ViewAppointmentsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

  // Cache for user names so we don't re-fetch same user repeatedly
  final Map<String, String> _userNameCache = {};

  // Filters
  DateTime? _selectedDate;
  String _statusFilter = 'All';
  String _typeFilter = 'All';

  static const List<String> _statusOptions = [
    'All',
    'Requested',
    'Confirmed',
    'Completed',
    'Cancelled',
    'NoShow',
  ];

  static const List<String> _typeOptions = [
    'All',
    'IN_PERSON',
    'VIDEO_CALL',
    'WALK_IN',
  ];

  // Builds the Firestore query based on current filters.
  // Rebuilt fresh every time a filter changes, which gives
  // StreamBuilder a brand-new stream to listen to.
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('appointments');

    if (_selectedDate != null) {
      final startOfDay = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThan: endOfDay);
    }

    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    if (_typeFilter != 'All') {
      query = query.where('appointmentType', isEqualTo: _typeFilter);
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

  // Takes the raw docs from the stream and resolves patient/doctor
  // names for each one. Used inside a nested FutureBuilder so the
  // outer StreamBuilder stays purely real-time.
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _clearDateFilter() {
    setState(() => _selectedDate = null);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Requested':
        return const Color(0xFFF4B400);
      case 'Confirmed':
        return const Color(0xFF1A73E8);
      case 'Completed':
        return const Color(0xFF0F9D58);
      case 'Cancelled':
        return const Color(0xFFDB4437);
      case 'NoShow':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'IN_PERSON':
        return Icons.local_hospital_outlined;
      case 'VIDEO_CALL':
        return Icons.videocam_outlined;
      case 'WALK_IN':
        return Icons.directions_walk_rounded;
      default:
        return Icons.event_outlined;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'IN_PERSON':
        return 'In-Person';
      case 'VIDEO_CALL':
        return 'Video Call';
      case 'WALK_IN':
        return 'Walk-In';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters =
        _selectedDate != null || _statusFilter != 'All' || _typeFilter != 'All';

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
          'View Appointments',
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
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedDate != null
                                ? _primary.withOpacity(0.1)
                                : const Color(0xFFF4F7F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedDate != null
                                  ? _primary
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 16,
                                  color: _selectedDate != null
                                      ? _primary
                                      : const Color(0xFF6B7280)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedDate != null
                                      ? DateFormat('MMM d, yyyy')
                                          .format(_selectedDate!)
                                      : 'Filter by date',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedDate != null
                                        ? _primary
                                        : const Color(0xFF6B7280),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_selectedDate != null)
                                GestureDetector(
                                  onTap: _clearDateFilter,
                                  child: const Icon(Icons.close_rounded,
                                      size: 16, color: _primary),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DropdownFilter(
                        label: 'Type',
                        value: _typeFilter,
                        options: _typeOptions,
                        color: _primary,
                        displayLabel: _typeLabel,
                        onChanged: (v) {
                          setState(() => _typeFilter = v);
                        },
                      ),
                    ),
                  ],
                ),
                if (hasActiveFilters) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDate = null;
                        _statusFilter = 'All';
                        _typeFilter = 'All';
                      });
                    },
                    child: const Row(
                      children: [
                        Icon(Icons.refresh_rounded,
                            size: 14, color: Color(0xFFDB4437)),
                        SizedBox(width: 4),
                        Text(
                          'Clear all filters',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDB4437),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Real-time stream of appointments based on current filters.
          // A fresh stream is created on every build, so changing any
          // filter (via setState above) automatically attaches a new
          // listener with the updated query.
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
                          'Error loading appointments: ${snapshot.error}',
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
                  // Re-resolves names whenever the underlying docs change
                  future: _enrichWithNames(docs),
                  builder: (context, nameSnapshot) {
                    if (nameSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: _primary));
                    }

                    final appointments = nameSnapshot.data ?? [];

                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFDCEFE9),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            '${appointments.length} appointment${appointments.length == 1 ? '' : 's'} found',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: appointments.isEmpty
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
                                            Icon(Icons.event_busy_outlined,
                                                size: 64,
                                                color:
                                                    _primary.withOpacity(0.3)),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'No appointments found',
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
                                  itemCount: appointments.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final appt = appointments[index];
                                    return _AppointmentCard(
                                      appt: appt,
                                      statusColor:
                                          _statusColor(appt['status'] ?? ''),
                                      typeIcon: _typeIcon(
                                          appt['appointmentType'] ?? ''),
                                      typeLabel: _typeLabel(
                                          appt['appointmentType'] ?? ''),
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

class _AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appt;
  final Color statusColor;
  final IconData typeIcon;
  final String typeLabel;

  const _AppointmentCard({
    required this.appt,
    required this.statusColor,
    required this.typeIcon,
    required this.typeLabel,
  });

  static const Color _primary = Color(0xFF1F8A70);

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
    final status = appt['status'] ?? 'Unknown';
    final fee = appt['consultationFee'];

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
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, size: 13, color: _primary),
                    const SizedBox(width: 5),
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                  appt['patientName'] ?? 'N/A',
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
                  appt['doctorName'] ?? 'N/A',
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
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Text(
                _formatDate(appt['createdAt']),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          if (fee != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.payments_outlined,
                    size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 8),
                Text(
                  'Fee: Rs. $fee',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F9D58),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}