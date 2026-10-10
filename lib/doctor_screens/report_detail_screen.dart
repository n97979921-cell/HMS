// lib/doctor_screens/report_detail_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import 'doctor_repository.dart';
import 'lab_test_status.dart';
import 'lab_test_detail.dart';
import 'dart:convert';

class ReportDetailScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String testId;

  const ReportDetailScreen({
    super.key,
    required this.repository,
    required this.testId,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  LabTestDetail? _detail;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.getLabTestDetail(widget.testId);
      if (mounted)
        setState(() {
          _detail = result;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load report. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _viewReportFullscreen(String base64Str) {
    final bytes = base64Decode(base64Str);

    showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.memory(bytes),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
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
    );
  }

  // Status badge (jab report load ho chuka ho) pehle jaisa right side par
  Widget _buildHeader() {
    return AppHeader(
      title: 'Report Detail',
      subtitle: _detail?.patientName,
      trailing: _detail != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: AppColors.mint.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(
                _detail!.status.label,
                style: const TextStyle(
                    color: AppColors.mint,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.teal));
    }
    if (_errorMessage != null || _detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Report not found',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadDetail,
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

    final detail = _detail!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        // Patient info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: AppColors.tealSoft,
                child: Text(
                  detail.patientName.isNotEmpty
                      ? detail.patientName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w800,
                      fontSize: 17),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.patientName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      '${detail.doctorName}${detail.reportDate != null ? ' · ${_formatDate(detail.reportDate!)}' : ''}',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Test name card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Test Name',
                  style: TextStyle(
                      color: AppColors.faint,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(detail.testType,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.text)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('REPORT',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.muted)),
        const SizedBox(height: 10),

        // Report (image, base64) — tap to view
        if (detail.reportBase64 != null && detail.reportBase64!.isNotEmpty) ...[
          GestureDetector(
            onTap: () => _viewReportFullscreen(detail.reportBase64!),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      base64Decode(detail.reportBase64!),
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 220,
                        color: AppColors.bg,
                        alignment: Alignment.center,
                        child: const Text('Could not load report',
                            style: TextStyle(color: AppColors.faint)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_in,
                          color: Colors.white, size: 19),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const AppEmptyState(
            icon: Icons.description_outlined,
            title: 'Report not uploaded yet',
          ),
        ],
      ],
    );
  }
}
