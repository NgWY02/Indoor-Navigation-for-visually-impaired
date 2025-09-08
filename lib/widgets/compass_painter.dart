import 'dart:math';
import 'package:flutter/material.dart';

class CompassPainter extends CustomPainter {
  final double currentHeading;
  final double targetHeading;
  final double threshold;
  final bool isWithinRange;

  CompassPainter({
    required this.currentHeading,
    required this.targetHeading,
    this.threshold = 5.0,
    this.isWithinRange = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Draw outer circle background
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw outer circle border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw compass directions (N, E, S, W)
    _drawCardinalDirections(canvas, center, radius);

    // Draw degree markings
    _drawDegreeMarkings(canvas, center, radius);

    // Draw target sector
    _drawTargetSector(canvas, center, radius);

    // Draw current heading arrow
    _drawCurrentHeading(canvas, center, radius);

    // Draw target direction indicator
    _drawTargetDirection(canvas, center, radius);

    // Draw center dot
    final centerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4.0, centerDotPaint);
  }

  void _drawCardinalDirections(Canvas canvas, Offset center, double radius) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );

    final directions = ['N', 'E', 'S', 'W'];
    final angles = [0.0, 90.0, 180.0, 270.0];

    for (int i = 0; i < directions.length; i++) {
      final angle = angles[i];
      final radian = (angle - 90) * pi / 180;
      final x = center.dx + (radius - 15) * cos(radian);
      final y = center.dy + (radius - 15) * sin(radian);

      final textSpan = TextSpan(text: directions[i], style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final offsetX = x - textPainter.width / 2;
      final offsetY = y - textPainter.height / 2;
      textPainter.paint(canvas, Offset(offsetX, offsetY));
    }
  }

  void _drawDegreeMarkings(Canvas canvas, Offset center, double radius) {
    final markPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.0;

    for (int deg = 0; deg < 360; deg += 10) {
      final radian = (deg - 90) * pi / 180;
      final startRadius = deg % 30 == 0 ? radius - 15 : radius - 8;
      final endRadius = radius - 3;

      final startX = center.dx + startRadius * cos(radian);
      final startY = center.dy + startRadius * sin(radian);
      final endX = center.dx + endRadius * cos(radian);
      final endY = center.dy + endRadius * sin(radian);

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        markPaint,
      );
    }
  }

  void _drawTargetSector(Canvas canvas, Offset center, double radius) {
    // Draw target sector
    final sectorColor = isWithinRange 
        ? Colors.green.withOpacity(0.3) 
        : Colors.orange.withOpacity(0.3);
    
    final sectorPaint = Paint()
      ..color = sectorColor
      ..style = PaintingStyle.fill;

    final targetRadian = (targetHeading - 90) * pi / 180;
    final startAngle = targetRadian - (threshold * pi / 180);
    final sweepAngle = threshold * 2 * pi / 180;

    final rect = Rect.fromCircle(center: center, radius: radius - 3);
    canvas.drawArc(rect, startAngle, sweepAngle, true, sectorPaint);

    // Draw sector border
    final sectorBorderPaint = Paint()
      ..color = isWithinRange ? Colors.green : Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawArc(rect, startAngle, sweepAngle, false, sectorBorderPaint);
  }

  void _drawCurrentHeading(Canvas canvas, Offset center, double radius) {
    // Draw current heading arrow (phone direction)
    final headingRadian = (currentHeading - 90) * pi / 180;
    
    // Arrow shaft
    final shaftPaint = Paint()
      ..color = isWithinRange ? Colors.green : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final arrowLength = radius * 0.7;
    final arrowEndX = center.dx + arrowLength * cos(headingRadian);
    final arrowEndY = center.dy + arrowLength * sin(headingRadian);

    canvas.drawLine(
      center,
      Offset(arrowEndX, arrowEndY),
      shaftPaint,
    );

    // Arrow head
    final arrowHeadPaint = Paint()
      ..color = isWithinRange ? Colors.green : Colors.white
      ..style = PaintingStyle.fill;

    final arrowPath = Path();
    const arrowSize = 12.0;
    
    final baseAngle1 = headingRadian + 2.8; // ~160 degrees
    final baseAngle2 = headingRadian - 2.8; // ~-160 degrees
    
    final base1X = arrowEndX + arrowSize * cos(baseAngle1);
    final base1Y = arrowEndY + arrowSize * sin(baseAngle1);
    final base2X = arrowEndX + arrowSize * cos(baseAngle2);
    final base2Y = arrowEndY + arrowSize * sin(baseAngle2);

    arrowPath.moveTo(arrowEndX, arrowEndY);
    arrowPath.lineTo(base1X, base1Y);
    arrowPath.lineTo(base2X, base2Y);
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowHeadPaint);
  }

  void _drawTargetDirection(Canvas canvas, Offset center, double radius) {
    // Draw target direction indicator
    final targetRadian = (targetHeading - 90) * pi / 180;
    final targetRadius = radius - 25;
    
    final targetX = center.dx + targetRadius * cos(targetRadian);
    final targetY = center.dy + targetRadius * sin(targetRadian);

    // Target indicator circle
    final targetPaint = Paint()
      ..color = isWithinRange ? Colors.green : Colors.blue
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(targetX, targetY), 8.0, targetPaint);

    // Target indicator border
    final targetBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(Offset(targetX, targetY), 8.0, targetBorderPaint);

    // Draw "TARGET" text
    final targetTextStyle = TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    final textSpan = TextSpan(text: 'TARGET', style: targetTextStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textX = targetX - textPainter.width / 2;
    final textY = targetY + 15;
    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) {
    return oldDelegate.currentHeading != currentHeading ||
        oldDelegate.targetHeading != targetHeading ||
        oldDelegate.isWithinRange != isWithinRange;
  }
}

class CompassWidget extends StatelessWidget {
  final double currentHeading;
  final double targetHeading;
  final double threshold;
  final bool isWithinRange;
  final double size;

  const CompassWidget({
    Key? key,
    required this.currentHeading,
    required this.targetHeading,
    this.threshold = 5.0,
    this.isWithinRange = false,
    this.size = 200.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      child: CustomPaint(
        painter: CompassPainter(
          currentHeading: currentHeading,
          targetHeading: targetHeading,
          threshold: threshold,
          isWithinRange: isWithinRange,
        ),
      ),
    );
  }
}
