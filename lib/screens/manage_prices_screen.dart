import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────
// MAIN SCREEN — Manage Prices
// ─────────────────────────────────────────
class ManagePricesScreen extends StatelessWidget {
  const ManagePricesScreen({super.key});

  static const Color primaryColor = Color(0xFF0D6B6B);
  static const Color bgColor = Color(0xFFBDD8D8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Prices',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Room Type Prices Card
            _PriceOptionCard(
              icon: Icons.bed_rounded,
              title: 'Room Type Prices',
              subtitle: 'Set prices for ICU, General, Private rooms',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManageRoomPricesScreen(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Test Type Prices Card
            _PriceOptionCard(
              icon: Icons.biotech_rounded,
              title: 'Test Type Prices',
              subtitle: 'Set prices for lab tests',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManageTestPricesScreen(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Consultation Fees Card
            _PriceOptionCard(
              icon: Icons.medical_services_rounded,
              title: 'Consultation Fees',
              subtitle: 'Set fees per department',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManageConsultationFeesScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const Color primaryColor = Color(0xFF0D6B6B);

  const _PriceOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
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
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: primaryColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF6B7280), size: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// ROOM TYPE PRICES SCREEN
// ─────────────────────────────────────────
class ManageRoomPricesScreen extends StatefulWidget {
  const ManageRoomPricesScreen({super.key});

  @override
  State<ManageRoomPricesScreen> createState() => _ManageRoomPricesScreenState();
}

class _ManageRoomPricesScreenState extends State<ManageRoomPricesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Color primaryColor = Color(0xFF0D6B6B);
  static const Color bgColor = Color(0xFFBDD8D8);

  // Fixed room types
  final List<String> _roomTypes = ['ICU', 'General', 'Private'];
  Map<String, double> _prices = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    setState(() => _isLoading = true);
    try {
      for (String roomType in _roomTypes) {
        final doc =
            await _firestore.collection('room_type_prices').doc(roomType).get();
        if (doc.exists) {
          _prices[roomType] = (doc.data()!['pricePerHour'] ?? 0).toDouble();
        } else {
          _prices[roomType] = 0;
        }
      }
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showEditDialog(String roomType) {
    final priceController = TextEditingController(
        text: _prices[roomType]?.toStringAsFixed(0) ?? '0');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Edit Price',
                style: TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(roomType,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryColor)),
            const SizedBox(height: 12),
            const Text('Price Per Hour',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '0',
                prefixText: 'Rs ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final price = double.tryParse(priceController.text.trim()) ?? 0;

                // 1. Master rate-card update
                await _firestore
                    .collection('room_type_prices')
                    .doc(roomType)
                    .set({
                  'roomType': roomType,
                  'pricePerHour': price,
                  'updatedAt': DateTime.now(),
                });

                // 2. Sirf FREE beds (Available + Under Maintenance) turant
                //    naye rate pe update karo. Occupied beds ko chhuo mat —
                //    unki price patient-assignment ke waqt "lock" ho chuki,
                //    release hote hi refresh hogi (admissions_screen.dart).
                final roomsSnap = await _firestore
                    .collection('rooms')
                    .where('roomType', isEqualTo: roomType)
                    .get();

                for (final roomDoc in roomsSnap.docs) {
                  final bedsSnap = await _firestore
                      .collection('beds')
                      .where('roomId', isEqualTo: roomDoc.id)
                      .where('availability',
                          whereIn: ['Available', 'Under Maintenance']).get();

                  if (bedsSnap.docs.isEmpty) continue;
                  final batch = _firestore.batch();
                  for (final bedDoc in bedsSnap.docs) {
                    batch.update(bedDoc.reference, {
                      'pricePerHour': price,
                      'updatedAt': DateTime.now(),
                    });
                  }
                  await batch.commit();
                }

                if (context.mounted) Navigator.pop(context);
                _loadPrices();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Room Type Prices',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _roomTypes.length,
              itemBuilder: (context, index) {
                final roomType = _roomTypes[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.bed_rounded,
                            color: primaryColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              roomType,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              'Rs ${_prices[roomType]?.toStringAsFixed(0) ?? '0'} / hour',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _showEditDialog(roomType),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        child: const Text('Edit',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────
// TEST TYPE PRICES SCREEN
// ─────────────────────────────────────────
class ManageTestPricesScreen extends StatefulWidget {
  const ManageTestPricesScreen({super.key});

  @override
  State<ManageTestPricesScreen> createState() => _ManageTestPricesScreenState();
}

class _ManageTestPricesScreenState extends State<ManageTestPricesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Color primaryColor = Color(0xFF0D6B6B);
  static const Color bgColor = Color(0xFFBDD8D8);

  List<Map<String, dynamic>> _tests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _firestore.collection('test_type_prices').get();
      setState(() {
        _tests = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Add Test',
                style: TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Test Name',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: 'Type...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Price',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Type...',
                prefixText: 'Rs ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;

                final existing = await _firestore
                    .collection('test_type_prices')
                    .doc(nameController.text.trim())
                    .get();
                if (existing.exists) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('This test already exists. Use Edit instead.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                final price = double.tryParse(priceController.text.trim()) ?? 0;
                await _firestore
                    .collection('test_type_prices')
                    .doc(nameController.text.trim())
                    .set({
                  'testType': nameController.text.trim(),
                  'charge': price,
                  'updatedAt': DateTime.now(),
                });
                Navigator.pop(context);
                _loadTests();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> test) {
    final priceController =
        TextEditingController(text: (test['charge'] ?? 0).toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Edit Price',
                style: TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(test['testType'] ?? '',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryColor)),
            const SizedBox(height: 12),
            const Text('Price',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: 'Rs ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final price = double.tryParse(priceController.text.trim()) ?? 0;
                await _firestore
                    .collection('test_type_prices')
                    .doc(test['id'])
                    .update({
                  'charge': price,
                  'updatedAt': DateTime.now(),
                });
                Navigator.pop(context);
                _loadTests();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(Map<String, dynamic> test) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Test',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
        content: Text('Are you sure you want to delete "${test['testType']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _firestore
                  .collection('test_type_prices')
                  .doc(test['id'])
                  .delete();
              Navigator.pop(context);
              _loadTests();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Test Type Prices',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: primaryColor,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : _tests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.biotech_rounded,
                          size: 64, color: primaryColor.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      const Text(
                        'No tests yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap + to add a test',
                        style: TextStyle(fontSize: 14, color: primaryColor),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tests.length,
                  itemBuilder: (context, index) {
                    final test = _tests[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.biotech_rounded,
                                color: primaryColor, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  test['testType'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                Text(
                                  'Rs ${(test['charge'] ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Edit Button
                          ElevatedButton(
                            onPressed: () => _showEditDialog(test),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            child: const Text('Edit',
                                style: TextStyle(color: Colors.white)),
                          ),
                          const SizedBox(width: 8),
                          // Delete Button
                          ElevatedButton(
                            onPressed: () => _showDeleteConfirm(test),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            child: const Text('Delete',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ─────────────────────────────────────────
// CONSULTATION FEES SCREEN
// ─────────────────────────────────────────
class ManageConsultationFeesScreen extends StatefulWidget {
  const ManageConsultationFeesScreen({super.key});

  @override
  State<ManageConsultationFeesScreen> createState() =>
      _ManageConsultationFeesScreenState();
}

class _ManageConsultationFeesScreenState
    extends State<ManageConsultationFeesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Color primaryColor = Color(0xFF0D6B6B);
  static const Color bgColor = Color(0xFFBDD8D8);

  List<Map<String, dynamic>> _departments = [];
  Map<String, Map<String, dynamic>> _fees = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load departments
      final deptSnap = await _firestore.collection('departments').get();
      final departments = deptSnap.docs
          .map((d) => {'id': d.id, 'name': d.data()['name']})
          .toList();

      // Load fees
      final feesSnap =
          await _firestore.collection('department_consultation_fees').get();
      Map<String, Map<String, dynamic>> fees = {};
      for (var doc in feesSnap.docs) {
        fees[doc.id] = doc.data();
      }

      setState(() {
        _departments = departments;
        _fees = fees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showEditDialog(Map<String, dynamic> dept) {
    final existingFee = _fees[dept['id']];
    final inPersonController = TextEditingController(
        text: (existingFee?['inPersonFee'] ?? 0).toStringAsFixed(0));
    final walkInController = TextEditingController(
        text: (existingFee?['walkInFee'] ?? 0).toStringAsFixed(0));
    final videoCallController = TextEditingController(
        text: (existingFee?['videoCallFee'] ?? 0).toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Edit Fees',
                style: TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dept['name'] ?? '',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primaryColor)),
              const SizedBox(height: 16),
              _feeField('In-Person Fee', inPersonController),
              const SizedBox(height: 12),
              _feeField('Walk-In Fee', walkInController),
              const SizedBox(height: 12),
              _feeField('Video Call Fee', videoCallController),
              const SizedBox(height: 10),
              Text(
                'Suggested: Walk-in ≥ In-person ≥ Video call',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await _firestore
                    .collection('department_consultation_fees')
                    .doc(dept['id'])
                    .set({
                  'departmentId': dept['id'],
                  'inPersonFee':
                      double.tryParse(inPersonController.text.trim()) ?? 0,
                  'walkInFee':
                      double.tryParse(walkInController.text.trim()) ?? 0,
                  'videoCallFee':
                      double.tryParse(videoCallController.text.trim()) ?? 0,
                  'updatedAt': DateTime.now(),
                });
                Navigator.pop(context);
                _loadData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: 'Rs ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: primaryColor),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Consultation Fees',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : _departments.isEmpty
              ? const Center(
                  child: Text(
                    'No departments found.\nAdd departments first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _departments.length,
                  itemBuilder: (context, index) {
                    final dept = _departments[index];
                    final fee = _fees[dept['id']];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.medical_services_rounded,
                                color: primaryColor, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dept['name'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                if (fee != null) ...[
                                  Text(
                                    'In-Person: Rs ${(fee['inPersonFee'] ?? 0).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                  Text(
                                    'Walk-In: Rs ${(fee['walkInFee'] ?? 0).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                  Text(
                                    'Video Call: Rs ${(fee['videoCallFee'] ?? 0).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                ] else
                                  const Text(
                                    'No fees set yet',
                                    style: TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _showEditDialog(dept),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            child: const Text('Edit',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
