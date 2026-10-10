import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';
import 'reports_screen.dart';

// Content-only widget for the Bed Occupancy tab — no Scaffold/AppBar
// of its own, since it lives inside ReportsScreen's TabBarView.
class BedOccupancyTab extends StatefulWidget {
  const BedOccupancyTab({super.key});

  @override
  State<BedOccupancyTab> createState() => _BedOccupancyTabState();
}

class _BedOccupancyTabState extends State<BedOccupancyTab> {
  static const Color _primary = Color(0xFF0E6E68);
  static const Color _bg = Color(0xFFF2F5F5);

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
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'ICU':
        return const Color(0xFF9A2E16);
      case 'General':
        return const Color(0xFF0E6E68);
      case 'Private':
        return const Color(0xFF1D4F91);
      default:
        return const Color(0xFF52666A);
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
      child: Column(
        children: [
          const ReportsHeaderStrip(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : RefreshIndicator(
                    onRefresh: _loadOccupancy,
                    color: AppColors.teal,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // Overall occupancy card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Overall occupancy',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$overallPct%',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: Text(
                                      '$totalOccupied of $totalBeds beds',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _OccupancyBar(
                                fraction: totalBeds == 0
                                    ? 0.0
                                    : (totalOccupied / totalBeds).toDouble(),
                                color: AppColors.teal,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        const Text(
                          'BY ROOM TYPE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // One card per room type
                        ..._roomTypes.map((type) {
                          final total = totalByType[type] ?? 0;
                          final occupied = occupiedByType[type] ?? 0;
                          final pct = total == 0 ? 0.0 : occupied / total;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
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
          ),
        ],
      ),
    );
  }
}

class _OccupancyBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _OccupancyBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(color: const Color(0xFFECEFEF)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  type == 'General' ? 'General ward' : type,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              Text(
                total == 0 ? 'No beds added' : '$occupied / $total beds',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _OccupancyBar(fraction: percentage, color: color),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              pctLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
