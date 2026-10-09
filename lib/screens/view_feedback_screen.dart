import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'View Feedback',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDB4437).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Error loading feedback: ${snapshot.error}',
                    style: const TextStyle(
                      color: Color(0xFFDB4437),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _primary));
          }

          final docs = snapshot.data?.docs ?? [];

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _enrichWithNames(docs),
            builder: (context, nameSnapshot) {
              if (nameSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _primary));
              }

              final feedbackList = nameSnapshot.data ?? [];
              final avgRating = _averageRating(feedbackList);

              return Column(
                children: [
                  // Summary header
                  if (feedbackList.isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4B400).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.star_rounded,
                                color: Color(0xFFF4B400), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  avgRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                Text(
                                  'Average rating \u2022 ${feedbackList.length} review${feedbackList.length == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ── NAYA: Delete All — jo bhi feedback abhi
                          // list mein dikh raha hai, sab delete. Koi
                          // confirmation nahi.
                          TextButton.icon(
                            onPressed: () =>
                                _deleteAllFeedback(context, feedbackList),
                            icon: const Icon(Icons.delete_sweep_outlined,
                                size: 16, color: Color(0xFFDB4437)),
                            label: const Text('Delete All',
                                style: TextStyle(
                                    color: Color(0xFFDB4437),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),

                  Expanded(
                    child: feedbackList.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.6,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.star_outline_rounded,
                                          size: 64,
                                          color: _primary.withOpacity(0.3)),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No feedback yet',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Patient reviews will appear here',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF9CA3AF)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: feedbackList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
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

  static const Color _primary = Color(0xFF1F8A70);

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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
          // Top row: patient name + rating stars + delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_outline_rounded,
                    color: _primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  feedback['patientName'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 16,
                    color: const Color(0xFFF4B400),
                  );
                }),
              ),
              // ── NAYA: delete icon, har card ke top par — admin kisi
              // bhi feedback ko individually delete kar sake.
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDB4437).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.delete_outline,
                      size: 16, color: Color(0xFFDB4437)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Doctor row
          Row(
            children: [
              const Icon(Icons.medical_services_outlined,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              const Text(
                'Doctor: ',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              Expanded(
                child: Text(
                  feedback['doctorName'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Date row
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Text(
                _formatDate(feedback['createdAt']),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),

          // Comment (if present)
          if (comment != null && comment != '') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                comment,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
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