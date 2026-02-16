import 'dart:math';

import 'package:flutter/material.dart';

// ============================================================================
// GradientCard — A styled container with gradient background and shadow
// ============================================================================

class GradientCard extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  const GradientCard({
    super.key,
    required this.child,
    this.colors = const [Color(0xFF1A237E), Color(0xFF283593)],
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: colors.first.withAlpha(80),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ============================================================================
// PulsingDot — Animated opacity oscillation indicator
// ============================================================================

class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;

  const PulsingDot({
    super.key,
    this.color = Colors.green,
    this.size = 12,
    this.active = true,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withAlpha((_animation.value * 255).toInt()),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color:
                          widget.color.withAlpha((_animation.value * 100).toInt()),
                      blurRadius: widget.size,
                      spreadRadius: widget.size * 0.3,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

// ============================================================================
// AnimatedCounter — Flip-style numeric counter display
// ============================================================================

class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String? suffix;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final text = suffix != null ? '$value$suffix' : '$value';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.5),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Text(
        text,
        key: ValueKey<int>(value),
        style: style ??
            const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
      ),
    );
  }
}

// ============================================================================
// GaugePainter — Radial arc gauge with animated needle
// ============================================================================

class GaugePainter extends CustomPainter {
  final double value; // 0.0 - 1.0
  final Color startColor;
  final Color endColor;
  final String label;
  final String unit;
  final double displayValue;

  GaugePainter({
    required this.value,
    this.startColor = Colors.green,
    this.endColor = Colors.red,
    this.label = '',
    this.unit = '',
    this.displayValue = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.6);
    final radius = min(size.width, size.height) * 0.42;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey.withAlpha(40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18
      ..strokeCap = StrokeCap.round;

    const startAngle = 0.75 * pi;
    const sweepAngle = 1.5 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Gradient value arc
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [startColor, endColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * value.clamp(0, 1),
      false,
      gradientPaint,
    );

    // Needle
    final needleAngle = startAngle + sweepAngle * value.clamp(0, 1);
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final needleEnd = Offset(
      center.dx + (radius * 0.7) * cos(needleAngle),
      center.dy + (radius * 0.7) * sin(needleAngle),
    );
    canvas.drawLine(center, needleEnd, needlePaint);

    // Center dot
    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.white,
    );

    // Value text
    final valueStr = displayValue.toStringAsFixed(1);
    final valuePainter = TextPainter(
      text: TextSpan(
        text: valueStr,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.35,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valuePainter.paint(
      canvas,
      Offset(center.dx - valuePainter.width / 2, center.dy + radius * 0.15),
    );

    // Unit text
    if (unit.isNotEmpty) {
      final unitPainter = TextPainter(
        text: TextSpan(
          text: unit,
          style: TextStyle(
            color: Colors.white70,
            fontSize: radius * 0.18,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      unitPainter.paint(
        canvas,
        Offset(
          center.dx - unitPainter.width / 2,
          center.dy + radius * 0.15 + valuePainter.height + 2,
        ),
      );
    }

    // Label text
    if (label.isNotEmpty) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white60,
            fontSize: radius * 0.16,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(center.dx - labelPainter.width / 2, size.height * 0.04),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return value != oldDelegate.value ||
        displayValue != oldDelegate.displayValue;
  }
}

// ============================================================================
// SparklinePainter — Mini line chart with area fill
// ============================================================================

class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color fillColor;
  final double minValue;
  final double maxValue;
  final double strokeWidth;

  SparklinePainter({
    required this.data,
    this.lineColor = Colors.cyan,
    Color? fillColor,
    this.minValue = 0,
    double? maxValue,
    this.strokeWidth = 2,
  })  : fillColor = fillColor ?? lineColor.withAlpha(50),
        maxValue = maxValue ?? (data.isEmpty ? 1 : data.reduce(max) * 1.1);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final range = maxValue - minValue;
    if (range <= 0) return;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minValue) / range) * size.height;
      points.add(Offset(x, y.clamp(0, size.height)));
    }

    // Build smooth path
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final controlX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(controlX, prev.dy, controlX, curr.dy, curr.dx, curr.dy);
    }

