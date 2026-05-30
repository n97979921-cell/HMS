import 'package:flutter/material.dart';
import '../Services/admin_service.dart';
import 'invite_form_screen.dart';

class UserListScreen extends StatefulWidget {
  final String role;
  final String title;

  const UserListScreen({
    super.key,
    required this.role,
    required this.title,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final AdminService _adminService = AdminService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await _adminService.getUsersByRole(widget.role);
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  Color get _roleColor {
    switch (widget.role) {
      case 'doctor':
        return const Color(0xFF1A73E8);
      case 'admin':
        return const Color(0xFF0F9D58);
      case 'receptionist':
        return const Color(0xFFF4B400);
      case 'labstaff':
        return const Color(0xFFDB4437);
      default:
        return const Color(0xFF1A73E8);
    }
  }

  IconData get _roleIcon {
    switch (widget.role) {
      case 'doctor':
        return Icons.medical_services_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'receptionist':
        return Icons.support_agent_rounded;
      case 'labstaff':
        return Icons.biotech_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InviteFormScreen(role: widget.role),
            ),
          );
          _loadUsers(); // Refresh after invite
        },
        backgroundColor: _roleColor,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: _roleColor),
            )
          : _users.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      return _UserCard(
                        user: _users[index],
                        roleColor: _roleColor,
                        roleIcon: _roleIcon,
                        onStatusChanged: _loadUsers,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_roleIcon, size: 64, color: _roleColor.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'No ${widget.title} yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to send an invite',
            style: TextStyle(
              fontSize: 14,
              color: _roleColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Color roleColor;
  final IconData roleIcon;
  final VoidCallback onStatusChanged;

  const _UserCard({
    required this.user,
    required this.roleColor,
    required this.roleIcon,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool isActive = user['status'] == 'active';
    final AdminService adminService = AdminService();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(roleIcon, color: roleColor, size: 24),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user['email'] ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  if (user['phone'] != null && user['phone'] != '') ...[
                    const SizedBox(height: 2),
                    Text(
                      user['phone'],
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Status badge + menu
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFE6F4EA)
                        : const Color(0xFFFCE8E6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? const Color(0xFF0F9D58)
                          : const Color(0xFFDB4437),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Color(0xFF6B7280), size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) async {
                    if (value == 'deactivate') {
                      await adminService.deactivateUser(user['uid']);
                      onStatusChanged();
                    } else if (value == 'activate') {
                      await adminService.reactivateUser(user['uid']);
                      onStatusChanged();
                    } else if (value == 'reset') {
                      await adminService.resetUserPassword(user['email']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Password reset email sent!')),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    if (isActive)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Row(
                          children: [
                            Icon(Icons.block_rounded,
                                color: Color(0xFFDB4437), size: 18),
                            SizedBox(width: 8),
                            Text('Deactivate'),
                          ],
                        ),
                      )
                    else
                      const PopupMenuItem(
                        value: 'activate',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Color(0xFF0F9D58), size: 18),
                            SizedBox(width: 8),
                            Text('Activate'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'reset',
                      child: Row(
                        children: [
                          Icon(Icons.lock_reset_rounded,
                              color: Color(0xFF1A73E8), size: 18),
                          SizedBox(width: 8),
                          Text('Reset Password'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
