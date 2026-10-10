import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'department_doctors_screen.dart';
import 'department_icons.dart';
import '../widgets/app_ui.dart';

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
    String selectedIcon = 'local_hospital_outlined';
    String selectedColor = 'green';

    showAppSheet(
      context,
      (_) => _DepartmentDialog(
        title: 'Add Department',
        nameController: nameController,
        descController: descController,
        isEditMode: false,
        selectedIcon: selectedIcon,
        selectedColor: selectedColor,
        onIconChanged: (icon) => selectedIcon = icon,
        onColorChanged: (color) => selectedColor = color,
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
            'iconName': selectedIcon,
            'colorKey': selectedColor,
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
    String selectedIcon = dept['iconName'] ?? 'local_hospital_outlined';
    String selectedColor = dept['colorKey'] ?? 'green';

    showAppSheet(
      context,
      (_) => _DepartmentDialog(
        title: 'Edit Department',
        nameController: nameController,
        descController: descController,
        isEditMode: true,
        selectedIcon: selectedIcon,
        selectedColor: selectedColor,
        onIconChanged: (icon) => selectedIcon = icon,
        onColorChanged: (color) => selectedColor = color,
        onSave: () async {
          await _firestore.collection('departments').doc(dept['id']).update({
            'description': descController.text.trim(),
            'iconName': selectedIcon,
            'colorKey': selectedColor,
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
      backgroundColor: AppColors.bg,
      floatingActionButton: AppFab(
        label: 'Add department',
        onPressed: _showAddDialog,
      ),
      body: Column(
        children: [
          AppHeader(
            title: 'Departments',
            subtitle: _isLoading ? null : '${_departments.length} departments',
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : RefreshIndicator(
                    color: AppColors.teal,
                    onRefresh: _loadDepartments,
                    child: _departments.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(20),
                            children: const [
                              AppEmptyState(
                                icon: Icons.business_rounded,
                                title: 'No departments yet',
                                subtitle: 'Tap + to add a department',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                            itemCount: _departments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final dept = _departments[index];
                              final color =
                                  getDepartmentColor(dept['colorKey']);
                              final hasDesc = dept['description'] != null &&
                                  dept['description'] != '';
                              return AppCard(
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
                                child: Row(
                                  children: [
                                    AppIconTile(
                                      icon: getDepartmentIcon(dept['iconName']),
                                      color: color,
                                      size: 48,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            dept['name'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.text,
                                            ),
                                          ),
                                          if (hasDesc) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              dept['description'],
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: AppColors.muted,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    AppSoftButton(
                                      label: 'Edit',
                                      onTap: () => _showEditDialog(dept),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DepartmentDialog extends StatefulWidget {
  final String title;
  final TextEditingController nameController;
  final TextEditingController descController;
  final VoidCallback onSave;
  final bool isEditMode;
  final String selectedIcon;
  final String selectedColor;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<String> onColorChanged;

  const _DepartmentDialog({
    required this.title,
    required this.nameController,
    required this.descController,
    required this.onSave,
    required this.selectedIcon,
    required this.selectedColor,
    required this.onIconChanged,
    required this.onColorChanged,
    this.isEditMode = false,
  });

  @override
  State<_DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  static const Color primaryColor = Color(0xFF1F8A70);
  late String _icon;
  late String _color;

  @override
  void initState() {
    super.initState();
    _icon = widget.selectedIcon;
    _color = widget.selectedColor;
  }

  @override
  Widget build(BuildContext context) {
    final accent = getDepartmentColor(_color);
    return AppSheet(
      title: widget.title,
      children: [
        const AppFieldLabel('Department name'),
        TextField(
          controller: widget.nameController,
          enabled: !widget.isEditMode,
          style: TextStyle(
            color: widget.isEditMode ? AppColors.faint : AppColors.text,
            fontWeight: FontWeight.w600,
          ),
          decoration: appInputDecoration(
            hint: 'Type...',
            filled: widget.isEditMode,
          ),
        ),
        if (widget.isEditMode) ...[
          const SizedBox(height: 4),
          const Text(
            'Department name cannot be changed after creation.',
            style: TextStyle(fontSize: 11, color: AppColors.faint),
          ),
        ],
        const SizedBox(height: 14),
        const AppFieldLabel('Description'),
        TextField(
          controller: widget.descController,
          maxLines: 3,
          decoration: appInputDecoration(hint: 'Type...'),
        ),
        const SizedBox(height: 14),
        const AppFieldLabel('Icon'),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: departmentIconMap.entries.map((entry) {
            final isSelected = _icon == entry.key;
            return GestureDetector(
              onTap: () {
                setState(() => _icon = entry.key);
                widget.onIconChanged(entry.key);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? accent.withOpacity(0.12) : AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Icon(entry.value,
                    color: isSelected ? accent : AppColors.muted, size: 20),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const AppFieldLabel('Color'),
        Wrap(
          spacing: 12,
          children: departmentColorMap.entries.map((entry) {
            final isSelected = _color == entry.key;
            return GestureDetector(
              onTap: () {
                setState(() => _color = entry.key);
                widget.onColorChanged(entry.key);
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: entry.value,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: isSelected
                      ? const [
                          BoxShadow(color: AppColors.text, spreadRadius: 2),
                        ]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        AppPrimaryButton(label: 'Save', onPressed: widget.onSave),
      ],
    );
  }
}
