import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_ui.dart';

class ViewFeedbackScreen extends StatefulWidget {
  const ViewFeedbackScreen({super.key});

  @override
  State<ViewFeedbackScreen> createState() => _ViewFeedbackScreenState();
}

class _ViewFeedbackScreenState extends State<ViewFeedbackScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _bg = Color(0xFFF4F7F6);

  final Map<String, String> _userNameCache = {};

  Query<Map<String, dynamic>> _buildQuery() {
    return FirebaseFirestore.instance
        .collection('feedback')
        .orderBy('createdAt', descending: true);
  }

  Future<String> _getUserName(String? userId) async {
    if (userId == null || userId.isEmpty) return 'N/A';
    if (_userNameCache.containsKey(userId)) {
      return _userNameCache[userId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final name = doc.exists ? (doc.data()?['name'] ?? 'Unknown') : 'Unknown';
      _userNameCache[userId] = name;
      return name;
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<List<Map<String, dynamic>>> _enrichWithNames(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final List<Map<String, dynamic>> results = [];
    for (final doc in docs) {
      final data = doc.data();
      final patientName = await _getUserName(data['patientId']);
      final doctorName = await _getUserName(data['doctorId']);
      results.add({
        'id': doc.id,
        ...data,
        'patientName': patientName,
        'doctorName': doctorName,
      });
    }
    return results;
  }

  // Computes the average rating across all loaded feedback,
  // shown as a quick summary at the top of the list.
  double _averageRating(List<Map<String, dynamic>> feedbackList) {
    if (feedbackList.isEmpty) return 0;
    final total = feedbackList.fold<int>(
        0, (sum, f) => sum + ((f['rating'] ?? 0) as num).toInt());
    return total / feedbackList.length;
  }

  // ── NAYA: Delete (single) — koi confirmation nahi, seedha permanent
  //    delete. Har card ke top par icon hamesha available. StreamBuilder
  //    khud-ba-khud list refresh kar dega.
  Future<void> _deleteFeedback(BuildContext context, String id) async {
    try {
      await FirebaseFirestore.instance.collection('feedback').doc(id).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Feedback deleted'),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting: $e'),
          backgroundColor: const Color(0xFFDB4437),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── NAYA: Delete All — jo bhi feedback is waqt list mein dikh raha
  //    hai, sab ek batch write mein permanent delete — bina
  //    confirmation ke.
  Future<void> _deleteAllFeedback(
      BuildContext context, List<Map<String, dynamic>> feedbackList) async {
    if (feedbackList.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final f in feedbackList) {
        batch.delete(
            FirebaseFirestore.instance.collection('feedback').doc(f['id']));
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${feedbackList.length} feedback record(s) deleted'),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting all: $e'),
          backgroundColor: const Color(0xFFDB4437),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Widget _stars(int filled, double size, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: color,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                const AppHeader(title: 'Feedback', subtitle: 'Patient reviews'),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Error loading feedback: ${snapshot.error}',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Column(
              children: [
                AppHeader(title: 'Feedback', subtitle: 'Patient reviews'),
                Expanded(
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.teal)),
                ),
              ],
            );
          }

          final docs = snapshot.data?.docs ?? [];

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _enrichWithNames(docs),
            builder: (context, nameSnapshot) {
              if (nameSnapshot.connectionState == ConnectionState.waiting) {
                return const Column(
                  children: [
                    AppHeader(title: 'Feedback', subtitle: 'Patient reviews'),
                    Expanded(
                      child: Center(
                          child:
                              CircularProgressIndicator(color: AppColors.teal)),
                    ),
                  ],
                );
              }

              final feedbackList = nameSnapshot.data ?? [];
              final avgRating = _averageRating(feedbackList);
              final reviewText =
                  '${feedbackList.length} review${feedbackList.length == 1 ? '' : 's'}';

              return Column(
                children: [
                  // Summary header
                  AppHeader(
                    title: 'Feedback',
                    subtitle: 'Patient reviews',
                    bottom: feedbackList.isEmpty
                        ? null
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: AppColors.star.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.star_rounded,
                                      color: AppColors.star, size: 30),
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          avgRating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 30,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '/ 5 average',
                                          style: TextStyle(
                                            color: AppColors.headerMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _stars(avgRating.round(), 15,
                                            AppColors.star),
                                        const SizedBox(width: 8),
                                        Text(
                                          reviewText,
                                          style: const TextStyle(
                                            color: AppColors.headerMuted,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ),

                  if (feedbackList.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              reviewText,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.teal,
                              ),
                            ),
                          ),
                          AppDeleteAllButton(
                            onTap: () =>
                                _deleteAllFeedback(context, feedbackList),
                          ),
                        ],
                      ),
                    ),

                  Expanded(
                    child: feedbackList.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(20),
                            children: const [
                              AppEmptyState(
                                icon: Icons.star_outline_rounded,
                                title: 'No feedback yet',
                                subtitle: 'Patient reviews will appear here',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            itemCount: feedbackList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final fb = feedbackList[index];
                              return _FeedbackCard(
                                feedback: fb,
                                onDelete: () =>
                                    _deleteFeedback(context, fb['id']),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> feedback;
  final VoidCallback onDelete;

  const _FeedbackCard({required this.feedback, required this.onDelete});

  String _formatDate(dynamic ts) {
    if (ts == null) return 'N/A';
    try {
      final date = (ts as Timestamp).toDate();
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rating = ((feedback['rating'] ?? 0) as num).toInt();
    final comment = feedback['comment'];
    final String name = feedback['patientName'] ?? 'N/A';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: patient name + rating stars + delete
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.tealSoft,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        return Icon(
                          i < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 16,
                          color: const Color(0xFFE0A800),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              AppDeleteButton(size: 34, onTap: onDelete),
            ],
          ),
          const SizedBox(height: 12),
          AppInfoRow(
              label: 'Doctor',
              value: feedback['doctorName'] ?? 'N/A',
              labelWidth: 56),
          AppInfoRow(
              label: 'Date',
              value: _formatDate(feedback['createdAt']),
              labelWidth: 56),

          // Comment (if present)
          if (comment != null && comment != '') ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '\u201C$comment\u201D',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF3B4F53),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
