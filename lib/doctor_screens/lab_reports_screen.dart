// lib/doctor_screens/lab_reports_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'doctor_repository.dart';
import 'lab_test_status.dart';
import 'lab_test_list_item.dart';
import 'report_detail_screen.dart';
import 'doctor_profile_screen.dart';

class _LabColors {
  static const pending = Color(0xFF8A6D00);
  static const confirmed = Color(0xFF5B3FA8);
  static const inProgress = Color(0xFF1D4F91);
  static const completed = Color(0xFF0B5E57);
  static const error = Color(0xFF9A2E16);
}

class LabReportsScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String doctorId;

  const LabReportsScreen({
    super.key,
    required this.repository,
    required this.doctorId,
  });

  @override
  State<LabReportsScreen> createState() => _LabReportsScreenState();
}

class _LabReportsScreenState extends State<LabReportsScreen> {
  String? _selectedFilter; // null = All
  List<LabTestListItem> _reports = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _bottomNavIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.getLabTestsForDoctor(
        doctorId: widget.doctorId,
        statusFilter: _selectedFilter,
      );
      if (mounted) {
        setState(() {
          _reports = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load lab reports. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _changeFilter(String? filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
    _loadReports();
  }

  Color _statusColor(LabTestStatus status) {
    switch (status) {
      case LabTestStatus.pending:
        return _LabColors.pending;
      case LabTestStatus.confirmed:
        return _LabColors.confirmed;
      case LabTestStatus.inProgress:
        return _LabColors.inProgress;
      case LabTestStatus.completed:
        return _LabColors.completed;
      case LabTestStatus.cancelled:
        return _LabColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Lab Reports',
      subtitle: 'Tests you requested',
      bottom: _buildFilterTabs(),
    );
  }

  Widget _buildFilterTabs() {
    final filters = <String, String?>{
      'All': null,
      'Confirmed': 'confirmed',
      'In Progress': 'inprogress',
      'Completed': 'completed',
      'Cancelled': 'cancelled',
    };

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = _selectedFilter == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _changeFilter(entry.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.mint
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: isSelected
                      ? null
                      : Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: isSelected ? AppColors.header : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.teal));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadReports,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.header, elevation: 0),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    if (_reports.isEmpty) {
      return const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: AppEmptyState(
          icon: Icons.science_outlined,
          title: 'No lab reports found',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadReports,
      color: AppColors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: _reports.length,
        itemBuilder: (context, index) => _reportCard(_reports[index]),
      ),
    );
  }

  Widget _reportCard(LabTestListItem item) {
    final color = _statusColor(item.status);
    final isCompleted = item.status == LabTestStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.science_outlined,
            color: AppColors.blue,
            background: AppColors.blueSoft,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.patientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text(item.testType,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12.5)),
                if (item.status == LabTestStatus.cancelled &&
                    item.cancelReason != null) ...[
                  const SizedBox(height: 2),
                  Text('Reason: ${item.cancelReason}',
                      style: const TextStyle(
                          color: Color(0xFF9A2E16),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isCompleted)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportDetailScreen(
                    repository: widget.repository,
                    testId: item.testId,
                  ),
                ),
              ),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.remove_red_eye_outlined,
                        size: 15, color: Colors.white),
                    SizedBox(width: 5),
                    Text('View',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            )
          else
            AppStatusChip(
              label: item.status.label,
              colors: AppChipColors(color, color.withOpacity(0.1)),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) {
            Navigator.pop(context);
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorProfileScreen(
                  repository: widget.repository,
                  doctorId: widget.doctorId,
                ),
              ),
            );
          }
          // index == 1 → already yahin hain, kuch mat karo
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.science_outlined),
              activeIcon: Icon(Icons.science),
              label: 'Lab Reports'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
