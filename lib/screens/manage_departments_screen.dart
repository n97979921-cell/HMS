import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'department_doctors_screen.dart';

class ManageDepartmentsScreen extends StatefulWidget {
  const ManageDepartmentsScreen({super.key});

  @override
  State<ManageDepartmentsScreen> createState() =>
      _ManageDepartmentsScreenState();
}

class _ManageDepartmentsScreenState extends State<ManageDepartmentsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color primaryDark = Color(0xFF0D6B5A);
  static const Color bgColor = Color(0xFFF4F7F6);

  List<Map<String, dynamic>> _departments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _firestore
          .collection('departments')
          .orderBy('createdAt', descending: false)
          .get();
      setState(() {
        _departments = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => _DepartmentDialog(
        title: 'Add Department',
        nameController: nameController,
        descController: descController,
        // Adding a new department — name must be editable.
        isEditMode: false,
        onSave: () async {
          if (nameController.text.trim().isEmpty) return;

          final existing = await _firestore
              .collection('departments')
              .where('name', isEqualTo: nameController.text.trim())
              .get();
          if (existing.docs.isNotEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Department already exists.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          await _firestore.collection('departments').add({
            'name': nameController.text.trim(),
            'description': descController.text.trim(),
            'createdAt': DateTime.now(),
            'updatedAt': DateTime.now(),
          });
          Navigator.pop(context);
          _loadDepartments();
        },
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> dept) {
    final nameController = TextEditingController(text: dept['name']);
    final descController = TextEditingController(text: dept['description']);

    showDialog(
      context: context,
      builder: (_) => _DepartmentDialog(
        title: 'Edit Department',
        nameController: nameController,
        descController: descController,
        // Editing an existing department — name is locked, only the
        // description can change.
        isEditMode: true,
        onSave: () async {
          // Name field is locked in edit mode, so we only ever write
          // the description back — the name in Firestore never
          // changes here.
          await _firestore.collection('departments').doc(dept['id']).update({
            'description': descController.text.trim(),
            'updatedAt': DateTime.now(),
          });
          Navigator.pop(context);
          _loadDepartments();
        },
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
          'Manage Departments',
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
          : _departments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business_rounded,
                          size: 64, color: primaryColor.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      const Text(
                        'No departments yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap + to add a department',
                        style: TextStyle(fontSize: 14, color: primaryColor),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDepartments,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _departments.length,
                    itemBuilder: (context, index) {
                      final dept = _departments[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DepartmentDoctorsScreen(
                                departmentId: dept['id'],
                                departmentName: dept['name'] ?? '',
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
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
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.business_rounded,
                                      color: primaryColor, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dept['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      if (dept['description'] != null &&
                                          dept['description'] != '')
                                        const SizedBox(height: 4),
                                      if (dept['description'] != null &&
                                          dept['description'] != '')
                                        Text(
                                          dept['description'],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6B7280),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                // Purana PopupMenuButton (3 dots) hata kar
                                // seedha "Edit" button lagaya — baaqi admin
                                // screens ke pattern se match karne ke liye.
                                GestureDetector(
                                  onTap: () => _showEditDialog(dept),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_rounded,
                                            color: primaryColor, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// DIALOG WIDGET
class _DepartmentDialog extends StatelessWidget {
  final String title;
  final TextEditingController nameController;
  final TextEditingController descController;
  final VoidCallback onSave;
  final bool isEditMode;

  const _DepartmentDialog({
    required this.title,
    required this.nameController,
    required this.descController,
    required this.onSave,
    this.isEditMode = false,
  });

  static const Color primaryColor = Color(0xFF1F8A70);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
          const Text('Department Name',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: nameController,
            // Locked once a department exists — renaming would break
            // the link doctors/invites already have to this name.
            enabled: !isEditMode,
            style: TextStyle(
              color: isEditMode ? Colors.grey[600] : Colors.black,
            ),
            decoration: InputDecoration(
              hintText: 'Type...',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: isEditMode,
              fillColor: const Color(0xFFF0F0F0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: primaryColor),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          if (isEditMode) ...[
            const SizedBox(height: 4),
            const Text(
              'Department name cannot be changed after creation.',
              style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Description',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: descController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Type...',
              hintStyle: const TextStyle(color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
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
            onPressed: onSave,
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
    );
  }
}