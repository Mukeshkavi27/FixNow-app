import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FixNowLoader extends StatefulWidget {
  const FixNowLoader({
    super.key,
    this.size = 132,
    this.showLabel = true,
  });

  final double size;
  final bool showLabel;

  @override
  State<FixNowLoader> createState() => _FixNowLoaderState();
}

class _FixNowLoaderState extends State<FixNowLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = widget.size * 0.46;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _FixNowLoaderPainter(progress: _controller.value),
                child: Center(child: child),
              );
            },
            child: Container(
              width: logoSize,
              height: logoSize,
              padding: EdgeInsets.all(widget.size * 0.08),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F0B5EEA),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
                border: Border.all(color: AppTheme.divider),
              ),
              child: const Center(
                child: Text(
                  'F',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.showLabel) ...[
          const SizedBox(height: 16),
          const Text(
            'FixNow',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Getting things ready',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _FixNowLoaderPainter extends CustomPainter {
  const _FixNowLoaderPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ringRect = Rect.fromCircle(
      center: center,
      radius: radius - 7,
    );
    final startAngle = (progress * math.pi * 2) - math.pi / 2;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.primary.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius - 7, basePaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.primary;
    canvas.drawArc(ringRect, startAngle, math.pi * 1.55, false, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _FixNowLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
