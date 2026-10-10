import 'package:flutter/material.dart';
import 'view_reports_screen.dart';
import 'doctor_performance_screen.dart';
import 'bed_occupancy_screen.dart';
import 'lab_summary_report_screen.dart';
import '../widgets/app_ui.dart';

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
  // Theme colors — matched to Admin Dashboard's green palette
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

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

  static const List<String> _tabLabels = ['Overview', 'Doctors', 'Beds', 'Lab'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Header (title + tab chips). Har tab apni dark strip khud
          // neeche jorta hai (date/month controls ke saath).
          Container(
            color: AppColors.header,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AppHeaderIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'Reports',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 44),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        return Row(
                          children: List.generate(_tabLabels.length, (i) {
                            final active = _tabController.index == i;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => _tabController.animateTo(i),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.mint
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: active
                                          ? AppColors.mint
                                          : Colors.white.withOpacity(0.22),
                                    ),
                                  ),
                                  child: Text(
                                    _tabLabels[i],
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: active
                                          ? AppColors.header
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                ReportsOverviewTab(),
                DoctorPerformanceTab(),
                BedOccupancyTab(),
                LabSummaryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Har report tab ke top par dark strip (header ka hissa lagti hai).
class ReportsHeaderStrip extends StatelessWidget {
  final Widget? child;
  const ReportsHeaderStrip({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 4, 20, child == null ? 16 : 18),
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: child,
    );
  }
}

/// Dark-style month/date navigation (< label >).
class ReportsDateNav extends StatelessWidget {
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const ReportsDateNav({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  Widget _btn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(onTap == null ? 0.04 : 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 20,
            color:
                onTap == null ? Colors.white.withOpacity(0.3) : Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.chevron_left_rounded, onPrev),
        SizedBox(
          width: 118,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _btn(Icons.chevron_right_rounded, onNext),
      ],
    );
  }
}
