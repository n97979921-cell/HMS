import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'doctor_list_screen.dart';

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
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _departments = [];

  static const List<Color> _bgColors = [
    Color(0xFFDCEFE9),
    Color(0xFFEAE3F7),
    Color(0xFFFCF1D6),
    Color(0xFFFADCE3),
    Color(0xFFD9ECF8),
    Color(0xFFFDE6E0),
  ];

  static const List<Color> _iconColors = [
    Color(0xFF1F8A70),
    Color(0xFF7E57C2),
    Color(0xFFC98A1B),
    Color(0xFFD1497A),
    Color(0xFF1565C0),
    Color(0xFFD9534F),
  ];

  static const List<IconData> _icons = [
    Icons.favorite_outline,
    Icons.child_friendly_outlined,
    Icons.medical_services_outlined,
    Icons.wb_sunny_outlined,
    Icons.psychology_outlined,
    Icons.visibility_outlined,
  ];

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
      backgroundColor: const Color(0xFFDB4437),
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
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _departments.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadDepartments,
                          color: _primary,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 80),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select a department',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A2F3A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Choose a specialty to see available doctors',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                _buildDepartmentGrid(),
                              ],
                            ),
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
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_outlined,
              size: 64, color: _primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'No departments available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please check back later',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _departments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) =>
          _departmentCard(_departments[index], index),
    );
  }

  Widget _departmentCard(Map<String, dynamic> dept, int index) {
    final bgColor = _bgColors[index % _bgColors.length];
    final iconColor = _iconColors[index % _iconColors.length];
    final icon = _icons[index % _icons.length];

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
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const Spacer(),
            Text(
              dept['name'] ?? '',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A),
              ),
            ),
            const SizedBox(height: 2),
            if (dept['description'] != null && dept['description'] != '')
              Text(
                dept['description'],
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
