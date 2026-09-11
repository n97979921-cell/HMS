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
///
/// ✅ REAL-TIME: Ab StreamBuilder use karta hai — sirf ek collection
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
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This will permanently delete all your notifications. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
              child: StreamBuilder<QuerySnapshot>(
                stream: _notificationsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _primary),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Something went wrong. Please try again.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    );
                  }

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

                  if (notifications.isEmpty) {
                    return _buildEmpty();
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _card(notifications[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ CHANGED: "Clear all" button add kiya gaya hai, right side pe.
  // Baqi header (back button, title) bilkul same hai.
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
          const Expanded(
            child: Text('Notifications',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: _confirmDeleteAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
            ),
            child: const Text(
              'Clear all',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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

  // ✅ CHANGED: card ab Dismissible mein wrap hai — patient chahe to
  // swipe karke bhi delete kar sakta hai (left ya right). Iske ilawa
  // ek chhota trash icon bhi laga diya gaya hai (jinhe swipe pasand
  // nahi, wo seedha icon tap kar ke delete kar saken). Baqi card ka
  // content (icon, message, time, unread dot) bilkul same hai.
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
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: const Color(0xFFD9534F),
          borderRadius: BorderRadius.circular(14),
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
                  margin: const EdgeInsets.only(top: 4, right: 6),
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                ),
              GestureDetector(
                onTap: () => _deleteNotification(notificationId),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, top: 2),
                  child: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}