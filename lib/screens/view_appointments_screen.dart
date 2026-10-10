import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

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
    'CheckedIn',
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

      bool hasFeedback = false;
      if (data['status'] == 'Completed') {
        final feedbackDoc = await FirebaseFirestore.instance
            .collection('feedback')
            .doc(doc.id)
            .get();
        hasFeedback = feedbackDoc.exists;
      }

      results.add({
        'id': doc.id,
        ...data,
        'patientName': patientName,
        'doctorName': doctorName,
        'hasFeedback': hasFeedback,
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

  // ── Delete (single): koi confirmation nahi — seedha permanent
  //    delete, jaisa request kiya gaya. Ab HAR card ke top par delete
  //    icon available hai, status se qata-nazar. StreamBuilder khud-ba-
  //    khud list refresh kar dega, manual reload ki zaroorat nahi.
  Future<void> _deleteAppointment(BuildContext context, String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Appointment deleted'),
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

  // Statuses jo "Delete All" (bulk) ke liye eligible hain — Completed
  // sirf jab feedback pehle hi de diya gaya ho. Yeh restriction sirf
  // bulk delete par lagu hai; single-card delete (upar wala) ab har
  // status par available hai.
  static bool _isDeleteEligible(Map<String, dynamic> appt) {
    final status = appt['status'];
    if (status == 'Cancelled' || status == 'NoShow' || status == 'CheckedIn') {
      return true;
    }
    if (status == 'Completed' && appt['hasFeedback'] == true) {
      return true;
    }
    return false;
  }

  // ── Delete All — jo bhi appointments is waqt screen par (currently
  //    applied date/type/status filters ke baad) dikh rahe hain, unmein
  //    se eligible (Cancelled/NoShow/CheckedIn/Completed+feedback)
  //    sab ek batch write mein permanent delete — bina confirmation ke.
  //    Button sirf tab dikhta hai jab status-filter specifically ek
  //    deletable status par ho (neeche condition dekhein).
  Future<void> _deleteAllEligible(
      BuildContext context, List<Map<String, dynamic>> appointments) async {
    try {
      final eligible = appointments.where(_isDeleteEligible).toList();
      if (eligible.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final appt in eligible) {
        batch.delete(FirebaseFirestore.instance
            .collection('appointments')
            .doc(appt['id']));
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${eligible.length} appointment(s) deleted'),
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
      case 'Requested':
        return AppChipColors.yellow;
      case 'Confirmed':
        return AppChipColors.blue;
      case 'CheckedIn':
        return AppChipColors.purple;
      case 'Completed':
        return AppChipColors.green;
      case 'Cancelled':
        return AppChipColors.red;
      case 'NoShow':
        return AppChipColors.grey;
      default:
        return AppChipColors.grey;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'NoShow':
        return 'No-show';
      case 'CheckedIn':
        return 'Checked in';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters =
        _selectedDate != null || _statusFilter != 'All' || _typeFilter != 'All';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Filters section (header)
          AppHeader(
            title: 'Appointments',
            subtitle: 'All appointments',
            bottom: Row(
              children: [
                Expanded(
                  child: AppHeaderDropdown(
                    label: 'Status',
                    value: _statusFilter,
                    options: _statusOptions,
                    displayOf: (o) =>
                        o == 'All' ? 'All statuses' : _statusText(o),
                    dotColorOf: (o) =>
                        o == 'All' ? AppColors.faint : _statusColor(o),
                    onChanged: (v) {
                      setState(() => _statusFilter = v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppHeaderDropdown(
                    label: 'Type',
                    value: _typeFilter,
                    options: _typeOptions,
                    displayOf: (o) => o == 'All' ? 'All types' : _typeLabel(o),
                    onChanged: (v) {
                      setState(() => _typeFilter = v);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Date filter + clear
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: _selectedDate != null
                        ? AppColors.tealSoft
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _selectedDate != null
                            ? AppColors.teal
                            : AppColors.border,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 16,
                                color: _selectedDate != null
                                    ? AppColors.teal
                                    : AppColors.text),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDate != null
                                    ? DateFormat('MMM d, yyyy')
                                        .format(_selectedDate!)
                                    : 'Filter by date',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _selectedDate != null
                                      ? AppColors.teal
                                      : AppColors.text,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_selectedDate != null)
                              GestureDetector(
                                onTap: _clearDateFilter,
                                child: const Icon(Icons.close_rounded,
                                    size: 16, color: AppColors.teal),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFFE3ECEC),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _selectedDate = null;
                          _statusFilter = 'All';
                          _typeFilter = 'All';
                        });
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                        child: Text(
                          'Clear filters',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.teal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Real-time stream of appointments based on current filters.
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
                          'Error loading appointments: ${snapshot.error}',
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

                return FutureBuilder<List<Map<String, dynamic>>>(
                  // Re-resolves names whenever the underlying docs change
                  future: _enrichWithNames(docs),
                  builder: (context, nameSnapshot) {
                    if (nameSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child:
                              CircularProgressIndicator(color: AppColors.teal));
                    }

                    final appointments = nameSnapshot.data ?? [];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${appointments.length} appointment${appointments.length == 1 ? '' : 's'} found',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.teal,
                                  ),
                                ),
                              ),
                              // "Delete All" — same condition as before
                              if (const [
                                    'Cancelled',
                                    'Completed',
                                    'CheckedIn',
                                    'NoShow'
                                  ].contains(_statusFilter) &&
                                  appointments.isNotEmpty)
                                AppDeleteAllButton(
                                  onTap: () =>
                                      _deleteAllEligible(context, appointments),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: appointments.isEmpty
                              ? ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: const [
                                    AppEmptyState(
                                      icon: Icons.event_busy_outlined,
                                      title: 'No appointments found',
                                      subtitle: 'Try adjusting your filters',
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                  itemCount: appointments.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final appt = appointments[index];
                                    final status = appt['status'] ?? '';
                                    return _AppointmentCard(
                                      appt: appt,
                                      chipColors: _chipColors(status),
                                      statusText: _statusText(status),
                                      typeIcon: _typeIcon(
                                          appt['appointmentType'] ?? ''),
                                      typeLabel: _typeLabel(
                                          appt['appointmentType'] ?? ''),
                                      onDelete: () => _deleteAppointment(
                                          context, appt['id']),
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

class _AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appt;
  final AppChipColors chipColors;
  final String statusText;
  final IconData typeIcon;
  final String typeLabel;
  final VoidCallback onDelete;

  const _AppointmentCard({
    required this.appt,
    required this.chipColors,
    required this.statusText,
    required this.typeIcon,
    required this.typeLabel,
    required this.onDelete,
  });

  String _formatDate(dynamic ts) {
    if (ts == null) return 'N/A';
    try {
      final date = (ts as Timestamp).toDate();
      return DateFormat('MMM d, yyyy • h:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = appt['consultationFee'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, size: 13, color: AppColors.teal),
                    const SizedBox(width: 5),
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AppStatusChip(label: statusText, colors: chipColors),
              const SizedBox(width: 8),
              AppDeleteButton(size: 34, onTap: onDelete),
            ],
          ),
          const SizedBox(height: 12),
          AppInfoRow(
              label: 'Patient',
              value: appt['patientName'] ?? 'N/A',
              labelWidth: 70),
          AppInfoRow(
              label: 'Doctor',
              value: appt['doctorName'] ?? 'N/A',
              labelWidth: 70),
          AppInfoRow(
              label: 'Booked',
              value: _formatDate(appt['createdAt']),
              labelWidth: 70),
          if (fee != null)
            AppInfoRow(label: 'Fee', value: 'Rs $fee', labelWidth: 70),
        ],
      ),
    );
  }
}
