import 'package:flutter/material.dart';
import 'view_reports_screen.dart';
import 'doctor_performance_screen.dart';
import 'bed_occupancy_screen.dart';
import 'lab_summary_report_screen.dart';

// This is the single entry point for "View Reports" in the admin
// drawer. It owns one shared AppBar + TabBar, and swipes between
// four tab contents:
//   1. Overview            (ReportsOverviewTab)
//   2. Doctor Performance  (DoctorPerformanceTab)
//   3. Bed Occupancy       (BedOccupancyTab)
//   4. Lab Summary         (LabSummaryTab)
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF0D6B6B);

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'View Reports',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Doctor Performance'),
            Tab(text: 'Bed Occupancy'),
            Tab(text: 'Lab Summary'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ReportsOverviewTab(),
          DoctorPerformanceTab(),
          BedOccupancyTab(),
          LabSummaryTab(),
        ],
      ),
    );
  }
}
