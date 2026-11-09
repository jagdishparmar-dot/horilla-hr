import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/dio_client.dart';
import '../../core/theme.dart';
import 'more_models.dart';

const heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2F6BFF), Color(0xFF6D5CFF), Color(0xFF9B5CFF)],
);

/// Widest a content column gets on tablets / landscape; phones are unaffected.
const double kMaxContentWidth = 640;

/// Standard page chrome for the secondary screens opened from More.
class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.navBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: actions,
        bottom: bottom,
      ),
      floatingActionButton: floatingActionButton,
      body: ConstrainedContent(child: body),
    );
  }
}

/// Centers [child] and caps its width so layouts hold up on large screens.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: child,
      ),
    );
  }
}

/// Loading / error / data switch shared by every API-backed screen.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => CenteredScroll(
        child: ErrorPanel(message: cleanError(e), onRetry: onRetry),
      ),
      data: builder,
    );
  }
}

String cleanError(Object e) {
  final text = e.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

/// Centers a short panel while keeping pull-to-refresh working.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: box.maxHeight.isFinite ? box.maxHeight : 400,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red.withValues(alpha: 0.10),
            ),
            child: Center(
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedWifiDisconnected01,
                color: AppColors.red,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            "Couldn't load this",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color = AppColors.navBlue,
    this.action,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.16),
                  const Color(0xFF9B5CFF).withValues(alpha: 0.14),
                ],
              ),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: color, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

BoxDecoration cardDecoration({double radius = 18}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 14,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

/// Label / value line with a tinted icon. Hidden when [value] is empty.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.navBlue,
    this.last = false,
  });

  final List<List<dynamic>> icon;
  final String label;
  final String? value;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = value;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: color, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class GradientIconTile extends StatelessWidget {
  const GradientIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final List<List<dynamic>> icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.3)!, color],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Center(
        child: HugeIcon(icon: icon, color: Colors.white, size: size * 0.48),
      ),
    );
  }
}

/// `Authorization` header for `/media/...` files, which the server only serves
/// to signed-in callers. Without it every photo redirects to the login page.
final mediaHeadersProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  final token = await ref.watch(tokenStorageProvider).readAccess();
  if (token == null || token.isEmpty) return const {};
  return {'Authorization': 'Bearer $token'};
});

class EmployeeAvatar extends ConsumerWidget {
  const EmployeeAvatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 30,
  });

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = resolveMediaUrl(url);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Center(
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.purple,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.72,
        ),
      ),
    );
    final headers = ref.watch(mediaHeadersProvider).asData?.value;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        color: AppColors.purpleSoft,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: resolved == null || headers == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: resolved,
              httpHeaders: headers,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Hands [uri] (tel:, mailto:, geo:, https:) to the system. A device with no
/// handler, or any launch failure, becomes a snackbar instead of a crash.
Future<void> openExternal(
  BuildContext context,
  Uri uri, {
  String failMessage = "Couldn't open this on your device.",
}) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) showSnack(context, failMessage);
}
