import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'beds_list_screen.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Add ${widget.roomType} Room',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _roomNumberController,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Room Number',
              hintText: 'e.g. 101, A-201',
              prefixIcon: Icon(Icons.meeting_room_outlined,
                  color: widget.roomTypeColor, size: 20),
              filled: true,
              fillColor: const Color(0xFFF4F7F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.roomTypeColor, width: 1.5),
              ),
            ),
            validator: (v) => v!.isEmpty ? 'Room number is required' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _roomNumberController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: _isAdding ? null : _addRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.roomTypeColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isAdding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Add Room', style: TextStyle(color: Colors.white)),
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.roomType} Rooms',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddRoomDialog,
        backgroundColor: widget.roomTypeColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rooms')
            .where('roomType', isEqualTo: widget.roomType)
            .orderBy('createdAt')
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

          final rooms = snapshot.data?.docs ?? [];

          if (rooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.meeting_room_outlined,
                      size: 64, color: widget.roomTypeColor.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'No ${widget.roomType} rooms yet',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add a room',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: roomTypeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.meeting_room_outlined,
                  color: roomTypeColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Room $roomNumber',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    roomType,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
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
                            (d.data() as Map)['availability'] == 'Available')
                        .length ??
                    0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$total Beds',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: roomTypeColor,
                      ),
                    ),
                    Text(
                      '$available Available',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0F9D58),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: roomTypeColor),
          ],
        ),
      ),
    );
  }
}