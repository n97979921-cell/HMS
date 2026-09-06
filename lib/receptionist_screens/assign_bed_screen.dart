import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ASSIGN BED (Receptionist)
///
/// Room-type select → us type ke AVAILABLE beds dikhein → assign.
/// Transaction: bed availability → Occupied, appointmentId set,
/// assignedAt = serverTimestamp (reads pehle, writes baad).
class AssignBedScreen extends StatefulWidget {
  final String appointmentId;
  final String patientId;
  final String patientName;

  const AssignBedScreen({
    super.key,
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<AssignBedScreen> createState() => _AssignBedScreenState();
}

class _AssignBedScreenState extends State<AssignBedScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  static const List<Map<String, dynamic>> _roomTypes = [
    {
      'type': 'ICU',
      'icon': Icons.monitor_heart_outlined,
      'color': Color(0xFFD9534F)
    },
    {'type': 'General', 'icon': Icons.bed_outlined, 'color': Color(0xFF1F8A70)},
    {
      'type': 'Private',
      'icon': Icons.king_bed_outlined,
      'color': Color(0xFF1565C0)
    },
  ];

  String? _selectedType;
  bool _isLoadingBeds = false;
  List<Map<String, dynamic>> _availableBeds = [];
  bool _isAssigning = false;

  Future<void> _loadBeds(String roomType) async {
    setState(() {
      _selectedType = roomType;
      _isLoadingBeds = true;
      _availableBeds = [];
    });
    try {
      // Us roomType ke rooms dhoondo, phir unke Available beds
      final roomsSnap = await FirebaseFirestore.instance
          .collection('rooms')
          .where('roomType', isEqualTo: roomType)
          .get();
      final roomIds = roomsSnap.docs.map((d) => d.id).toList();
      final roomNumberById = {
        for (final d in roomsSnap.docs) d.id: d.data()['roomNumber'] ?? ''
      };

      if (roomIds.isEmpty) {
        setState(() => _isLoadingBeds = false);
        return;
      }

      // whereIn max 30 items — theek hai for demo scale
      final bedsSnap = await FirebaseFirestore.instance
          .collection('beds')
          .where('roomId', whereIn: roomIds)
          .where('availability', isEqualTo: 'Available')
          .get();

      setState(() {
        _availableBeds = bedsSnap.docs.map((d) {
          final data = d.data();
          return {
            'bedId': d.id,
            'roomNumber': roomNumberById[data['roomId']] ?? '',
            'bedNumber': data['bedNumber'] ?? '',
            'pricePerHour': data['pricePerHour'] ?? 0,
          };
        }).toList();
        _isLoadingBeds = false;
      });
    } catch (e) {
      setState(() => _isLoadingBeds = false);
      _showError('Error loading beds: $e');
    }
  }

  Future<void> _assignBed(Map<String, dynamic> bed) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Assign this bed?'),
        content: Text(
            'Room ${bed['roomNumber']} — Rs. ${bed['pricePerHour']}/hour\n\n'
            'Patient: ${widget.patientName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Assign', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isAssigning = true);
    try {
      final bedRef =
          FirebaseFirestore.instance.collection('beds').doc(bed['bedId']);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // READ pehle — race-check: bed abhi bhi Available hai?
        final bedSnap = await transaction.get(bedRef);
        if (!bedSnap.exists) throw Exception('Bed not found');
        if (bedSnap.data()?['availability'] != 'Available') {
          throw Exception('This bed was just taken. Please pick another.');
        }

        // WRITE
        transaction.update(bedRef, {
          'availability': 'Occupied',
          'appointmentId': widget.appointmentId,
          'assignedAt': FieldValue.serverTimestamp(),
          'releasedAt': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      _showSuccess('Bed assigned successfully');
      Navigator.pop(context, true);
    } catch (e) {
      _showError('Could not assign bed: $e');
      if (_selectedType != null) _loadBeds(_selectedType!); // refresh
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patient: ${widget.patientName}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    const SizedBox(height: 18),
                    const Text('Select room type',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A))),
                    const SizedBox(height: 10),
                    Row(
                      children: _roomTypes.map((rt) {
                        final isSel = _selectedType == rt['type'];
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _loadBeds(rt['type']),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isSel ? rt['color'] : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2))
                                ],
                              ),
                              child: Column(
                                children: [
                                  Icon(rt['icon'],
                                      color: isSel ? Colors.white : rt['color'],
                                      size: 22),
                                  const SizedBox(height: 6),
                                  Text(rt['type'],
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isSel
                                              ? Colors.white
                                              : const Color(0xFF1A2F3A))),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedType != null) ...[
                      Text('Available beds — $_selectedType',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2F3A))),
                      const SizedBox(height: 10),
                      _isLoadingBeds
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child:
                                    CircularProgressIndicator(color: _primary),
                              ),
                            )
                          : _availableBeds.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Text(
                                      'No available beds of this type right now.',
                                      style: TextStyle(color: Colors.grey)),
                                )
                              : Column(
                                  children: _availableBeds.map((bed) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.04),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2))
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    'Room ${bed['roomNumber']} — Bed ${bed['bedNumber']}',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFF1A2F3A))),
                                                Text(
                                                    'Rs. ${bed['pricePerHour']}/hour',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey)),
                                              ],
                                            ),
                                          ),
                                          ElevatedButton(
                                            onPressed: _isAssigning
                                                ? null
                                                : () => _assignBed(bed),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _primary,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                            ),
                                            child: const Text('Assign',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Assign Bed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
