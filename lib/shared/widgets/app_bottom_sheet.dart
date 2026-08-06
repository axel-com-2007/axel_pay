// ============================================================
// AppBottomSheet — bottom sheet standard de l'application
// ============================================================
// Point d'entrée unique pour afficher un bottom sheet (sélection
// d'options, détail rapide, confirmation...) avec une apparence
// cohérente : poignée, coins arrondis, padding.
// ============================================================

import 'package:flutter/material.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/typography/app_typography.dart';
import '../../design_system/spacing/app_spacing.dart';

class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (context) => _AppBottomSheetContent(title: title, child: child),
    );
  }
}

class _AppBottomSheetContent extends StatelessWidget {
  final String? title;
  final Widget child;

  const _AppBottomSheetContent({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppRadius.sheet),
        topRight: Radius.circular(AppRadius.sheet),
      ),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.sheet),
          topRight: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.greyMedium,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (title != null) ...[
            Text(title!, style: AppTextStyles.h2),
            const SizedBox(height: AppSpacing.lg),
          ],
          child,
        ],
      ),
    );
  }
}