import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

// ─────────────────────────────────────────
// MAIN SCREEN — Manage Prices
// ─────────────────────────────────────────
class ManagePricesScreen extends StatelessWidget {
  const ManagePricesScreen({super.key});

  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const AppHeader(title: 'Prices', subtitle: 'Rooms · Lab tests'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                // Room Type Prices Card
                _PriceOptionCard(
                  icon: Icons.bed_rounded,
                  iconColor: AppColors.teal,
                  iconBg: AppColors.tealSoft,
                  title: 'Room type prices',
                  subtitle: 'Set prices for ICU, General, Private rooms',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManageRoomPricesScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Test Type Prices Card
                _PriceOptionCard(
                  icon: Icons.biotech_rounded,
                  iconColor: AppColors.blue,
                  iconBg: AppColors.blueSoft,
                  title: 'Test type prices',
                  subtitle: 'Set prices for lab tests',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManageTestPricesScreen(),
                    ),
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

class _PriceOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PriceOptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          AppIconTile(
              icon: icon, color: iconColor, background: iconBg, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
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

  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

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

    showAppSheet(
      context,
      (_) => AppSheet(
        title: 'Edit price',
        subtitle: roomType,
        children: [
          const AppFieldLabel('Price per hour'),
          TextField(
            controller: priceController,
            keyboardType: TextInputType.number,
            decoration: appInputDecoration(hint: '0', prefixText: 'Rs '),
          ),
          const SizedBox(height: 20),
          AppPrimaryButton(
            label: 'Save',
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
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          AppHeader(
            title: 'Room type prices',
            subtitle: '${_roomTypes.length} room types',
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    children: [
                      ..._roomTypes.map((roomType) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AppCard(
                              child: Row(
                                children: [
                                  const AppIconTile(
                                    icon: Icons.bed_rounded,
                                    color: AppColors.teal,
                                    background: AppColors.tealSoft,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          roomType,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(
                                                text:
                                                    'Rs ${_prices[roomType]?.toStringAsFixed(0) ?? '0'}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                              const TextSpan(text: ' / hour'),
                                            ],
                                          ),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AppSoftButton(
                                    label: 'Edit',
                                    onTap: () => _showEditDialog(roomType),
                                  ),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 4),
                      const AppInfoNote(
                        text:
                            'A new price applies to free beds (Available and Under Maintenance) right away. Occupied beds keep their old price until the patient is released.',
                      ),
                    ],
                  ),
          ),
        ],
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

  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

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
    bool isSaving = false;

    showAppSheet(
      context,
      (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AppSheet(
          title: 'Add test',
          children: [
            const AppFieldLabel('Test name'),
            TextField(
              controller: nameController,
              decoration: appInputDecoration(hint: 'Type...'),
            ),
            const SizedBox(height: 14),
            const AppFieldLabel('Price'),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration:
                  appInputDecoration(hint: 'Type...', prefixText: 'Rs '),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Save',
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Test name is required'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      try {
                        final existing = await _firestore
                            .collection('test_type_prices')
                            .where('testType', isEqualTo: name)
                            .limit(1)
                            .get();

                        if (existing.docs.isNotEmpty) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'This test already exists. Use Edit instead.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          setDialogState(() => isSaving = false);
                          return;
                        }

                        final price =
                            double.tryParse(priceController.text.trim()) ?? 0;

                        final docRef =
                            _firestore.collection('test_type_prices').doc();
                        await docRef.set({
                          'testType': name,
                          'charge': price,
                          'updatedAt': DateTime.now(),
                        });

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        _loadTests();
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save test: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> test) {
    final priceController =
        TextEditingController(text: (test['charge'] ?? 0).toStringAsFixed(0));

    showAppSheet(
      context,
      (_) => AppSheet(
        title: 'Edit price',
        subtitle: test['testType'] ?? '',
        children: [
          const AppFieldLabel('Price'),
          TextField(
            controller: priceController,
            keyboardType: TextInputType.number,
            decoration: appInputDecoration(prefixText: 'Rs '),
          ),
          const SizedBox(height: 20),
          AppPrimaryButton(
            label: 'Save',
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
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(Map<String, dynamic> test) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Delete test',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: Color(0xFF9A2E16))),
        content: Text(
          'Are you sure you want to delete "${test['testType']}"?',
          style: const TextStyle(fontSize: 13, color: Color(0xFF3B4F53)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
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
                  onPressed: () async {
                    await _firestore
                        .collection('test_type_prices')
                        .doc(test['id'])
                        .delete();
                    Navigator.pop(context);
                    _loadTests();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: AppColors.danger,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Delete',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton:
          AppFab(label: 'Add test', onPressed: _showAddDialog),
      body: Column(
        children: [
          AppHeader(
            title: 'Test type prices',
            subtitle: _isLoading ? null : '${_tests.length} tests',
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _tests.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: const [
                          AppEmptyState(
                            icon: Icons.biotech_rounded,
                            title: 'No tests yet',
                            subtitle: 'Tap + to add a test',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                        itemCount: _tests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final test = _tests[index];
                          return AppCard(
                            child: Row(
                              children: [
                                const AppIconTile(
                                  icon: Icons.biotech_rounded,
                                  color: AppColors.blue,
                                  background: AppColors.blueSoft,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        test['testType'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Rs ${(test['charge'] ?? 0).toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Edit Button
                                AppSoftButton(
                                  label: 'Edit',
                                  onTap: () => _showEditDialog(test),
                                ),
                                const SizedBox(width: 8),
                                // Delete Button
                                AppDeleteButton(
                                  size: 38,
                                  onTap: () => _showDeleteConfirm(test),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
