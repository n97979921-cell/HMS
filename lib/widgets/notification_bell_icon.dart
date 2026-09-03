import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/notifications_screen.dart';

/// NOTIFICATION BELL ICON — reusable widget, har dashboard mein
/// same tarah use hoga (patient, doctor, admin, receptionist, lab staff).
///
/// Kaam:
///  - Current logged-in user ki `isRead: false` notifications ka
///    count real-time (StreamBuilder) nikalta hai.
///  - Agar count > 0 ho to bell ke upar red badge dikhata hai
///    (9 se zyada ho to "9+" likh deta hai).
///  - Tap karne par NotificationsScreen open hoti hai — ye pehle se
///    jo navigation logic tha, wahi hai, sirf UI wrap kiya gaya hai.
///
/// Kisi bhi dashboard mein purana bell-icon code hata ke iski jagah
/// bas `const NotificationBellIcon()` laga do. Agar tumhare dashboard
/// mein bell white background pe hai (dark AppBar jaisa) to defaults
/// (white icon, halka transparent background) sahi rahenge. Agar
/// light background (white card) pe bell hai to `iconColor` aur
/// `backgroundColor` params se color change kar sakte ho.
class NotificationBellIcon extends StatelessWidget {
  final Color iconColor;
  final Color backgroundColor;
  final double size;

  const NotificationBellIcon({
    super.key,
    this.iconColor = Colors.white,
    this.backgroundColor = const Color(0x26FFFFFF), // white ~15% opacity
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // uid null ho (edge case) to khaali stream — badge kabhi crash nahi hoga
    final Stream<QuerySnapshot> unreadStream = uid == null
        ? const Stream<QuerySnapshot>.empty()
        : FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .where('isRead', isEqualTo: false)
            .snapshots();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: unreadStream,
        builder: (context, snapshot) {
          final unreadCount = snapshot.data?.docs.length ?? 0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  color: iconColor,
                  size: size,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}