// lib/screens/manage_users_screen.dart
import 'package:flutter/material.dart';
import 'user_list_screen.dart';
import 'admin_profile_screen.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  // Theme colors — matched to Admin Dashboard's green palette
  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

  @override
  Widget build(BuildContext context) {
    final roles = [
      {
        'title': 'Doctors',
        'role': 'doctor',
        'icon': Icons.medical_services_rounded,
      },
      {
        'title': 'Admins',
        'role': 'admin',
        'icon': Icons.admin_panel_settings_rounded,
      },
      {
        'title': 'Receptionists',
        'role': 'receptionist',
        'icon': Icons.support_agent_rounded,
      },
      {
        'title': 'Lab Staff',
        'role': 'labstaff',
        'icon': Icons.biotech_rounded,
      },
    ];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Users',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemCount: roles.length,
                itemBuilder: (context, index) {
                  final role = roles[index];
                  return _RoleCard(
                    title: role['title'] as String,
                    role: role['role'] as String,
                    icon: role['icon'] as IconData,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
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
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.people_outline), label: 'Users'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String role;
  final IconData icon;

  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color lightColor = Color(0xFFDCEFE9);

  const _RoleCard({
    required this.title,
    required this.role,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserListScreen(role: role, title: title),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: lightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: primaryColor, size: 28),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to view',
                    style: TextStyle(
                      fontSize: 12,
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
