import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

/// NOTIFICATIONS SCREEN — reusable, sab 4 roles ke liye same.
///
/// Sirf current logged-in user (FirebaseAuth uid) ki notifications
/// dikhata hai — koi extra parameter nahi chahiye, is liye har role
/// se seedha `NotificationsScreen()` navigate ho sakti hai.
///
/// Tap karne par isRead: true ho jata hai. Type ke hisaab se icon.
///
///  REAL-TIME: Ab StreamBuilder use karta hai — sirf ek collection
/// (`notifications`) se data aata hai, is liye poori screen real-time
/// bana di gayi hai (Rule 1). Naya notification aate hi list khud
/// update ho jayegi, refresh karne ki zaroorat nahi.
///
/// ✅ NEW: Delete support add kiya gaya hai —
///   - Har card pe ek chhota delete (trash) icon — sirf wahi ek
///     notification delete karta hai.
///   - Header mein "Clear all" button — is user ki SAARI
///     notifications ek batch mein delete karta hai (confirmation
///     dialog ke saath, taake galti se sab delete na ho jayen).
/// Baqi poora logic (mark-as-read, real-time stream, icons/colors,
/// time-ago) bilkul waisa hi hai, kuch change nahi hua.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Stream<QuerySnapshot> _notificationsStream;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Agar uid null ho (edge case) to ek khali stream de dete hain
    // taake StreamBuilder crash na ho, sirf "no notifications" dikhe.
    _notificationsStream = uid == null
        ? const Stream.empty()
        : FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .snapshots();
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
      // StreamBuilder khud-ba-khud UI update kar dega jab Firestore
      // mein change ho jayega — koi manual setState() ki zaroorat nahi.
    } catch (_) {
      // Silent — read-status miss hone se koi bara nuqsan nahi
    }
  }

  // ── DELETE: single notification ──
  // Sirf wahi ek document delete hota hai. StreamBuilder khud list
  // se hata dega, koi manual setState() ki zaroorat nahi.
  Future<void> _deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete notification')),
      );
    }
  }

  // ── DELETE: all notifications (this user only) ──
  // Batch delete — pehle is user ki saari notifications fetch karo,
  // phir ek hi batch mein sab delete kar do (single write, atomic).
  Future<void> _deleteAllNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear notifications')),
      );
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Clear all notifications?',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.danger)),
        content: const Text(
          'This will permanently delete all your notifications. This cannot be undone.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              elevation: 0,
            ),
            child: const Text(
              'Clear all',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteAllNotifications();
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
        return AppColors.teal;
      case 'Lab':
        return AppColors.blue;
      case 'Room':
      case 'RoomRecommendation':
        return const Color(0xFF5B3FA8);
      case 'Payment':
        return const Color(0xFF8A6D00);
      case 'VideoConsultation':
        return const Color(0xFF9A2E16);
      default:
        return AppColors.faint;
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
    // Same single stream as before — header bhi isi se unread count
    // dikhata hai (sirf UI), koi nayi query nahi.
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          final notifications = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'notificationId': doc.id,
              'type': data['type'] ?? '',
              'referenceId': data['referenceId'],
              'message': data['message'] ?? '',
              'isRead': data['isRead'] ?? false,
              'createdAt': data['createdAt'],
            };
          }).toList();

          // Newest first — client-side sort (Firestore composite
          // index se bachne ke liye, chhoti list ke liye kaafi hai).
          notifications.sort((a, b) {
            final aTs = a['createdAt'];
            final bTs = b['createdAt'];
            if (aTs is! Timestamp || bTs is! Timestamp) return 0;
            return bTs.compareTo(aTs);
          });

          final unread = notifications.where((n) => n['isRead'] != true).length;

          Widget body;
          if (snapshot.connectionState == ConnectionState.waiting) {
            body = const Center(
              child: CircularProgressIndicator(color: AppColors.teal),
            );
          } else if (snapshot.hasError) {
            body = const Center(
              child: Text(
                'Something went wrong. Please try again.',
                style: TextStyle(color: AppColors.muted),
              ),
            );
          } else if (notifications.isEmpty) {
            body = _buildEmpty();
          } else {
            body = ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _card(notifications[i]),
            );
          }

          return Column(
            children: [
              _buildHeader(
                snapshot.connectionState == ConnectionState.waiting
                    ? null
                    : (unread > 0 ? '$unread unread' : 'All caught up'),
              ),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(String? subtitle) {
    return AppHeader(
      title: 'Notifications',
      subtitle: subtitle,
      trailing: GestureDetector(
        onTap: _confirmDeleteAll,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: const Text(
            'Clear all',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: AppEmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'No notifications yet',
      ),
    );
  }

  // Card: swipe (Dismissible) + trash icon dono pehle jaise hain,
  // sirf look badla hai.
  Widget _card(Map<String, dynamic> n) {
    final isRead = n['isRead'] == true;
    final color = _colorForType(n['type']);
    final notificationId = n['notificationId'] as String;

    return Dismissible(
      key: ValueKey(notificationId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteNotification(notificationId),
      child: GestureDetector(
        onTap: () {
          if (!isRead) _markAsRead(notificationId);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : const Color(0xFFF0FAF7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRead ? Colors.transparent : const Color(0xFF9FD9C9),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(_iconForType(n['type']), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['message'],
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            fontWeight:
                                isRead ? FontWeight.w600 : FontWeight.w800,
                            color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text(_timeAgo(n['createdAt']),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.faint)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (!isRead)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 4, bottom: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  GestureDetector(
                    onTap: () => _deleteNotification(notificationId),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Color(0xFFB8806F),
                      ),
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
