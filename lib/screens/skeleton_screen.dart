import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Shimmering placeholder of the Home screen, shown while the signed-in
/// user's data loads. It mirrors the real layout so nothing jumps when the
/// app appears.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Semantics(
          label: 'Loading',
          child: Shimmer(
            child: Column(children: [
              Expanded(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  children: const [
                    // Header: logo, greeting, bell, profile
                    Row(children: [
                      Bone(width: 56, height: 56, radius: 14),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(children: [
                          Bone(width: 90, height: 12),
                          SizedBox(height: 8),
                          Bone(width: 60, height: 20),
                        ]),
                      ),
                      SizedBox(width: 8),
                      Bone(width: 44, height: 44, circle: true),
                      SizedBox(width: 8),
                      Bone(width: 44, height: 44, circle: true),
                    ]),
                    SizedBox(height: 18),
                    // Photo diagnosis card
                    Bone(height: 230, radius: 22),
                    SizedBox(height: 18),
                    // Quick actions
                    Row(children: [
                      Expanded(child: Bone(height: 96, radius: 16)),
                      SizedBox(width: 12),
                      Expanded(child: Bone(height: 96, radius: 16)),
                    ]),
                    SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Bone(height: 96, radius: 16)),
                      SizedBox(width: 12),
                      Expanded(child: Bone(height: 96, radius: 16)),
                    ]),
                    SizedBox(height: 22),
                    // Batch card and tip card
                    Bone(height: 84, radius: 16),
                    SizedBox(height: 14),
                    Bone(height: 130, radius: 16),
                  ],
                ),
              ),
              // Bottom navigation placeholder
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _NavBone(),
                  _NavBone(),
                  _NavBone(),
                  _NavBone(),
                  _NavBone(),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavBone extends StatelessWidget {
  const _NavBone();

  @override
  Widget build(BuildContext context) => const Column(children: [
        Bone(width: 26, height: 26, circle: true),
        SizedBox(height: 8),
        Bone(width: 36, height: 8),
      ]);
}

/// A rounded placeholder block. It is drawn white; [Shimmer] repaints it.
class Bone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;
  const Bone({super.key, this.width, required this.height, this.radius = 8, this.circle = false});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// Sweeps a soft highlight across everything inside it. No extra package needed.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final base = dark ? const Color(0xFF1E2E25) : const Color(0xFFE2E8DE);
    final highlight = dark ? const Color(0xFF2D4236) : const Color(0xFFF6F8F3);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          colors: [base, highlight, base],
          stops: const [0.35, 0.5, 0.65],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          transform: _Slide(_c.value),
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

/// Moves the gradient from fully off the left edge to fully off the right edge.
class _Slide extends GradientTransform {
  final double progress;
  const _Slide(this.progress);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
}
