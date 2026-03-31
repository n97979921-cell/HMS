import 'package:flutter/material.dart';

class HospitalLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double w = size.width;
    final double h = size.height;

    // Outer triangle/drop shape (light teal outline)
    final Paint outlinePaint = Paint()
      ..color = const Color(0xFF7ECACA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final Path outerPath = Path();
    outerPath.moveTo(cx, h * 0.02);
    outerPath.lineTo(w * 0.92, h * 0.55);
    outerPath.quadraticBezierTo(w * 0.92, h * 0.82, cx, h * 0.82);
    outerPath.quadraticBezierTo(w * 0.08, h * 0.82, w * 0.08, h * 0.55);
    outerPath.close();
    canvas.drawPath(outerPath, outlinePaint);

    // Inner filled drop shape (gradient teal)
    final Paint fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4AADAD), Color(0xFF1A6B6B)],
      ).createShader(Rect.fromLTWH(0, h * 0.12, w, h * 0.72))
      ..style = PaintingStyle.fill;

    final Path innerPath = Path();
    innerPath.moveTo(cx, h * 0.14);
    innerPath.lineTo(w * 0.84, h * 0.54);
    innerPath.quadraticBezierTo(w * 0.84, h * 0.78, cx, h * 0.78);
    innerPath.quadraticBezierTo(w * 0.16, h * 0.78, w * 0.16, h * 0.54);
    innerPath.close();
    canvas.drawPath(innerPath, fillPaint);

    // White cross
    final Paint crossPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final double cw = w * 0.11;
    final double ch = h * 0.28;
    final double ccx = cx;
    final double ccy = h * 0.46;

    // Vertical
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ccx, ccy), width: cw, height: ch),
        const Radius.circular(4),
      ),
      crossPaint,
    );
    // Horizontal
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ccx, ccy), width: ch, height: cw),
        const Radius.circular(4),
      ),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}