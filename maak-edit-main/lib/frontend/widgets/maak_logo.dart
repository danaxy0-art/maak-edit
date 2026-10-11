import 'package:flutter/material.dart';

/// The "Ma'ak" wordmark + icon shown at the top of the auth/onboarding
/// screens, using the real logo asset at assets/images/logo.png.
class MaakLogo extends StatelessWidget {
  final double iconSize;
  const MaakLogo({super.key, this.iconSize = 40});

  @override
  Widget build(BuildContext context) {
    // The logo image already contains the wordmark, so it's shown on its
    // own without extra text underneath.
    return Image.asset(
      'assets/images/logo.png',
      height: iconSize * 1.6,
      fit: BoxFit.contain,
    );
  }
}

/// Decorative rolling-hills illustration pinned to the bottom of a screen,
/// matching the mockups. Purely decorative — safe to omit.
class MaakBottomHills extends StatelessWidget {
  const MaakBottomHills({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: 140,
        width: double.infinity,
        child: CustomPaint(painter: _HillsPainter()),
      ),
    );
  }
}

class _HillsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final back = Paint()..color = const Color(0xFFD9E4EC);
    final front = Paint()..color = const Color(0xFFC3D6E3);

    final backPath = Path()
      ..moveTo(0, size.height * 0.5)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.2,
        size.width * 0.6,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.65,
        size.width,
        size.height * 0.4,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final frontPath = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.5,
        size.width * 0.7,
        size.height * 0.8,
      )
      ..quadraticBezierTo(
        size.width * 0.9,
        size.height * 0.95,
        size.width,
        size.height * 0.7,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(backPath, back);
    canvas.drawPath(frontPath, front);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
