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

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _currentNavIndex = 0;
  final Logger _logger = Logger();

  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

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
        doctorRatings.add({'doctorId': entry.key, 'avgRating': avg});
      }
      doctorRatings
          .sort((a, b) => (b['avgRating'] as double).compareTo(a['avgRating']));

      final topRated = doctorRatings
          .where((d) => (d['avgRating'] as double) >= 4.7)
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DateTime? _parseSlotDateTime(dynamic dateStr, dynamic startTime) {
    try {
      final date = DateTime.parse(dateStr as String);
      final timeParts = (startTime as String).split(':');
      return DateTime(date.year, date.month, date.day, int.parse(timeParts[0]),
          int.parse(timeParts[1]));
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
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : RefreshIndicator(
                onRefresh: _loadHomeData,
                color: _primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGreetingCard(),
                      const SizedBox(height: 16),
                      _buildAssistanceCard(),
                      const SizedBox(height: 16),
                      if (_nextAppointment != null) ...[
                        _buildAppointmentCard(),
                        const SizedBox(height: 20),
                      ],
                      const Text(
                        'Our services',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2F3A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildServicesGrid(),
                      const SizedBox(height: 12),
                      _buildBillingCard(),
                      const SizedBox(height: 24),
                      if (_topDoctors.isNotEmpty) ...[
                        const Text(
                          'Top doctors',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2F3A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDoctorsRow(),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildGreetingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hello,',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                _patientName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your health, our priority',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_outlined,
                color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Need assistance?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A2F3A),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
            icon:
                const Icon(Icons.support_agent, size: 16, color: Colors.white),
            label: const Text('Help', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.calendar_today, color: _primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Next appointment',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  _nextAppointment!['doctorName'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2F3A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAppointmentTime(dt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _relativeCountdown(dt),
              style: const TextStyle(
                  fontSize: 11, color: _primary, fontWeight: FontWeight.w600),
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
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _serviceCard(Icons.videocam_outlined, 'Video consult',
            'Connect with doctors online', const Color(0xFFDCEFE9), () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const DepartmentListScreen(appointmentType: 'VIDEO_CALL'),
            ),
          );
        }),
        _serviceCard(Icons.local_hospital_outlined, 'In-clinic visit',
            'Book physical appointment', const Color(0xFFE3E0F7), () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const DepartmentListScreen(appointmentType: 'IN_PERSON'),
            ),
          );
        }),
        _serviceCard(Icons.science_outlined, 'Lab reports', 'View results',
            const Color(0xFFFDE6E0), () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LabReportsScreen()),
          );
        }),
        _serviceCard(Icons.medication_outlined, 'Prescription', 'Your medicine',
            const Color(0xFFD9ECF8), () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrescriptionsScreen()),
          );
        }),
      ],
    );
  }

  Widget _serviceCard(IconData icon, String title, String subtitle,
      Color bgColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: bgColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF1A2F3A), size: 22),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
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
          MaterialPageRoute(builder: (_) => const BillingScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFCEFD8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined,
                color: Color(0xFF1A2F3A), size: 22),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Billing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2F3A),
                  ),
                ),
                Text(
                  'Payments & dues',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorsRow() {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _topDoctors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final doc = _topDoctors[i];
          return Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _primary.withOpacity(0.15),
                  child: const Icon(Icons.person, color: _primary, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  doc['name'],
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2F3A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  doc['specialty'],
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      doc['rating'],
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex,
      onTap: (index) {
        if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyAppointmentsScreen()),
          );
        } else if (index == 2) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PatientProfileScreen()));
        } else {
          setState(() => _currentNavIndex = index);
        }
      },
      backgroundColor: Colors.white,
      selectedItemColor: _primary,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'My appointments'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
