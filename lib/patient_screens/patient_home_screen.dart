import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'department_list_screen.dart';
import 'my_appointments_screen.dart';
import 'billing_screen.dart';
import 'lab_reports_screen.dart';
import 'prescriptions_screen.dart';
import 'patient_profile_screen.dart';
import 'help_screen.dart';
import 'package:logger/logger.dart';
import '../widgets/notification_bell_icon.dart';
import '../widgets/app_ui.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _currentNavIndex = 0;
  final Logger _logger = Logger();

  bool _isLoading = true;
  String _patientName = '';
  Map<String, dynamic>? _nextAppointment;
  List<Map<String, dynamic>> _topDoctors = [];

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      _patientName = userDoc.data()?['name'] ?? 'Patient';

      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: uid)
          .where('status', whereIn: ['Requested', 'Confirmed']).get();

      Map<String, dynamic>? soonest;
      DateTime? soonestTime;

      for (final doc in apptSnap.docs) {
        final data = doc.data();
        final slotId = data['slotId'];

        if (slotId == null) continue;

        final slotDoc = await FirebaseFirestore.instance
            .collection('slots')
            .doc(slotId)
            .get();

        if (!slotDoc.exists) continue;

        final slotData = slotDoc.data()!;
        final dateStr = slotData['date'];
        final startTime = slotData['startTime'];

        if (dateStr == null || startTime == null) continue;

        final slotDateTime = _parseSlotDateTime(dateStr, startTime);

        if (slotDateTime == null) continue;
        if (slotDateTime.isBefore(DateTime.now())) continue;

        if (soonestTime == null || slotDateTime.isBefore(soonestTime)) {
          final doctorDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(data['doctorId'])
              .get();

          soonest = {
            'appointmentId': doc.id,
            'doctorName': doctorDoc.data()?['name'] ?? 'Doctor',
            'dateTime': slotDateTime,
          };

          soonestTime = slotDateTime;
        }
      }

      _nextAppointment = soonest;

      final feedbackSnap =
          await FirebaseFirestore.instance.collection('feedback').get();

      final Map<String, List<int>> ratingsByDoctor = {};

      for (final doc in feedbackSnap.docs) {
        final data = doc.data();
        final doctorId = data['doctorId'];
        final rating = (data['rating'] ?? 0) as num;

        if (doctorId != null) {
          ratingsByDoctor.putIfAbsent(doctorId, () => []).add(rating.toInt());
        }
      }

      final List<Map<String, dynamic>> doctorRatings = [];

      for (final entry in ratingsByDoctor.entries) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;

        doctorRatings.add({
          'doctorId': entry.key,
          'avgRating': avg,
          'reviewCount': entry.value.length,
        });
      }

      doctorRatings.sort(
        (a, b) =>
            (b['avgRating'] as double).compareTo(a['avgRating'] as double),
      );

      final topRated = doctorRatings
          .where((d) =>
              (d['avgRating'] as double) >= 4.7 &&
              (d['reviewCount'] as int) >= 5)
          .toList();

      final List<Map<String, dynamic>> resolvedTopDoctors = [];

      for (final entry in topRated) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(entry['doctorId'])
            .get();

        final profileDoc = await FirebaseFirestore.instance
            .collection('doctor_profiles')
            .doc(entry['doctorId'])
            .get();

        String specialization = '';

        if (profileDoc.exists) {
          specialization = profileDoc.data()?['specialization'] ?? '';
        }

        resolvedTopDoctors.add({
          'name': doctorDoc.data()?['name'] ?? 'Doctor',
          'specialty': specialization,
          'rating': (entry['avgRating'] as double).toStringAsFixed(1),
        });
      }

      _topDoctors = resolvedTopDoctors;
    } catch (e) {
      _logger.e('Error loading home data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  DateTime? _parseSlotDateTime(dynamic dateStr, dynamic startTime) {
    try {
      final date = DateTime.parse(dateStr as String);
      final timeParts = (startTime as String).split(':');

      return DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (e) {
      return null;
    }
  }

  String _formatAppointmentTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(dt.year, dt.month, dt.day);

    final timeLabel = DateFormat('h:mm a').format(dt);

    if (apptDay == today) {
      return 'Today, $timeLabel';
    } else if (apptDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow, $timeLabel';
    } else {
      return '${DateFormat('d MMM').format(dt)}, $timeLabel';
    }
  }

  String _relativeCountdown(DateTime dt) {
    final diff = dt.difference(DateTime.now());

    if (diff.inDays > 0) return 'In ${diff.inDays}d';
    if (diff.inHours > 0) return 'In ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'In ${diff.inMinutes}m';

    return 'Now';
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            )
          : Column(
              children: [
                _buildGreetingCard(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadHomeData,
                    color: AppColors.teal,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_nextAppointment != null) ...[
                            _buildAppointmentCard(),
                            const SizedBox(height: 18),
                          ],
                          _sectionTitle('Our services'),
                          const SizedBox(height: 12),
                          _buildServicesGrid(),
                          const SizedBox(height: 12),
                          _buildBillingCard(),
                          if (_topDoctors.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _sectionTitle('Top doctors'),
                            const SizedBox(height: 12),
                            _buildDoctorsRow(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppColors.text,
      ),
    );
  }

  // Dark header: logo, "Hello,", name, tagline, bell + next appointment
  // card (agar ho) — sab wahi data, sirf naya look.
  Widget _buildGreetingCard() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 50,
                      height: 50,
                      color: Colors.white,
                      child: Image.asset(
                        'assets/Logo.png',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.local_hospital,
                            color: AppColors.header,
                            size: 24,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hello,',
                          style: TextStyle(
                            color: AppColors.headerMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Your health, our priority',
                          style: TextStyle(
                            color: AppColors.headerLabel,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const NotificationBellIcon(),
                ],
              ),
              const SizedBox(height: 16),
              _buildAssistanceCard(),
            ],
          ),
        ),
      ),
    );
  }

  // Header ke andar — same Help navigation, sirf look badla
  Widget _buildAssistanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Need assistance?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HelpScreen(),
                ),
              );
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.support_agent, size: 16, color: AppColors.header),
                  SizedBox(width: 6),
                  Text(
                    'Help',
                    style: TextStyle(
                      color: AppColors.header,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard() {
    final dt = _nextAppointment!['dateTime'] as DateTime;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.calendar_today_rounded,
            color: AppColors.teal,
            background: AppColors.tealSoft,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Next appointment',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.faint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _nextAppointment!['doctorName'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAppointmentTime(dt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.header,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _relativeCountdown(dt),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mint,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _serviceCard(
          Icons.videocam_outlined,
          'Video consult',
          'Connect with doctors online',
          const AppChipColors(AppColors.teal, AppColors.tealSoft),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DepartmentListScreen(
                  appointmentType: 'VIDEO_CALL',
                ),
              ),
            );
          },
        ),
        _serviceCard(
          Icons.local_hospital_outlined,
          'In-clinic visit',
          'Book physical appointment',
          const AppChipColors(Color(0xFF5B3FA8), Color(0xFFEEE8FB)),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DepartmentListScreen(
                  appointmentType: 'IN_PERSON',
                ),
              ),
            );
          },
        ),
        _serviceCard(
          Icons.science_outlined,
          'Lab reports',
          'View results',
          const AppChipColors(Color(0xFF9A2E16), Color(0xFFFBE6E0)),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LabReportsScreen(),
              ),
            );
          },
        ),
        _serviceCard(
          Icons.medication_outlined,
          'Prescription',
          'Your medicine',
          const AppChipColors(AppColors.blue, AppColors.blueSoft),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrescriptionsScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _serviceCard(
    IconData icon,
    String title,
    String subtitle,
    AppChipColors colors,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
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
              color: colors.fg,
              background: colors.bg,
              size: 42,
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BillingScreen(),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            AppIconTile(
              icon: Icons.receipt_long_outlined,
              color: Color(0xFF8A6D00),
              background: Color(0xFFF6F2E2),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Billing',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Payments & dues',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorsRow() {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _topDoctors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final doc = _topDoctors[i];
          final String name = '${doc['name']}';

          return Container(
            width: 138,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.tealSoft,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  doc['specialty'],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6E0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF2B233),
                        size: 13,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        doc['rating'],
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A6D00),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
        elevation: 0,
        backgroundColor: Colors.white,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        currentIndex: _currentNavIndex,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MyAppointmentsScreen(),
              ),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PatientProfileScreen(),
              ),
            );
          } else {
            setState(
              () => _currentNavIndex = index,
            );
          }
        },
        selectedItemColor: AppColors.header,
        unselectedItemColor: AppColors.faint,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today_rounded),
            label: 'My appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
