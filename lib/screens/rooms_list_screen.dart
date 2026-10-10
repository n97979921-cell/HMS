import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'beds_list_screen.dart';
import '../widgets/app_ui.dart';

class RoomsListScreen extends StatefulWidget {
  final String roomType;
  final Color roomTypeColor;

  const RoomsListScreen({
    super.key,
    required this.roomType,
    required this.roomTypeColor,
  });

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen> {
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

  final _formKey = GlobalKey<FormState>();
  final _roomNumberController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _roomNumberController.dispose();
    super.dispose();
  }

  Future<void> _addRoom() async {
    if (!_formKey.currentState!.validate()) return;

    // Check duplicate room number in same type
    final existing = await FirebaseFirestore.instance
        .collection('rooms')
        .where('roomType', isEqualTo: widget.roomType)
        .where('roomNumber', isEqualTo: _roomNumberController.text.trim())
        .get();

    if (existing.docs.isNotEmpty) {
      _showError('Room number already exists in ${widget.roomType}!');
      return;
    }

    setState(() => _isAdding = true);

    try {
      await FirebaseFirestore.instance.collection('rooms').add({
        'roomType': widget.roomType,
        'roomNumber': _roomNumberController.text.trim(),
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      });

      _roomNumberController.clear();
      Navigator.pop(context);
      _showSuccess('Room added successfully!');
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isAdding = false);
    }
  }

  void _showAddRoomDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Add ${widget.roomType} room',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppFieldLabel('Room number'),
              TextFormField(
                controller: _roomNumberController,
                keyboardType: TextInputType.text,
                style: const TextStyle(fontSize: 14),
                decoration: appInputDecoration(hint: 'e.g. 101, A-201'),
                validator: (v) => v!.isEmpty ? 'Room number is required' : null,
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _roomNumberController.clear();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: AppColors.text, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isAdding ? null : _addRoom,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: AppColors.header,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isAdding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Add room',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
      floatingActionButton:
          AppFab(label: 'Add room', onPressed: _showAddRoomDialog),
      body: Column(
        children: [
          AppHeader(
            title: '${widget.roomType} rooms',
            subtitle: 'Tap a room to see its beds',
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .where('roomType', isEqualTo: widget.roomType)
                  .orderBy('createdAt')
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

                final rooms = snapshot.data?.docs ?? [];

                if (rooms.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      AppEmptyState(
                        icon: Icons.meeting_room_outlined,
                        title: 'No ${widget.roomType} rooms yet',
                        subtitle: 'Tap Add room to add a room',
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final data = room.data() as Map<String, dynamic>;

                    return _RoomCard(
                      roomId: room.id,
                      roomNumber: data['roomNumber'] ?? '',
                      roomType: widget.roomType,
                      roomTypeColor: widget.roomTypeColor,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BedsListScreen(
                              roomId: room.id,
                              roomNumber: data['roomNumber'] ?? '',
                              roomType: widget.roomType,
                              roomTypeColor: widget.roomTypeColor,
                            ),
                          ),
                        );
                      },
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

class _RoomCard extends StatelessWidget {
  final String roomId;
  final String roomNumber;
  final String roomType;
  final Color roomTypeColor;
  final VoidCallback onTap;

  const _RoomCard({
    required this.roomId,
    required this.roomNumber,
    required this.roomType,
    required this.roomTypeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          AppIconTile(icon: Icons.meeting_room_outlined, color: roomTypeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room $roomNumber',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                // Real-time bed count
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('beds')
                      .where('roomId', isEqualTo: roomId)
                      .snapshots(),
                  builder: (context, snap) {
                    final total = snap.data?.docs.length ?? 0;
                    final available = snap.data?.docs
                            .where((d) =>
                                (d.data() as Map)['availability'] ==
                                'Available')
                            .length ??
                        0;
                    return Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$roomType · $total Beds · '),
                          TextSpan(
                            text: '$available Available',
                            style: const TextStyle(
                              color: Color(0xFF0B5E57),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
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
