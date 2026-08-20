import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// NOTIFICATIONS SCREEN — reusable, sab 4 roles ke liye same.
///
/// Sirf current logged-in user (FirebaseAuth uid) ki notifications
/// dikhata hai — koi extra parameter nahi chahiye, is liye har role
/// se seedha `NotificationsScreen()` navigate ho sakti hai.
///
/// Tap karne par isRead: true ho jata hai. Type ke hisaab se icon.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .get();

      final result = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'notificationId': doc.id,
          'type': data['type'] ?? '',
          'referenceId': data['referenceId'],
          'message': data['message'] ?? '',
          'isRead': data['isRead'] ?? false,
          'createdAt': data['createdAt'],
        };
      }).toList();

      // Newest first
      result.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        if (aTs is! Timestamp || bTs is! Timestamp) return 0;
        return bTs.compareTo(aTs);
      });

      setState(() {
        _notifications = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
      setState(() {
        final n = _notifications.firstWhere(
            (n) => n['notificationId'] == notificationId,
            orElse: () => {});
        if (n.isNotEmpty) n['isRead'] = true;
      });
    } catch (_) {
      // Silent — read-status miss hone se koi bara nuqsan nahi
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Appointment':
        return Icons.calendar_today_outlined;
      case 'Lab':
        return Icons.science_outlined;
      case 'Room':
      case 'RoomRecommendation':
        return Icons.bed_outlined;
      case 'Payment':
        return Icons.payments_outlined;
      case 'VideoConsultation':
        return Icons.videocam_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'Appointment':
        return const Color(0xFF1F8A70);
      case 'Lab':
        return const Color(0xFF1565C0);
      case 'Room':
      case 'RoomRecommendation':
        return const Color(0xFF7E57C2);
      case 'Payment':
        return const Color(0xFFB8860B);
      case 'VideoConsultation':
        return const Color(0xFFD9534F);
      default:
        return Colors.grey;
    }
  }

  String _timeAgo(dynamic ts) {
    if (ts is! Timestamp) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary))
                  : _notifications.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadNotifications,
                          color: _primary,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _card(_notifications[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Notifications',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_outlined,
              size: 64, color: _primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No notifications yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> n) {
    final isRead = n['isRead'] == true;
    final color = _colorForType(n['type']);

    return GestureDetector(
      onTap: () {
        if (!isRead) _markAsRead(n['notificationId']);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFF0FAF7),
          borderRadius: BorderRadius.circular(14),
          border: isRead
              ? null
              : Border.all(color: _primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(_iconForType(n['type']), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n['message'],
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isRead ? FontWeight.w400 : FontWeight.w600,
                          color: const Color(0xFF1A2F3A))),
                  const SizedBox(height: 4),
                  Text(_timeAgo(n['createdAt']),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
