import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/branding.dart';
import '../../core/theme.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final ok = await ref
        .read(authProvider.notifier)
        .login(_username.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) return;
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authProvider).error;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Brand.splash,
        body: Stack(
          children: [
            const _LoginBackdrop(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 12,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 28),
                          const ClockMeLogo(size: 92),
                          const SizedBox(height: 20),
                          const Text(
                            'ClockMe',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check in. Check out. Stay on time.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 36),
                          _LoginCard(
                            formKey: _formKey,
                            username: _username,
                            password: _password,
                            obscure: _obscure,
                            submitting: _submitting,
                            error: error,
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                            onSubmit: _submit,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Use your Horilla HR account',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: Brand.hero),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(size: 220, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            top: 120,
            left: -70,
            child: _Blob(size: 180, color: Colors.white.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: 80,
            right: -40,
            child: _Blob(size: 160, color: const Color(0xFF9B5CFF).withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.username,
    required this.password,
    required this.obscure,
    required this.submitting,
    required this.error,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController username;
  final TextEditingController password;
  final bool obscure;
  final bool submitting;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome back. Enter your credentials to continue.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                TextFormField(
                  controller: username,
                  enabled: !submitting,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'your.username',
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(12),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedUser,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: password,
                  enabled: !submitting,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedSquareLockPassword,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                    suffixIcon: IconButton(
                      onPressed: onToggleObscure,
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBanner(message: _friendlyError(error!)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: submitting ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navBlue,
                    disabledBackgroundColor: AppColors.navBlue.withValues(
                      alpha: 0.55,
                    ),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign in',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedAlert02,
            size: 18,
            color: AppColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _friendlyError(String raw) {
  var text = raw.trim();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) text = text.substring(prefix.length);
  if (text.startsWith('DioException')) {
    return 'Cannot reach the ClockMe server. Check your connection and try again.';
  }
  return text;
}
