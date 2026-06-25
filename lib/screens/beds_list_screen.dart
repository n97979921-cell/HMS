import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  static const Color _bg = Color(0xFFF5F7FA);

  bool _isAdding = false;

  Color _statusColor(String status) {
    switch (status) {
      case 'Available':
        return const Color(0xFF0F9D58);
      case 'Occupied':
        return const Color(0xFFDB4437);
      case 'Under Maintenance':
        return const Color(0xFFF4B400);
      default:
        return const Color(0xFF6B7280);
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
        setState(() => _isAdding = false);
        return;
      }

      final pricePerHour = priceDoc.data()!['pricePerHour'];

      await FirebaseFirestore.instance.collection('beds').add({
        'roomId': widget.roomId,
        'availability': 'Available',
        'appointmentId': null,
        'assignedAt': null,
        'releasedAt': null,
        'pricePerHour': pricePerHour,
        'updatedAt': DateTime.now(),
      });

      _showSuccess('Bed added successfully!');
    } catch (e) {
      _showError('Error: $e');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Change Status',
          style: TextStyle(fontWeight: FontWeight.w700),
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
              backgroundColor: _statusColor(newStatus),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: widget.roomTypeColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Room ${widget.roomNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            Text(
              widget.roomType,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAdding ? null : _addBed,
        backgroundColor: widget.roomTypeColor,
        icon: _isAdding
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Bed', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('beds')
            .where('roomId', isEqualTo: widget.roomId)
            .orderBy('updatedAt')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: widget.roomTypeColor));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final beds = snapshot.data?.docs ?? [];

          final available = beds
              .where((b) => (b.data() as Map)['availability'] == 'Available')
              .length;
          final occupied = beds
              .where((b) => (b.data() as Map)['availability'] == 'Occupied')
              .length;
          final maintenance = beds
              .where((b) =>
                  (b.data() as Map)['availability'] == 'Under Maintenance')
              .length;

          return Column(
            children: [
              if (beds.isNotEmpty)
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      _StatChip(
                          label: 'Available',
                          count: available,
                          color: const Color(0xFF0F9D58)),
                      const SizedBox(width: 8),
                      _StatChip(
                          label: 'Occupied',
                          count: occupied,
                          color: const Color(0xFFDB4437)),
                      const SizedBox(width: 8),
                      _StatChip(
                          label: 'Maintenance',
                          count: maintenance,
                          color: const Color(0xFFF4B400)),
                    ],
                  ),
                ),
              Expanded(
                child: beds.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bed_outlined,
                                size: 64,
                                color: widget.roomTypeColor.withOpacity(0.4)),
                            const SizedBox(height: 16),
                            const Text(
                              'No beds added yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap + Add Bed to get started',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        itemCount: beds.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final bed = beds[index];
                          final data = bed.data() as Map<String, dynamic>;
                          final status = data['availability'] ?? 'Available';
                          final bedNumber = index + 1;

                          return _BedCard(
                            bedNumber: bedNumber,
                            status: status,
                            pricePerHour: data['pricePerHour'] ?? 0,
                            statusColor: _statusColor(status),
                            statusIcon: _statusIcon(status),
                            roomTypeColor: widget.roomTypeColor,
                            onStatusTap: () => _updateBedStatus(bed.id, status),
                          );
                        },
                      ),
              ),
            ],
          );
        },
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bed_outlined, color: statusColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bed $bedNumber',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rs. $pricePerHour / hour',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
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
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.3)),
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
                      fontWeight: FontWeight.w600,
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
