// lib/doctor_screens/report_detail_screen.dart
import 'package:flutter/material.dart';
import 'doctor_repository.dart';
import 'lab_test_status.dart';
import 'lab_test_detail.dart';
import 'dart:convert';

class _DetailColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const error = Color(0xFFD64545);
}

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
                child: Image.memory(base64Decode(base64Str)),
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
      backgroundColor: _DetailColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_DetailColors.primary, _DetailColors.primaryDark],
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
          const Expanded(
            child: Text(
              'Report Detail',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (_detail != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(
                _detail!.status.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _DetailColors.primary));
    }
    if (_errorMessage != null || _detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: _DetailColors.error, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Report not found',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _DetailColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadDetail,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _DetailColors.primary),
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
      padding: const EdgeInsets.all(16),
      children: [
        // Patient info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DetailColors.cardBackground,
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
              CircleAvatar(
                radius: 22,
                backgroundColor: _DetailColors.primary.withOpacity(0.15),
                child: Text(
                  detail.patientName.isNotEmpty
                      ? detail.patientName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: _DetailColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.patientName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      '${detail.doctorName}${detail.reportDate != null ? ' · ${_formatDate(detail.reportDate!)}' : ''}',
                      style: const TextStyle(
                          color: _DetailColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Test name card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DetailColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Test Name',
                  style:
                      TextStyle(color: _DetailColors.textMuted, fontSize: 13)),
              const SizedBox(height: 4),
              Text(detail.testType,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // PDF file + download
        // Report image (base64) — tap to zoom
        if (detail.reportBase64 != null && detail.reportBase64!.isNotEmpty) ...[
          GestureDetector(
            onTap: () => _viewReportFullscreen(detail.reportBase64!),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    base64Decode(detail.reportBase64!),
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 220,
                      color: const Color(0xFFF0F0F0),
                      alignment: Alignment.center,
                      child: const Text('Could not load report',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.zoom_in,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _DetailColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text('Report not uploaded yet',
                textAlign: TextAlign.center,
                style: TextStyle(color: _DetailColors.textMuted)),
          ),
        ],
      ],
    );
  }
}
