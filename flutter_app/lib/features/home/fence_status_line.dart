import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'home_provider.dart';

/// Distance from the site returned by `GET /mobile/home/` `geofence`.
class FenceStatusLine extends ConsumerWidget {
  const FenceStatusLine({super.key, this.align = TextAlign.center});

  final TextAlign align;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fence = ref.watch(punchFenceProvider);
    return fence.when(
      loading: () => Text(
        'Checking your location…',
        textAlign: align,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      error: (error, _) {
        final text = error.toString();
        return Text(
          text.startsWith('Exception: ') ? text.substring(11) : text,
          textAlign: align,
          style: const TextStyle(
            color: AppColors.red,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
      },
      data: (fix) {
        if (fix == null) return const SizedBox.shrink();
        return Text(
          fix.label,
          textAlign: align,
          style: TextStyle(
            color: fix.inside ? AppColors.green : AppColors.red,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}
