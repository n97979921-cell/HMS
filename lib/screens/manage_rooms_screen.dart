import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'rooms_list_screen.dart';
import '../widgets/app_ui.dart';

class ManageRoomsScreen extends StatelessWidget {
  const ManageRoomsScreen({super.key});

  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

  static const List<Map<String, dynamic>> _roomTypes = [
    {
      'type': 'ICU',
      'label': 'ICU',
      'subtitle': 'Intensive Care Unit',
      'icon': Icons.monitor_heart_outlined,
      'color': Color(0xFF9A2E16),
    },
    {
      'type': 'General',
      'label': 'General',
      'subtitle': 'General Ward',
      'icon': Icons.bed_outlined,
      'color': Color(0xFF0E6E68),
    },
    {
      'type': 'Private',
      'label': 'Private',
      'subtitle': 'Private Room',
      'icon': Icons.king_bed_outlined,
      'color': Color(0xFF1D4F91),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const AppHeader(
            title: 'Rooms & beds',
            subtitle: 'Select a room type to manage rooms and beds',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                const Text(
                  'ROOM TYPES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                for (final rt in _roomTypes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RoomTypeCard(
                      type: rt['type'],
                      label: rt['label'],
                      subtitle: rt['subtitle'],
                      icon: rt['icon'],
                      color: rt['color'],
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoomsListScreen(
                              roomType: rt['type'],
                              roomTypeColor: rt['color'],
                            ),
                          ),
                        );
                      },
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

class _RoomTypeCard extends StatelessWidget {
  final String type;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _RoomTypeCard({
    required this.type,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          AppIconTile(icon: icon, color: color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                // Real-time room count
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rooms')
                      .where('roomType', isEqualTo: type)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs.length ?? 0;
                    return Text(
                      '$subtitle · $count Rooms',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.muted, size: 24),
        ],
      ),
    );
  }
}
