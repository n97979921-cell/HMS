import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Content-only widget for the Bed Occupancy tab — no Scaffold/AppBar
// of its own, since it lives inside ReportsScreen's TabBarView.
class BedOccupancyTab extends StatefulWidget {
  const BedOccupancyTab({super.key});

  @override
  State<BedOccupancyTab> createState() => _BedOccupancyTabState();
}

class _BedOccupancyTabState extends State<BedOccupancyTab> {
  static const Color _primary = Color(0xFF0D6B6B);
  static const Color _bg = Color(0xFFF5F7FA);

  static const List<String> _roomTypes = ['ICU', 'General', 'Private'];

  bool _isLoading = true;
  Map<String, dynamic> _occupancyData = {};

  @override
  void initState() {
    super.initState();
    _loadOccupancy();
  }

  Future<void> _loadOccupancy() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all rooms so we know which roomId belongs to which type
      final roomsSnap =
          await FirebaseFirestore.instance.collection('rooms').get();

      final Map<String, String> roomTypeById = {};
      for (final doc in roomsSnap.docs) {
        roomTypeById[doc.id] = doc.data()['roomType'] ?? 'Unknown';
      }

      // Fetch all beds, then bucket them by the roomType of their room
      final bedsSnap =
          await FirebaseFirestore.instance.collection('beds').get();

      final Map<String, int> totalByType = {
        for (final t in _roomTypes) t: 0,
      };
      final Map<String, int> occupiedByType = {
        for (final t in _roomTypes) t: 0,
      };

      int totalBeds = 0;
      int totalOccupied = 0;

      for (final doc in bedsSnap.docs) {
        final data = doc.data();
        final roomId = data['roomId'];
        final roomType = roomTypeById[roomId] ?? 'Unknown';

        if (!_roomTypes.contains(roomType)) continue;

        totalByType[roomType] = (totalByType[roomType] ?? 0) + 1;
        totalBeds++;

        if (data['availability'] == 'Occupied') {
          occupiedByType[roomType] = (occupiedByType[roomType] ?? 0) + 1;
          totalOccupied++;
        }
      }

      setState(() {
        _occupancyData = {
          'totalByType': totalByType,
          'occupiedByType': occupiedByType,
          'totalBeds': totalBeds,
          'totalOccupied': totalOccupied,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading occupancy: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'ICU':
        return const Color(0xFFDB4437);
      case 'General':
        return const Color(0xFF0D6B6B);
      case 'Private':
        return const Color(0xFF1A73E8);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalByType =
        Map<String, int>.from(_occupancyData['totalByType'] ?? <String, int>{});
    final occupiedByType = Map<String, int>.from(
        _occupancyData['occupiedByType'] ?? <String, int>{});
    final totalBeds = _occupancyData['totalBeds'] ?? 0;
    final totalOccupied = _occupancyData['totalOccupied'] ?? 0;
    final overallPct =
        totalBeds == 0 ? 0 : ((totalOccupied / totalBeds) * 100).round();

    return Container(
      color: _bg,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : RefreshIndicator(
              onRefresh: _loadOccupancy,
              color: _primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Overall occupancy hero card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'OVERALL OCCUPANCY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$overallPct%',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$totalOccupied of $totalBeds beds occupied',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'BY ROOM TYPE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // One card per room type
                  ..._roomTypes.map((type) {
                    final total = totalByType[type] ?? 0;
                    final occupied = occupiedByType[type] ?? 0;
                    final pct = total == 0 ? 0.0 : occupied / total;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RoomTypeOccupancyCard(
                        type: type,
                        total: total,
                        occupied: occupied,
                        percentage: pct,
                        color: _typeColor(type),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _RoomTypeOccupancyCard extends StatelessWidget {
  final String type;
  final int total;
  final int occupied;
  final double percentage;
  final Color color;

  const _RoomTypeOccupancyCard({
    required this.type,
    required this.total,
    required this.occupied,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pctLabel = total == 0 ? '0%' : '${(percentage * 100).round()}%';

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    type,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
              Text(
                total == 0 ? 'No beds added' : '$occupied / $total beds',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: const Color(0xFFF0F0F0)),
                  FractionallySizedBox(
                    widthFactor: percentage,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              pctLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
