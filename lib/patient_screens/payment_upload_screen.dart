import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

/// PAYMENT UPLOAD SCREEN (Phase 1)
///
/// Booking flow: patient slot select → "Request appointment" dabaye →
/// appointment (Requested) + slot (HELD) ban jaate hain (transaction) →
/// FORAN yeh screen khulti hai.
///
/// Yahan patient:
///   1. EasyPaisa number + amount dekhta hai
///   2. Paisa bhej ke screenshot upload karta hai (gallery/PDF, base64)
///   3. Submit → payments record (Pending) bane
///
/// Agar patient "Cancel" dabaye (irada badal gaya):
///   → appointment + slot DELETE (clean exit), koi payment record nahi
///
/// Storage use NAHI hoti — screenshot base64 me Firestore me
/// (Blaze plan avoid). Image compress karke size chota rakhte hain.
class PaymentUploadScreen extends StatefulWidget {
  final String appointmentId;
  final String slotId;
  final num amount;
  final String doctorName;

  const PaymentUploadScreen({
    super.key,
    required this.appointmentId,
    required this.slotId,
    required this.amount,
    required this.doctorName,
  });

  @override
  State<PaymentUploadScreen> createState() => _PaymentUploadScreenState();
}

class _PaymentUploadScreenState extends State<PaymentUploadScreen> {
  static const Color _primary = Color(0xFF1F8A70);
  static const Color _primaryDark = Color(0xFF0D6B5A);

  // Hospital ka EasyPaisa (baad me badal sakte ho)
  static const String _easypaisaNumber = '03165853792';
  static const String _easypaisaName = 'Family Well Care Hospital';

  final _transactionIdController = TextEditingController();
  final _picker = ImagePicker();

  String? _screenshotBase64; // compressed image base64
  bool _isSubmitting = false;
  bool _cancelling = false;

  @override
  void dispose() {
    _transactionIdController.dispose();
    super.dispose();
  }

  // Gallery se image pick + compress + base64
  Future<void> _pickScreenshot() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery, // sirf gallery — camera nahi
        maxWidth: 1000, // compress: bara resolution chhota
        maxHeight: 1000,
        imageQuality: 60, // JPEG quality — size chota rakhta hai
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      // Firestore doc limit ~1MB. Base64 ~33% bada hota hai.
      // ~700KB base64 tak theek. Agar zyada, warn.
      if (bytes.lengthInBytes > 700 * 1024) {
        _showError('Image too large. Please choose a smaller screenshot.');
        return;
      }

      setState(() => _screenshotBase64 = base64Encode(bytes));
    } catch (e) {
      _showError('Could not load image: $e');
    }
  }

  // Submit — payments record (Pending)
  Future<void> _submitPayment() async {
    if (_screenshotBase64 == null) {
      _showError('Please upload your payment screenshot');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final paymentRef =
          FirebaseFirestore.instance.collection('payments').doc();

      await paymentRef.set({
        'paymentId': paymentRef.id,
        'appointmentId': widget.appointmentId,
        'patientId': uid,
        'type': 'Consultation',
        'amount': widget.amount,
        'paymentMethod': 'Online',
        'status': 'Pending',
        'referenceId': null, // Consultation => null
        'transactionId': _transactionIdController.text.trim().isEmpty
            ? null
            : _transactionIdController.text.trim(),
        'screenshotBase64': _screenshotBase64,
        'refundAmount': null,
        'refundPaid': false,
        'verifiedBy': null,
        'createdAt': FieldValue.serverTimestamp(),
        'paidAt': null,
      });

      if (!mounted) return;
      // Success → back to previous (booking done)
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Payment submitted! Awaiting reception confirmation.'),
        backgroundColor: _primary,
      ));
    } catch (e) {
      _showError('Could not submit payment: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Cancel — clean exit: appointment + slot delete
  Future<void> _cancelBooking() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel booking?'),
        content: const Text(
            'Your slot will be released and you will need to book again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, continue'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, cancel',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _cancelling = true);
    try {
      final apptRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId);
      final slotRef =
          FirebaseFirestore.instance.collection('slots').doc(widget.slotId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // reads pehle
        final apptSnap = await transaction.get(apptRef);
        final slotSnap = await transaction.get(slotRef);
        // writes baad — dono delete (clean exit)
        if (apptSnap.exists) transaction.delete(apptRef);
        if (slotSnap.exists) transaction.delete(slotRef);
      });

      if (!mounted) return;
      Navigator.pop(context, false); // booking cancelled
    } catch (e) {
      _showError('Could not cancel: $e');
      setState(() => _cancelling = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFDB4437),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Back button ko intercept karo — warna slot HELD reh jayega
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isSubmitting && !_cancelling) _cancelBooking();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7F6),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAmountCard(),
                      const SizedBox(height: 20),
                      _buildInstructions(),
                      const SizedBox(height: 20),
                      const Text('Transaction ID (optional)',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2F3A))),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _transactionIdController,
                        decoration: InputDecoration(
                          hintText: 'e.g. EasyPaisa TID',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Payment screenshot',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2F3A))),
                      const SizedBox(height: 8),
                      _buildScreenshotPicker(),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
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
            onTap: _cancelBooking, // back = cancel (with confirm)
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
          const Text('Payment',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Amount to pay',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Rs. ${widget.amount}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Consultation — ${widget.doctorName}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to pay',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2F3A))),
          const SizedBox(height: 12),
          _payRow('1', 'Send Rs. ${widget.amount} on EasyPaisa to:'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDCEFE9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_easypaisaNumber,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _primaryDark)),
                Text(_easypaisaName,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _payRow('2', 'Take a screenshot of the confirmation'),
          const SizedBox(height: 8),
          _payRow('3', 'Upload it below and submit'),
        ],
      ),
    );
  }

  Widget _payRow(String num, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration:
              const BoxDecoration(color: _primary, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(num,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ),
      ],
    );
  }

  Widget _buildScreenshotPicker() {
    if (_screenshotBase64 != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(_screenshotBase64!),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickScreenshot,
            icon: const Icon(Icons.refresh, size: 16, color: _primary),
            label: const Text('Change screenshot',
                style: TextStyle(color: _primary)),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _pickScreenshot,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _primary.withValues(alpha: 0.4),
              width: 1.5,
              style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_upload_outlined,
                size: 36, color: _primary.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            const Text('Tap to upload screenshot',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const Text('(from gallery)',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: (_isSubmitting || _cancelling) ? null : _cancelBooking,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFD9534F)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _cancelling
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Color(0xFFD9534F), strokeWidth: 2.5))
                  : const Text('Cancel',
                      style: TextStyle(
                          color: Color(0xFFD9534F),
                          fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _cancelling) ? null : _submitPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Submit Payment',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
