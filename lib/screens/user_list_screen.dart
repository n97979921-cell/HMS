// lib/screens/user_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Services/admin_service.dart';
import 'invite_form_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;

  // Theme colors — matched to Admin Dashboard's green palette
  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) {
          final name = (user['name'] ?? '').toString().toLowerCase();
          return name.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: widget.role)
          .where('status', whereIn: ['active', 'inactive']).get();
      setState(() {
        _users = snap.docs.map((d) => d.data()).toList();
        _filteredUsers = _searchController.text.trim().isEmpty
            ? _users
            : _users.where((user) {
                final name = (user['name'] ?? '').toString().toLowerCase();
                return name.contains(_searchController.text.trim().toLowerCase());
              }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeletedUsersScreen(
                    role: widget.role,
                    title: widget.title,
                  ),
                ),
              );
            },
            child: const Text(
              'Deleted',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InviteFormScreen(role: widget.role),
            ),
          );
          _loadUsers();
        },
        backgroundColor: primaryColor,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: primaryColor),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF)),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _users.isEmpty ? _roleIcon : Icons.search_off_rounded,
                              size: 64,
                              color: primaryColor.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _users.isEmpty
                                  ? 'No ${widget.title} yet'
                                  : 'No results found',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _users.isEmpty
                                  ? 'Tap + to send an invite'
                                  : 'Try a different name',
                              style: const TextStyle(fontSize: 14, color: primaryColor),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadUsers,
                        color: primaryColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            return _UserCard(
                              user: _filteredUsers[index],
                              roleIcon: _roleIcon,
                              onChanged: _loadUsers,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final IconData roleIcon;
  final VoidCallback onChanged;

  static const Color primaryColor = Color(0xFF1F8A70);

  const _UserCard({
    required this.user,
    required this.roleIcon,
    required this.onChanged,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  static const Color primaryColor = Color(0xFF1F8A70);
  bool _hasTimingSetting = false;
  String _startTime = '';
  String _endTime = '';

  // ── NAYA: Fee state ──
  bool _hasFeeSetting = false;
  double _inPersonFee = 0;
  double _walkInFee = 0;
  double _videoCallFee = 0;

  @override
  void initState() {
    super.initState();
    if (widget.user['role'] == 'doctor') {
      _checkTiming();
      _checkFee(); // NAYA
    }
  }

  Future<void> _checkTiming() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('doctor_settings')
          .doc(widget.user['uid'])
          .get();
      if (doc.exists) {
        setState(() {
          _hasTimingSetting = true;
          _startTime = doc.data()?['appointmentStartTime'] ?? '';
          _endTime = doc.data()?['appointmentEndTime'] ?? '';
        });
      }
    } catch (e) {}
  }

  // ── NAYA: Doctor ki fee check karta hai ──
  Future<void> _checkFee() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('doctor_consultation_fees')
          .doc(widget.user['uid'])
          .get();
      if (doc.exists) {
        setState(() {
          _hasFeeSetting = true;
          _inPersonFee = (doc.data()?['inPersonFee'] ?? 0).toDouble();
          _walkInFee = (doc.data()?['walkInFee'] ?? 0).toDouble();
          _videoCallFee = (doc.data()?['videoCallFee'] ?? 0).toDouble();
        });
      }
    } catch (e) {}
  }

  void _showSetTimingDialog(BuildContext context) {
    TimeOfDay startTime = _hasTimingSetting
        ? _parseTime(_startTime)
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = _hasTimingSetting
        ? _parseTime(_endTime)
        : const TimeOfDay(hour: 17, minute: 0);

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Set Timing',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.access_time_rounded, color: primaryColor),
                title: const Text('Start Time',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                subtitle: Text(
                  startTime.format(context),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E)),
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: startTime,
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: primaryColor,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setDialogState(() => startTime = picked);
                  }
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time_filled_rounded,
                    color: primaryColor),
                title: const Text('End Time',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                subtitle: Text(
                  endTime.format(context),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E)),
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: endTime,
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: primaryColor,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setDialogState(() => endTime = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: primaryColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${startTime.format(context)} → ${endTime.format(context)}',
                      style: const TextStyle(
                          color: primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final start =
                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                final end =
                    '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                await FirebaseFirestore.instance
                    .collection('doctor_settings')
                    .doc(widget.user['uid'])
                    .set({
                  'doctorId': widget.user['uid'],
                  'appointmentStartTime': start,
                  'appointmentEndTime': end,
                  'updatedAt': DateTime.now(),
                });

                Navigator.pop(context);
                _checkTiming();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Timing saved successfully!'),
                    backgroundColor: primaryColor,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── NAYA: Set/Update Fee dialog — "Set Timing" jaisa hi pattern ──
  void _showSetFeeDialog(BuildContext context) {
    final inPersonController = TextEditingController(
        text: _hasFeeSetting ? _inPersonFee.toStringAsFixed(0) : '');
    final walkInController = TextEditingController(
        text: _hasFeeSetting ? _walkInFee.toStringAsFixed(0) : '');
    final videoCallController = TextEditingController(
        text: _hasFeeSetting ? _videoCallFee.toStringAsFixed(0) : '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Set Consultation Fee',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.user['name'] ?? '',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primaryColor)),
              const SizedBox(height: 16),
              _feeField('In-Person Fee', inPersonController),
              const SizedBox(height: 12),
              _feeField('Walk-In Fee', walkInController),
              const SizedBox(height: 12),
              _feeField('Video Call Fee', videoCallController),
              const SizedBox(height: 10),
              Text(
                'Suggested: Walk-in ≥ In-person ≥ Video call',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final inPerson =
                  double.tryParse(inPersonController.text.trim()) ?? 0;
              final walkIn = double.tryParse(walkInController.text.trim()) ?? 0;
              final videoCall =
                  double.tryParse(videoCallController.text.trim()) ?? 0;

// ── NAYA: Teeno fees zaroori hain, ek bhi 0/empty na ho ──
              if (inPerson <= 0 || walkIn <= 0 || videoCall <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Please set all three fees — In-Person, Walk-In, and Video Call.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return; // Save mat karo
              }

              await FirebaseFirestore.instance
                  .collection('doctor_consultation_fees')
                  .doc(widget.user['uid'])
                  .set({
                'doctorId': widget.user['uid'],
                'inPersonFee': inPerson,
                'walkInFee': walkIn,
                'videoCallFee': videoCall,
                'updatedBy': FirebaseAuth.instance.currentUser?.uid,
                'updatedAt': DateTime.now(),
              });

              Navigator.pop(context);
              _checkFee();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Fee saved successfully!'),
                  backgroundColor: primaryColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── NAYA: helper widget, ManageConsultationFeesScreen jaisa hi ──
  Widget _feeField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: 'Rs ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: primaryColor),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  void _showEditDialog(BuildContext context) {
    final nameController =
        TextEditingController(text: widget.user['name'] ?? '');
    final phoneController =
        TextEditingController(text: widget.user['phone'] ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit User',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              await AdminService().editUserInfo(
                userId: widget.user['uid'],
                newName: nameController.text.trim(),
                newPhone: phoneController.text.trim(),
                newRole: widget.user['role'],
              );
              Navigator.pop(context);
              widget.onChanged();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete User',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
        content: Text(
            'Are you sure you want to delete ${widget.user['name']}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              await AdminService().deleteUser(widget.user['uid']);
              Navigator.pop(context);
              widget.onChanged();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.user['status'] == 'active';
    final bool isDoctor = widget.user['role'] == 'doctor';
    final AdminService adminService = AdminService();

    // NAYA: doctor "incomplete" hai agar timing YA fee, dono mein se
    // koi bhi missing ho — dono ke bina patient ko dikhta hi nahi.
    final bool isIncomplete =
        isDoctor && (!_hasTimingSetting || !_hasFeeSetting);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isIncomplete
            ? Border.all(color: const Color(0xFFF4B400), width: 1.5)
            : null,
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
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isIncomplete
                    ? const Color(0xFFFEF7E0)
                    : primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.roleIcon,
                  color: isIncomplete ? const Color(0xFFB8860B) : primaryColor,
                  size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.user['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(widget.user['email'] ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                  if (widget.user['phone'] != null &&
                      widget.user['phone'] != '')
                    Text(widget.user['phone'],
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  if (isDoctor && _hasTimingSetting)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 12, color: primaryColor),
                          const SizedBox(width: 4),
                          Text(
                            '$_startTime - $_endTime',
                            style: const TextStyle(
                                fontSize: 11,
                                color: primaryColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  if (isDoctor && !_hasTimingSetting)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Timing not set',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFB8860B),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  // ── NAYA: Fee info ──
                  if (isDoctor && _hasFeeSetting)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.payments_rounded,
                              size: 12, color: primaryColor),
                          const SizedBox(width: 4),
                          Text(
                            'In: Rs ${_inPersonFee.toStringAsFixed(0)} · Walk: Rs ${_walkInFee.toStringAsFixed(0)} · Video: Rs ${_videoCallFee.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: primaryColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  if (isDoctor && !_hasFeeSetting)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Fee not set',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFB8860B),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFDCEFE9)
                        : const Color(0xFFFCE8E6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive ? primaryColor : const Color(0xFFDB4437),
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
                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    if ((value == 'deactivate' || value == 'delete') &&
                        widget.user['uid'] == currentUid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'You cannot deactivate or delete your own account.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (value == 'edit') {
                      _showEditDialog(context);
                    } else if (value == 'timing') {
                      _showSetTimingDialog(context);
                    } else if (value == 'fee') {
                      // NAYA
                      _showSetFeeDialog(context);
                    } else if (value == 'deactivate') {
                      await adminService.deactivateUser(widget.user['uid']);
                      widget.onChanged();
                    } else if (value == 'activate') {
                      await adminService.reactivateUser(widget.user['uid']);
                      widget.onChanged();
                    } else if (value == 'reset') {
                      await adminService
                          .resetUserPassword(widget.user['email']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password reset email sent!'),
                          backgroundColor: primaryColor,
                        ),
                      );
                    } else if (value == 'delete') {
                      _showDeleteConfirm(context);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, color: primaryColor, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ]),
                    ),
                    if (isDoctor)
                      PopupMenuItem(
                        value: 'timing',
                        child: Row(children: [
                          const Icon(Icons.access_time_rounded,
                              color: primaryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(_hasTimingSetting
                              ? 'Update Timing'
                              : 'Set Timing'),
                        ]),
                      ),
                    // ── NAYA: Set/Update Fee — sirf doctor ke liye ──
                    if (isDoctor)
                      PopupMenuItem(
                        value: 'fee',
                        child: Row(children: [
                          const Icon(Icons.payments_rounded,
                              color: primaryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(_hasFeeSetting ? 'Update Fee' : 'Set Fee'),
                        ]),
                      ),
                    if (isActive)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Row(children: [
                          Icon(Icons.block_rounded,
                              color: Color(0xFFF4B400), size: 18),
                          SizedBox(width: 8),
                          Text('Deactivate'),
                        ]),
                      )
                    else
                      const PopupMenuItem(
                        value: 'activate',
                        child: Row(children: [
                          Icon(Icons.check_circle_rounded,
                              color: Color(0xFF0F9D58), size: 18),
                          SizedBox(width: 8),
                          Text('Activate'),
                        ]),
                      ),
                    const PopupMenuItem(
                      value: 'reset',
                      child: Row(children: [
                        Icon(Icons.lock_reset_rounded,
                            color: Color(0xFF1A73E8), size: 18),
                        SizedBox(width: 8),
                        Text('Reset Password'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded,
                            color: Color(0xFFDB4437), size: 18),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Color(0xFFDB4437))),
                      ]),
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

class DeletedUsersScreen extends StatefulWidget {
  final String role;
  final String title;

  const DeletedUsersScreen({
    super.key,
    required this.role,
    required this.title,
  });

  @override
  State<DeletedUsersScreen> createState() => _DeletedUsersScreenState();
}

class _DeletedUsersScreenState extends State<DeletedUsersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _deletedUsers = [];
  bool _isLoading = true;

  static const Color primaryColor = Color(0xFF1F8A70);
  static const Color bgColor = Color(0xFFF4F7F6);

  @override
  void initState() {
    super.initState();
    _loadDeletedUsers();
  }

  Future<void> _loadDeletedUsers() async {
    setState(() => _isLoading = true);
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: widget.role)
          .where('status', isEqualTo: 'deleted')
          .get();
      setState(() {
        _deletedUsers = snap.docs.map((d) => d.data()).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Deleted ${widget.title}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : _deletedUsers.isEmpty
              ? const Center(
                  child: Text('No deleted users',
                      style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _deletedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _deletedUsers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
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
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.person_off_rounded,
                                color: Colors.red, size: 24),
                          ),
                          const SizedBox(width: 14),
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
                                Text(user['email'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280))),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Deleted',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}