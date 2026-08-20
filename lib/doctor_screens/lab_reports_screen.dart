// lib/doctor_screens/lab_reports_screen.dart
import 'package:flutter/material.dart';
import 'doctor_repository.dart';
import 'lab_test_status.dart';
import 'lab_test_list_item.dart';
import 'report_detail_screen.dart';

class _LabColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const pending = Color(0xFFB98900);
  static const inProgress = Color(0xFF2D6BE0);
  static const completed = Color(0xFF1F8A70);
  static const error = Color(0xFFD64545);
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
        return const Color(0xFF7E57C2);
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
      backgroundColor: _LabColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterTabs(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_LabColors.primary, _LabColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const Text(
            'Lab Reports',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
        ],
      ),
      child: Row(
        children: filters.entries.map((entry) {
          final isSelected = _selectedFilter == entry.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => _changeFilter(entry.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? _LabColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: isSelected ? Colors.white : _LabColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
          child: CircularProgressIndicator(color: _LabColors.primary));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: _LabColors.error, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _LabColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadReports,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _LabColors.primary),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    if (_reports.isEmpty) {
      return const Center(
        child: Text('No lab reports found',
            style: TextStyle(color: _LabColors.textMuted)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadReports,
      color: _LabColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
        color: _LabColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.patientName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(item.testType,
                    style: const TextStyle(
                        color: _LabColors.textMuted, fontSize: 13)),
                if (item.status == LabTestStatus.cancelled &&
                    item.cancelReason != null) ...[
                  const SizedBox(height: 2),
                  Text('Reason: ${item.cancelReason}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (isCompleted)
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportDetailScreen(
                    repository: widget.repository,
                    testId: item.testId,
                  ),
                ),
              ),
              icon: const Icon(Icons.remove_red_eye_outlined,
                  size: 16, color: Colors.white),
              label: const Text('View',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(
                item.status.label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _bottomNavIndex,
      selectedItemColor: _LabColors.primary,
      unselectedItemColor: _LabColors.textMuted,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        if (index == 0) Navigator.pop(context);
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.science_outlined), label: 'Lab Reports'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
