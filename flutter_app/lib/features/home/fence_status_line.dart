import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

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
      loading: () => _caption(
        'Checking your location…',
        AppColors.textSecondary,
      ),
      error: (error, _) {
        final text = error.toString();
        return _caption(
          text.startsWith('Exception: ') ? text.substring(11) : text,
          AppColors.red,
        );
      },
      data: (fix) {
        if (fix == null) return const SizedBox.shrink();
        return _caption(
          fix.label,
          fix.inside ? AppColors.green : AppColors.red,
        );
      },
    );
  }

  Widget _caption(String text, Color color) {
    final inside = color == AppColors.green;
    return Align(
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: inside
              ? const Color(0xFFE8F5E9)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedLocation01,
              color: color,
              size: 13,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                text,
                textAlign: align,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