    // Fill area
    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillColor, fillColor.withAlpha(0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Draw line
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Last point dot
    if (points.isNotEmpty) {
      canvas.drawCircle(
        points.last,
        strokeWidth * 2,
        Paint()..color = lineColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) {
    return data != oldDelegate.data ||
        lineColor != oldDelegate.lineColor ||
        maxValue != oldDelegate.maxValue;
  }
}

// ============================================================================
// BarChartPainter — Animated horizontal bar chart
// ============================================================================

class BarChartPainter extends CustomPainter {
  final List<BarChartItem> items;
  final double animationValue; // 0.0 - 1.0

  BarChartPainter({
    required this.items,
    this.animationValue = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;

    final maxValue =
        items.map((i) => i.value).reduce(max).clamp(1.0, double.infinity);
    final barHeight = (size.height / items.length) * 0.7;
    final gap = (size.height / items.length) * 0.3;
    final labelWidth = size.width * 0.28;
    final chartWidth = size.width - labelWidth - 60;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final y = i * (barHeight + gap) + gap / 2;

      // Label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: labelWidth - 4);
      labelPainter.paint(canvas, Offset(0, y + (barHeight - labelPainter.height) / 2));

      // Bar background
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelWidth, y, chartWidth, barHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        barRect,
        Paint()..color = Colors.white.withAlpha(15),
      );

      // Bar fill
      final fillWidth =
          (item.value / maxValue) * chartWidth * animationValue;
      if (fillWidth > 0) {
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(labelWidth, y, fillWidth, barHeight),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          fillRect,
          Paint()
            ..shader = LinearGradient(
              colors: [item.color, item.color.withAlpha(180)],
            ).createShader(
                Rect.fromLTWH(labelWidth, y, fillWidth, barHeight)),
        );
      }

      // Value text
      final valPainter = TextPainter(
        text: TextSpan(
          text: item.valueLabel ?? item.value.toStringAsFixed(0),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valPainter.paint(
        canvas,
        Offset(labelWidth + fillWidth + 6, y + (barHeight - valPainter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) {
    return animationValue != oldDelegate.animationValue ||
        items != oldDelegate.items;
  }
}

class BarChartItem {
  final String label;
  final double value;
  final Color color;
  final String? valueLabel;

  const BarChartItem({
    required this.label,
    required this.value,
    required this.color,
    this.valueLabel,
  });
}

// ============================================================================
// ProgressRingPainter — Circular progress with gradient stroke
// ============================================================================

class ProgressRingPainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  final Color startColor;
  final Color endColor;
  final double strokeWidth;
  final String? centerText;

  ProgressRingPainter({
    required this.progress,
    this.startColor = Colors.blue,
    this.endColor = Colors.cyan,
    this.strokeWidth = 8,
    this.centerText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - strokeWidth;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withAlpha(20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progress arc
    const startAngle = -pi / 2;
    final sweepAngle = 2 * pi * progress.clamp(0, 1);

    if (sweepAngle > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: startAngle,
            endAngle: startAngle + sweepAngle,
            colors: [startColor, endColor],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Center text
    final text = centerText ?? '${(progress * 100).toInt()}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.4,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        centerText != oldDelegate.centerText;
  }
}

// ============================================================================
// HistogramPainter — Vertical bar histogram
// ============================================================================

class HistogramPainter extends CustomPainter {
  final List<double> buckets;
  final List<Color> bucketColors;
  final double animationValue;
  final double? meanValue; // bucket index (float) of the mean
  final List<String>? bucketLabels;

  HistogramPainter({
    required this.buckets,
    required this.bucketColors,
    this.animationValue = 1.0,
    this.meanValue,
    this.bucketLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    final maxBucket = buckets.reduce(max).clamp(1.0, double.infinity);
    final bottomMargin = 20.0;
    final chartHeight = size.height - bottomMargin;
    final barWidth = size.width / buckets.length * 0.75;
    final gap = size.width / buckets.length * 0.25;

    for (int i = 0; i < buckets.length; i++) {
      final x = i * (barWidth + gap) + gap / 2;
      final barHeight = (buckets[i] / maxBucket) * chartHeight * animationValue;
      final y = chartHeight - barHeight;
      final color =
          i < bucketColors.length ? bucketColors[i] : Colors.grey;

      // Bar with rounded top
      final barRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(barRect, Paint()..color = color);

      // Bucket label
      if (bucketLabels != null && i < bucketLabels!.length) {
        final lp = TextPainter(
          text: TextSpan(
            text: bucketLabels![i],
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        lp.paint(canvas,
            Offset(x + barWidth / 2 - lp.width / 2, chartHeight + 4));
      }
    }

    // Mean line
    if (meanValue != null) {
      final meanX = meanValue! * (barWidth + gap) + gap / 2 + barWidth / 2;
      final dashedPaint = Paint()
        ..color = Colors.yellow
        ..strokeWidth = 1.5;
      for (double y = 0; y < chartHeight; y += 6) {
        canvas.drawLine(
          Offset(meanX, y),
          Offset(meanX, min(y + 3, chartHeight)),
          dashedPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant HistogramPainter oldDelegate) {
    return animationValue != oldDelegate.animationValue ||
        buckets != oldDelegate.buckets;
  }
}

// ============================================================================
// JoystickPainter — Virtual joystick control with gradient ring
// ============================================================================

class JoystickPainter extends CustomPainter {
  final Offset thumbPosition; // -1.0 to 1.0 for x and y
  final bool isActive;

  JoystickPainter({
    this.thumbPosition = Offset.zero,
    this.isActive = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;

    // Outer ring gradient
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..shader = SweepGradient(
        colors: [
          const Color(0xFF455A64),
          const Color(0xFF546E7A),
          const Color(0xFF607D8B),
          const Color(0xFF546E7A),
          const Color(0xFF455A64),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, outerPaint);

    // Background fill
    canvas.drawCircle(
      center,
      radius - 3,
      Paint()..color = const Color(0xFF1B2631),
    );

    // Crosshairs
    final crossPaint = Paint()
      ..color = Colors.white.withAlpha(25)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - radius * 0.7, center.dy),
      Offset(center.dx + radius * 0.7, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.7),
      Offset(center.dx, center.dy + radius * 0.7),
      crossPaint,
    );

    // Inner zone circle
    canvas.drawCircle(
      center,
      radius * 0.3,
      Paint()
        ..color = Colors.white.withAlpha(10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Thumb
    final thumbX = center.dx + thumbPosition.dx * radius * 0.75;
    final thumbY = center.dy + thumbPosition.dy * radius * 0.75;
    final thumbCenter = Offset(thumbX, thumbY);

    // Thumb glow
    if (isActive) {
      canvas.drawCircle(
        thumbCenter,
        radius * 0.22,
        Paint()
          ..color = Colors.blue.withAlpha(40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    // Thumb circle
    canvas.drawCircle(
      thumbCenter,
      radius * 0.16,
      Paint()
        ..shader = RadialGradient(
          colors: [
            isActive ? Colors.blue[300]! : Colors.blueGrey[300]!,
            isActive ? Colors.blue[700]! : Colors.blueGrey[600]!,
          ],
        ).createShader(
            Rect.fromCircle(center: thumbCenter, radius: radius * 0.16)),
    );

    // Thumb highlight
    canvas.drawCircle(
      Offset(thumbCenter.dx - 2, thumbCenter.dy - 2),
      radius * 0.06,
      Paint()..color = Colors.white.withAlpha(80),
    );
  }

  @override
  bool shouldRepaint(covariant JoystickPainter oldDelegate) {
    return thumbPosition != oldDelegate.thumbPosition ||
        isActive != oldDelegate.isActive;
  }
}

// ============================================================================
// HeatmapCellPainter — A colored cell for zone heatmaps
// ============================================================================

class HeatmapCellPainter extends CustomPainter {
  final double value; // 0.0 - 1.0 (0=green, 0.5=yellow, 1.0=red)
  final String label;
  final String? sublabel;
  final bool isSelected;

  HeatmapCellPainter({
    required this.value,
    required this.label,
    this.sublabel,
    this.isSelected = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final v = value.clamp(0.0, 1.0);

    // Interpolate green -> yellow -> red
    Color cellColor;
    if (v < 0.5) {
      cellColor = Color.lerp(
        const Color(0xFF4CAF50),
        const Color(0xFFFFC107),
        v * 2,
      )!;
    } else {
      cellColor = Color.lerp(
        const Color(0xFFFFC107),
        const Color(0xFFF44336),
        (v - 0.5) * 2,
      )!;
    }

    // Cell background
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = cellColor.withAlpha(180));

    // Selection border
    if (isSelected) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Label
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: min(size.width, size.height) * 0.16,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width - 8);
    labelPainter.paint(
      canvas,
      Offset(
        (size.width - labelPainter.width) / 2,
        (size.height - labelPainter.height) / 2 - 6,
      ),
    );

    // Sublabel
    if (sublabel != null) {
      final subPainter = TextPainter(
        text: TextSpan(
          text: sublabel,
          style: TextStyle(
            color: Colors.white70,
            fontSize: min(size.width, size.height) * 0.11,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.width - 8);
      subPainter.paint(
        canvas,
        Offset(
          (size.width - subPainter.width) / 2,
          (size.height + labelPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapCellPainter oldDelegate) {
    return value != oldDelegate.value ||
        label != oldDelegate.label ||
        isSelected != oldDelegate.isSelected;
  }
}
