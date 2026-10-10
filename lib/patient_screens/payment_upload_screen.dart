import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import '../widgets/app_ui.dart';

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
        backgroundColor: AppColors.teal,
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel booking?'),
        content: const Text(
            'Your slot will be released and you will need to book again.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, continue'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB23A1E), elevation: 0),
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
      backgroundColor: const Color(0xFF9A2E16),
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
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAmountCard(),
                    const SizedBox(height: 12),
                    _buildInstructions(),
                    const SizedBox(height: 20),
                    _sectionLabel('TRANSACTION ID (OPTIONAL)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _transactionIdController,
                      decoration: InputDecoration(
                        hintText: 'e.g. EasyPaisa TID',
                        hintStyle: const TextStyle(color: AppColors.faint),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppColors.teal, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('PAYMENT SCREENSHOT'),
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
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.muted));
  }

  Widget _buildHeader() {
    return AppHeader(
      title: 'Payment',
      subtitle: 'EasyPaisa · upload screenshot',
      onBack: _cancelBooking, // back = cancel (with confirm)
    );
  }

  Widget _buildAmountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Amount to pay',
              style: TextStyle(
                  color: AppColors.headerMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Rs. ${widget.amount}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Consultation — ${widget.doctorName}',
              style: const TextStyle(
                  color: Color(0xFFD5E6E4),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to pay',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          const SizedBox(height: 12),
          _payRow('1', 'Send Rs. ${widget.amount} on EasyPaisa to:'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 34),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_easypaisaNumber,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF0B5E57))),
                const SizedBox(height: 2),
                Text(_easypaisaName,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _payRow('2', 'Take a screenshot of the confirmation'),
          const SizedBox(height: 10),
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
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
              color: AppColors.teal, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(num,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: AppColors.text)),
          ),
        ),
      ],
    );
  }

  Widget _buildScreenshotPicker() {
    if (_screenshotBase64 != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: AppColors.bg,
                child: Image.memory(
                  base64Decode(_screenshotBase64!),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                      color: AppColors.mint, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      size: 16, color: AppColors.header),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Screenshot attached',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickScreenshot,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 16, color: AppColors.teal),
                    SizedBox(width: 6),
                    Text('Change screenshot',
                        style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _pickScreenshot,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFB9CFCC), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppIconTile(
              icon: Icons.cloud_upload_outlined,
              color: AppColors.teal,
              background: AppColors.tealSoft,
            ),
            const SizedBox(height: 8),
            const Text('Tap to upload screenshot',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 2),
            const Text('(from gallery)',
                style: TextStyle(fontSize: 12, color: AppColors.faint)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed:
                    (_isSubmitting || _cancelling) ? null : _cancelBooking,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFF0C9BE)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _cancelling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Color(0xFF9A2E16), strokeWidth: 2.5))
                    : const Text('Cancel',
                        style: TextStyle(
                            color: Color(0xFF9A2E16),
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed:
                    (_isSubmitting || _cancelling) ? null : _submitPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.header,
                  disabledBackgroundColor: AppColors.header.withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
                            fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
