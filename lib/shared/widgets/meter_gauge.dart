// ============================================================
// MeterGaugeWidget — jauge circulaire réutilisable (CustomPainter)
// ============================================================
// Composant graphique personnalisé pour représenter visuellement une
// consommation / un niveau / une progression (ex : crédit prépayé
// restant en kWh, niveau de consommation, progression d'un objectif).
//
// Remplace la jauge qui existait en privé dans prepaid_screen.dart afin
// qu'elle soit réutilisable sur n'importe quel écran (compteurs,
// accueil, historique...) sans duplication de code.
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/typography/app_typography.dart';
import '../../design_system/animations/app_animations.dart';

class MeterGaugeWidget extends StatelessWidget {
  final double value;
  final double maxValue;
  final String unitLabel;
  final String? subLabel;

  // AVANT : final String Function(double value)? valueFormatter;
  final String Function(num value)? valueFormatter;   // ✅ corrigé

  final double size;
  final double strokeWidth;
  final double criticalThreshold;
  final Duration animationDuration;
  

  const MeterGaugeWidget({
    super.key,
    required this.value,
    required this.maxValue,
    required this.unitLabel,
    this.subLabel,
    this.valueFormatter,
    this.size = 190,
    this.strokeWidth = 14,
    this.criticalThreshold = 0.2,
    this.animationDuration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            builder: (context, animatedRatio, _) => CustomPaint(
              size: Size(size, size),
              painter: _MeterGaugePainter(
                ratio: animatedRatio,
                strokeWidth: strokeWidth,
                critical: ratio < criticalThreshold,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedCounter(
                value: value,
                formatter: valueFormatter ?? (v) => v.toStringAsFixed(1),
                style: AppTextStyles.amountMedium.copyWith(fontSize: 34),
              ),
              Text(unitLabel, style: AppTextStyles.bodyMuted),
              if (subLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  subLabel!,
                  style: const TextStyle(color: AppColors.primaryBlueDark, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MeterGaugePainter extends CustomPainter {
  final double ratio; // 0.0 -> 1.0
  final double strokeWidth;
  final bool critical;

  _MeterGaugePainter({required this.ratio, required this.strokeWidth, required this.critical});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    final bgPaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = critical ? AppColors.danger : AppColors.primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi * 1.25;
    const sweepAngleMax = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngleMax,
      false,
      bgPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngleMax * ratio,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MeterGaugePainter oldDelegate) =>
      oldDelegate.ratio != ratio || oldDelegate.critical != critical;
}
