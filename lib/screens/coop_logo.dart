import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Shows assets/images/logo3.png when it exists. Until you add that file it draws
/// a simple CoopIQ mark and wordmark so the header is never empty.
class CoopLogo extends StatelessWidget {
  final double height;
  const CoopLogo({super.key, this.height = 36});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo3.png',
      height: height,
      errorBuilder: (_, __, ___) => _Fallback(height: height),
    );
  }
}

class _Fallback extends StatelessWidget {
  final double height;
  const _Fallback({required this.height});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: height,
        height: height,
        decoration: BoxDecoration(color: CoopColors.forest, borderRadius: BorderRadius.circular(height * 0.3)),
        child: Icon(Icons.egg_alt, color: CoopColors.amber, size: height * 0.62),
      ),
      const SizedBox(width: 8),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Coop', style: TextStyle(color: CoopColors.forest)),
          TextSpan(text: 'IQ', style: TextStyle(color: CoopColors.leaf)),
        ]),
        style: TextStyle(fontSize: height * 0.56, fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
    ]);
  }
}
