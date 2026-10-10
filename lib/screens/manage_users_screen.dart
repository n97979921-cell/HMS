// lib/screens/manage_users_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_list_screen.dart';
import 'admin_profile_screen.dart';
import '../widgets/app_ui.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  // ── NAYA (sirf dikhane ke liye): har role ke users ki ginti.
  // Wahi filter jo user list screen use karti hai (active + inactive).
  static Future<Map<String, int>> _loadCounts(List<String> roles) async {
    final Map<String, int> counts = {};
    for (final role in roles) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: role)
          .where('status', whereIn: ['active', 'inactive']).get();
      counts[role] = snap.docs.length;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final roles = [
      {
        'title': 'Doctors',
        'role': 'doctor',
        'icon': Icons.medical_services_rounded,
        'subtitle': 'Timings, fees and accounts',
        'iconColor': AppColors.blue,
      },
      {
        'title': 'Admins',
        'role': 'admin',
        'icon': Icons.admin_panel_settings_rounded,
        'subtitle': 'Hospital admin accounts',
        'iconColor': AppColors.teal,
      },
      {
        'title': 'Receptionists',
        'role': 'receptionist',
        'icon': Icons.support_agent_rounded,
        'subtitle': 'Front desk staff',
        'iconColor': const Color(0xFF8A5A00),
      },
      {
        'title': 'Lab Staff',
        'role': 'labstaff',
        'icon': Icons.biotech_rounded,
        'subtitle': 'Lab technicians',
        'iconColor': const Color(0xFF9A2E16),
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FutureBuilder<Map<String, int>>(
        future: _loadCounts(roles.map((r) => r['role'] as String).toList()),
        builder: (context, snap) {
          final counts = snap.data ?? {};
          final total = counts.values.fold<int>(0, (a, b) => a + b);
          return Column(
            children: [
              AppHeader(
                title: 'Manage users',
                bottom: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hospital staff',
                        style: TextStyle(
                          color: AppColors.headerMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snap.hasData ? '$total members' : '—',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: roles.length,
                  itemBuilder: (context, index) {
                    final role = roles[index];
                    final r = role['role'] as String;
                    return _RoleCard(
                      title: role['title'] as String,
                      role: r,
                      icon: role['icon'] as IconData,
                      subtitle: role['subtitle'] as String,
                      iconColor: role['iconColor'] as Color,
                      count: snap.hasData ? '${counts[r] ?? 0}' : '—',
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: BottomNavigationBar(
          currentIndex: 1, // "Users" tab selected dikhega
          onTap: (index) {
            if (index == 0) {
              Navigator.pop(context); // Home wapis
            } else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminProfileScreen()),
              );
            }
            // index == 1 → already yahin hain
          },
          elevation: 0,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.header,
          unselectedItemColor: AppColors.faint,
          selectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people_rounded),
                label: 'Users'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String role;
  final IconData icon;
  final String subtitle;
  final Color iconColor;
  final String count;

  const _RoleCard({
    required this.title,
    required this.role,
    required this.icon,
    required this.subtitle,
    required this.iconColor,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserListScreen(role: role, title: title),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppIconTile(icon: icon, color: iconColor, size: 44),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Tap to view',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
