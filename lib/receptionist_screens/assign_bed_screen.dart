import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

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
  static const Color _primary = Color(0xFF0B2E33);

  static const List<Map<String, dynamic>> _roomTypes = [
    {
      'type': 'ICU',
      'icon': Icons.monitor_heart_outlined,
      'color': Color(0xFF9A2E16)
    },
    {'type': 'General', 'icon': Icons.bed_outlined, 'color': Color(0xFF0E6E68)},
    {
      'type': 'Private',
      'icon': Icons.king_bed_outlined,
      'color': Color(0xFF1D4F91)
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Assign this bed?'),
        content: Text(
            'Room ${bed['roomNumber']} — Bed ${bed['bedNumber']} — Rs. ${bed['pricePerHour']}/hour\n\n'
            'Patient: ${widget.patientName}'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
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
      backgroundColor: const Color(0xFF9A2E16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('SELECT ROOM TYPE'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (int i = 0; i < _roomTypes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: _roomTypeTile(_roomTypes[i])),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_selectedType != null) ...[
                    _sectionLabel(
                        'AVAILABLE BEDS — ${_selectedType!.toUpperCase()}'),
                    const SizedBox(height: 10),
                    _isLoadingBeds
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                  color: AppColors.teal),
                            ),
                          )
                        : _availableBeds.isEmpty
                            ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 22, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Text(
                                  'No available beds of this type right now.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.faint),
                                ),
                              )
                            : Column(
                                children: _availableBeds
                                    .map((bed) => _bedCard(bed))
                                    .toList(),
                              ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.muted));
  }

  Widget _roomTypeTile(Map<String, dynamic> rt) {
    final isSel = _selectedType == rt['type'];
    final Color c = rt['color'];
    return GestureDetector(
      onTap: () => _loadBeds(rt['type']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 84,
        decoration: BoxDecoration(
          color: isSel ? c : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isSel
                    ? Colors.white.withOpacity(0.18)
                    : c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(rt['icon'], color: isSel ? Colors.white : c, size: 20),
            ),
            const SizedBox(height: 6),
            Text(rt['type'],
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isSel ? Colors.white : AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _bedCard(Map<String, dynamic> bed) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room ${bed['roomNumber']} — Bed ${bed['bedNumber']}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text('Rs. ${bed['pricePerHour']}/hour',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _isAssigning ? null : () => _assignBed(bed),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              disabledBackgroundColor: AppColors.header.withOpacity(0.5),
              elevation: 0,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Assign',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final name = widget.patientName;
    return AppHeader(
      title: 'Assign Bed',
      subtitle: 'Pick a room type and bed',
      bottom: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.mint,
                shape: BoxShape.circle,
              ),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: const TextStyle(
                    color: AppColors.header,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Patient',
                      style: TextStyle(
                          color: AppColors.headerMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
