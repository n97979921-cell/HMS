import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

class BedsListScreen extends StatefulWidget {
  final String roomId;
  final String roomNumber;
  final String roomType;
  final Color roomTypeColor;

  const BedsListScreen({
    super.key,
    required this.roomId,
    required this.roomNumber,
    required this.roomType,
    required this.roomTypeColor,
  });

  @override
  State<BedsListScreen> createState() => _BedsListScreenState();
}

class _BedsListScreenState extends State<BedsListScreen> {
  static const Color _bg = Color(0xFFF4F7F6);

  bool _isAdding = false;

  Color _statusColor(String status) {
    switch (status) {
      case 'Available':
        return const Color(0xFF0B5E57);
      case 'Occupied':
        return const Color(0xFF9A2E16);
      case 'Under Maintenance':
        return const Color(0xFF8A6D00);
      default:
        return AppColors.muted;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Available':
        return Icons.check_circle_outline_rounded;
      case 'Occupied':
        return Icons.person_outlined;
      case 'Under Maintenance':
        return Icons.build_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> _addBed() async {
    setState(() => _isAdding = true);
    try {
      final priceDoc = await FirebaseFirestore.instance
          .collection('room_type_prices')
          .doc(widget.roomType)
          .get();
      if (!priceDoc.exists || priceDoc.data()?['pricePerHour'] == null) {
        _showError(
            'Price not set for ${widget.roomType}. Ask admin to set room prices first.');
        return;
      }
      final pricePerHour = priceDoc.data()!['pricePerHour'];

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final existingBeds = await FirebaseFirestore.instance
            .collection('beds')
            .where('roomId', isEqualTo: widget.roomId)
            .get();

        // Private room restriction — only 1 bed allowed per Private room
        if (widget.roomType == 'Private' && existingBeds.docs.isNotEmpty) {
          throw Exception('PRIVATE_LIMIT_REACHED');
        }

        final usedNumbers = existingBeds.docs
            .map((doc) => (doc.data()['bedNumber'] as num?)?.toInt())
            .whereType<int>()
            .toSet();

        int nextBedNumber = 1;
        while (usedNumbers.contains(nextBedNumber)) {
          nextBedNumber++;
        }

        final newBedRef = FirebaseFirestore.instance.collection('beds').doc();
        transaction.set(newBedRef, {
          'roomId': widget.roomId,
          'bedNumber': nextBedNumber,
          'availability': 'Available',
          'appointmentId': null,
          'assignedAt': null,
          'releasedAt': null,
          'pricePerHour': pricePerHour,
          'updatedAt': DateTime.now(),
        });
      });

      _showSuccess('Bed added successfully!');
    } catch (e) {
      if (e.toString().contains('PRIVATE_LIMIT_REACHED')) {
        _showError(
            'Private room already has a bed. Only 1 bed allowed per Private room.');
      } else {
        _showError('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _updateBedStatus(String bedId, String currentStatus) async {
    if (currentStatus == 'Occupied') {
      _showError('Cannot change status — bed is currently occupied!');
      return;
    }

    final newStatus =
        currentStatus == 'Available' ? 'Under Maintenance' : 'Available';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Change status',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        content: Text(
          'Change bed status to "$newStatus"?',
          style: const TextStyle(color: Color(0xFF6B7280)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirm',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('beds').doc(bedId).update({
        'availability': newStatus,
        'updatedAt': DateTime.now(),
      });
      _showSuccess('Bed status updated!');
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF0F9D58),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('beds')
            .where('roomId', isEqualTo: widget.roomId)
            .snapshots(),
        builder: (context, snapshot) {
          final bedCount = snapshot.data?.docs.length ?? 0;
          final isPrivateLimitReached =
              widget.roomType == 'Private' && bedCount >= 1;

          if (isPrivateLimitReached) {
            return const SizedBox.shrink();
          }

          return FloatingActionButton.extended(
            onPressed: _isAdding ? null : _addBed,
            backgroundColor: AppColors.header,
            elevation: 6,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            icon: _isAdding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded,
                    color: AppColors.mint, size: 24),
            label: const Text('Add bed',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          );
        },
      ),
      body: Column(
        children: [
          AppHeader(
            title: 'Room ${widget.roomNumber}',
            subtitle: '${widget.roomType} · tap a bed status to change it',
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('beds')
                  .where('roomId', isEqualTo: widget.roomId)
                  .orderBy('bedNumber')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.teal));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final beds = snapshot.data?.docs ?? [];

                final available = beds
                    .where(
                        (b) => (b.data() as Map)['availability'] == 'Available')
                    .length;
                final occupied = beds
                    .where(
                        (b) => (b.data() as Map)['availability'] == 'Occupied')
                    .length;
                final maintenance = beds
                    .where((b) =>
                        (b.data() as Map)['availability'] ==
                        'Under Maintenance')
                    .length;

                if (beds.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: const [
                      AppEmptyState(
                        icon: Icons.bed_outlined,
                        title: 'No beds added yet',
                        subtitle: 'Tap Add bed to get started',
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          _StatChip(
                              label: 'Available',
                              count: available,
                              color: _statusColor('Available')),
                          _StatChip(
                              label: 'Occupied',
                              count: occupied,
                              color: _statusColor('Occupied')),
                          _StatChip(
                              label: 'Maintenance',
                              count: maintenance,
                              color: _statusColor('Under Maintenance')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (int index = 0; index < beds.length; index++)
                      Builder(builder: (context) {
                        final bed = beds[index];
                        final data = bed.data() as Map<String, dynamic>;
                        final status = data['availability'] ?? 'Available';
                        final bedNumber = data['bedNumber'] ?? (index + 1);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _BedCard(
                            bedNumber: bedNumber,
                            status: status,
                            pricePerHour: data['pricePerHour'] ?? 0,
                            statusColor: _statusColor(status),
                            statusIcon: _statusIcon(status),
                            roomTypeColor: widget.roomTypeColor,
                            onStatusTap: () => _updateBedStatus(bed.id, status),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _BedCard extends StatelessWidget {
  final int bedNumber;
  final String status;
  final dynamic pricePerHour;
  final Color statusColor;
  final IconData statusIcon;
  final Color roomTypeColor;
  final VoidCallback onStatusTap;

  const _BedCard({
    required this.bedNumber,
    required this.status,
    required this.pricePerHour,
    required this.statusColor,
    required this.statusIcon,
    required this.roomTypeColor,
    required this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          AppIconTile(icon: Icons.bed_outlined, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bed $bedNumber',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Rs $pricePerHour / hour',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: status == 'Occupied' ? null : onStatusTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  if (status != 'Occupied') ...[
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 12, color: statusColor),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
