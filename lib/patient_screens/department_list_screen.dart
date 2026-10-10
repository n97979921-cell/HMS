import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'doctor_list_screen.dart';
import '../screens/department_icons.dart';
import '../widgets/app_ui.dart';

class DepartmentListScreen extends StatefulWidget {
  final String appointmentType; // 'IN_PERSON' | 'VIDEO_CALL'

  const DepartmentListScreen({
    super.key,
    required this.appointmentType,
  });

  @override
  State<DepartmentListScreen> createState() => _DepartmentListScreenState();
}

class _DepartmentListScreenState extends State<DepartmentListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _departments = [];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() => _isLoading = true);
    try {
      final deptSnap = await FirebaseFirestore.instance
          .collection('departments')
          .orderBy('createdAt')
          .get();

      // Only show departments where at least one doctor has
      // doctor_settings configured (schema rule).
      final settingsSnap =
          await FirebaseFirestore.instance.collection('doctor_settings').get();

      final Set<String> departmentsWithDoctors = {};
      for (final settingDoc in settingsSnap.docs) {
        final profileDoc = await FirebaseFirestore.instance
            .collection('doctor_profiles')
            .doc(settingDoc.id)
            .get();

        if (profileDoc.exists) {
          final deptId = profileDoc.data()?['departmentId'];
          if (deptId != null) departmentsWithDoctors.add(deptId);
        }
      }

      final List<Map<String, dynamic>> result = [];
      for (final doc in deptSnap.docs) {
        if (!departmentsWithDoctors.contains(doc.id)) continue;
        result.add({'id': doc.id, ...doc.data()});
      }

      setState(() {
        _departments = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error loading departments: $e');
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

  String get _title => widget.appointmentType == 'VIDEO_CALL'
      ? 'Video consult'
      : 'In-clinic visit';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _departments.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadDepartments,
                        color: AppColors.teal,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select a department',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Choose a specialty to see available doctors',
                                style: TextStyle(
                                    fontSize: 12.5, color: AppColors.muted),
                              ),
                              const SizedBox(height: 14),
                              _buildDepartmentGrid(),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: _title,
      subtitle: 'Select a department',
    );
  }

  Widget _buildEmptyState() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: AppEmptyState(
        icon: Icons.business_outlined,
        title: 'No departments available',
        subtitle: 'Please check back later',
      ),
    );
  }

  Widget _buildDepartmentGrid() {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _departments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) =>
          _departmentCard(_departments[index], index),
    );
  }

  Widget _departmentCard(Map<String, dynamic> dept, int index) {
    final iconColor = getDepartmentColor(dept['colorKey']);
    final bgColor = iconColor.withOpacity(0.12);
    final icon = getDepartmentIcon(dept['iconName']);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DoctorListScreen(
              departmentId: dept['id'],
              departmentName: dept['name'] ?? '',
              appointmentType: widget.appointmentType,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(
              icon: icon,
              color: iconColor,
              background: bgColor,
              size: 42,
            ),
            const Spacer(),
            Text(
              dept['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            if (dept['description'] != null && dept['description'] != '')
              Text(
                dept['description'],
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
