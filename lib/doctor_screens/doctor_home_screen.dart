// lib/doctor_screens/doctor_home_screen.dart
import 'package:flutter/material.dart';
import 'appointment_status.dart';
import 'doctor_appointment_list_item.dart';
import 'doctor_repository.dart';
import 'lab_reports_screen.dart';
import 'doctor_profile_screen.dart';
import 'appointment_detail_screen.dart';

class _DoctorColors {
  static const primary = Color(0xFF1F8A70);
  static const primaryDark = Color(0xFF166049);
  static const background = Color(0xFFF5F7F8);
  static const cardBackground = Colors.white;
  static const textMuted = Color(0xFF8A8A8A);
  static const videoBadge = Color(0xFF1F8A70);
  static const walkInBadge = Color(0xFFB98900);
  static const error = Color(0xFFD64545);
}

class DoctorHomeScreen extends StatefulWidget {
  final DoctorRepository repository;
  final String doctorId;

  const DoctorHomeScreen({
    super.key,
    required this.repository,
    required this.doctorId,
  });

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedTab = 'confirmed';
  int _bottomNavIndex = 0;

  String? _doctorName;
  List<DoctorAppointmentListItem> _appointments = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDoctorName();
    _loadAppointments();
  }

  Future<void> _loadDoctorName() async {
    try {
      final name = await widget.repository.getDoctorName(widget.doctorId);
      if (mounted) setState(() => _doctorName = name);
    } catch (_) {
      if (mounted) setState(() => _doctorName = 'Doctor');
    }
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.repository.getAppointmentsForDate(
        doctorId: widget.doctorId,
        date: _selectedDate,
        statuses: [_selectedTab],
      );
      if (mounted) {
        setState(() {
          _appointments = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load appointments. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _changeDate(int days) {
    final newDate = _selectedDate.add(Duration(days: days));
    final today = DateTime.now();
    final minDate = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 7));
    final maxDate = DateTime(today.year, today.month, today.day).add(const Duration(days: 7));

    if (newDate.isBefore(minDate) || newDate.isAfter(maxDate)) return;

    setState(() => _selectedDate = newDate);
    _loadAppointments();
  }

  bool _canGoPrevious() {
    final today = DateTime.now();
    final minDate = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 7));
    final currentDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return currentDate.isAfter(minDate);
  }

  bool _canGoNext() {
    final today = DateTime.now();
    final maxDate = DateTime(today.year, today.month, today.day).add(const Duration(days: 7));
    final currentDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return currentDate.isBefore(maxDate);
  }

  void _changeTab(String tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
    _loadAppointments();
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DoctorColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildDateNavigator(),
            _buildTabToggle(),
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_DoctorColors.primary, _DoctorColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome,', style: TextStyle(color: Colors.white70, fontSize: 14)),
              Text(
                _doctorName ?? '...',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              const Text(
                'Manage your appointments',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_none, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDateNavigator() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _DoctorColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: _canGoPrevious() ? () => _changeDate(-1) : null,
            icon: Icon(Icons.chevron_left, color: _canGoPrevious() ? _DoctorColors.primary : _DoctorColors.textMuted),
            label: Text(
              'Previous Day',
              style: TextStyle(color: _canGoPrevious() ? _DoctorColors.primary : _DoctorColors.textMuted),
            ),
          ),
          Column(
            children: [
              Text(
                _isToday(_selectedDate) ? 'Today' : 'Selected',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(_formatDate(_selectedDate), style: const TextStyle(color: _DoctorColors.textMuted, fontSize: 12)),
            ],
          ),
          TextButton.icon(
            onPressed: _canGoNext() ? () => _changeDate(1) : null,
            icon: Icon(Icons.chevron_right, color: _canGoNext() ? _DoctorColors.primary : _DoctorColors.textMuted),
            label: Text(
              'Next Day',
              style: TextStyle(color: _canGoNext() ? _DoctorColors.primary : _DoctorColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
      ),
      child: Row(
        children: [
          _tabButton('Confirmed', 'confirmed'),
          _tabButton('Completed', 'completed'),
        ],
      ),
    );
  }

  Widget _tabButton(String label, String value) {
    final isSelected = _selectedTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTab(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _DoctorColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : _DoctorColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _DoctorColors.primary));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _DoctorColors.error, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: _DoctorColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAppointments,
                style: ElevatedButton.styleFrom(backgroundColor: _DoctorColors.primary),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    if (_appointments.isEmpty) {
      return const Center(
        child: Text('No appointments found', style: TextStyle(color: _DoctorColors.textMuted)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAppointments,
      color: _DoctorColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _appointments.length,
        itemBuilder: (context, index) => _appointmentCard(_appointments[index]),
      ),
    );
  }

  Widget _appointmentCard(DoctorAppointmentListItem item) {
    final isVideo = item.appointmentType == AppointmentType.videoCall;
    final badgeColor = isVideo ? _DoctorColors.videoBadge : _DoctorColors.walkInBadge;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AppointmentDetailScreen(
              repository: widget.repository,
              doctorId: widget.doctorId,
              appointment: item,
              dateLabel: _formatDate(_selectedDate),
            ),
          ),
        );
        _loadAppointments();
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DoctorColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(isVideo ? Icons.videocam_outlined : Icons.storefront_outlined, color: badgeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.patientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(item.slotTime, style: const TextStyle(color: _DoctorColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(
              item.appointmentType.label,
              style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _bottomNavIndex,
      selectedItemColor: _DoctorColors.primary,
      unselectedItemColor: _DoctorColors.textMuted,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        setState(() => _bottomNavIndex = index);
        if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LabReportsScreen(repository: widget.repository, doctorId: widget.doctorId),
            ),
          );
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DoctorProfileScreen(repository: widget.repository, doctorId: widget.doctorId),
            ),
          );
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.science_outlined), label: 'Lab Reports'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}