import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedbackScreen extends StatefulWidget {
  final String appointmentId;
  final String doctorId;
  final String doctorName;
  final String specialization;

  const FeedbackScreen({
    super.key,
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    required this.specialization,
  });

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  int _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      _showError('Please select a rating');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not logged in');

      // feedbackId = appointmentId — schema rule, prevents duplicate
      // feedback for the same appointment.
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.appointmentId)
          .set({
        'feedbackId': widget.appointmentId,
        'appointmentId': widget.appointmentId,
        'patientId': uid,
        'doctorId': widget.doctorId,
        'rating': _rating,
        'comment': _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Thank you for your feedback'),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context, true); // true = feedback submitted
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showError('Error submitting feedback: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very good';
      case 5:
        return 'Excellent';
      default:
        return 'Tap a star to rate';
    }
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildDoctorCard(),
                    const SizedBox(height: 28),
                    _buildRatingCard(),
                    const SizedBox(height: 20),
                    _buildCommentCard(),
                  ],
                ),
              ),
            ),
            _buildSubmitBar(),
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
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Give Feedback',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDoctorCard() {
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: _primary.withOpacity(0.15),
          child: Text(
            widget.doctorName.isNotEmpty
                ? widget.doctorName[0].toUpperCase()
                : '?',
            style: const TextStyle(
                color: _primary, fontWeight: FontWeight.bold, fontSize: 26),
          ),
        ),
        const SizedBox(height: 12),
        Text(widget.doctorName,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2F3A))),
        const SizedBox(height: 2),
        Text(widget.specialization,
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ],
    );
  }

  Widget _buildRatingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          const Text('How was your consultation?',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = starIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    starIndex <= _rating ? Icons.star : Icons.star_border,
                    color: starIndex <= _rating
                        ? Colors.amber
                        : Colors.grey.shade400,
                    size: 38,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(_ratingLabel,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _rating == 0 ? Colors.grey : _primary)),
        ],
      ),
    );
  }

  Widget _buildCommentCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Additional comments (optional)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Share your experience...',
              filled: true,
              fillColor: const Color(0xFFF4F7F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitFeedback,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : const Text('Submit Feedback',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
