import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_ui.dart';

class DepartmentDoctorsScreen extends StatefulWidget {
  final String departmentId;
  final String departmentName;

  const DepartmentDoctorsScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  State<DepartmentDoctorsScreen> createState() =>
      _DepartmentDoctorsScreenState();
}

class _DepartmentDoctorsScreenState extends State<DepartmentDoctorsScreen> {
  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

  bool _isLoading = true;
  List<Map<String, dynamic>> _doctors = [];

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    setState(() => _isLoading = true);
    try {
      final profilesSnap = await FirebaseFirestore.instance
          .collection('doctor_profiles')
          .where('departmentId', isEqualTo: widget.departmentId)
          .get();

      final List<Map<String, dynamic>> result = [];
      for (final doc in profilesSnap.docs) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(doc.id)
            .get();
        if (!userDoc.exists) continue;

        result.add({
          'name': userDoc.data()?['name'] ?? 'Doctor',
          'email': userDoc.data()?['email'] ?? '',
          'specialization': doc.data()['specialization'] ?? '',
          'status': userDoc.data()?['status'] ?? '',
        });
      }

      setState(() {
        _doctors = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _initials(String name) {
    final parts = name
        .replaceFirst('Dr. ', '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    return parts.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          AppHeader(
            title: widget.departmentName,
            subtitle: _isLoading
                ? null
                : '${_doctors.length} doctor${_doctors.length == 1 ? '' : 's'}',
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.teal))
                : _doctors.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: const [
                          AppEmptyState(
                            icon: Icons.medical_services_outlined,
                            title: 'No doctors in this department',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: _doctors.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return const Text(
                              'DOCTORS IN THIS DEPARTMENT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppColors.muted,
                              ),
                            );
                          }
                          final doc = _doctors[index - 1];
                          final isActive = doc['status'] == 'active';
                          return AppCard(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 23,
                                  backgroundColor: AppColors.tealSoft,
                                  child: Text(
                                    _initials(doc['name'] ?? ''),
                                    style: const TextStyle(
                                      color: AppColors.teal,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc['name'],
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        doc['specialization'],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AppStatusChip(
                                  label: isActive ? 'Active' : 'Inactive',
                                  colors: isActive
                                      ? AppChipColors.green
                                      : AppChipColors.red,
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
