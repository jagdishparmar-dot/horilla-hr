import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/api/dio_client.dart';
import '../../core/branding.dart';
import '../../core/config.dart';
import '../../core/server_url_provider.dart';
import '../../core/theme.dart';
import '../home/home_typography.dart';
import 'auth_provider.dart';
import 'forgot_password_screen.dart';
import 'login_ui.dart';
import 'server_url_screen.dart';

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
        .login(
          _username.text.trim(),
          _password.text,
          onAttemptFinished: () {
            if (mounted) _password.clear();
          },
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) return;
  }

  void _openServerUrl() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ServerUrlScreen(editing: true),
      ),
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ForgotPasswordScreen(initialIdentifier: _username.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authProvider).error;
    final serverHost = ServerUrl.display(
      ref.watch(serverUrlProvider).apiBaseUrl,
    );
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Theme(
      data: HomeType.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: LoginUi.canvas,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: LoginUi.canvas,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 8,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        const _BrandMark(),
                        const SizedBox(height: 16),
                        Text(
                          'Sign in to ClockMe',
                          textAlign: TextAlign.center,
                          style: HomeType.headline(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: LoginUi.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check in. Check out. Stay on time.',
                          textAlign: TextAlign.center,
                          style: HomeType.body(
                            fontSize: 12,
                            height: 1.45,
                            color: LoginUi.onVariant,
                          ),
                        ),
                        if (serverHost.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _ServerPill(host: serverHost, onTap: _openServerUrl),
                        ],
                        const SizedBox(height: 24),
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
                          onForgotPassword: _openForgotPassword,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: LoginUi.field,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.navBlue.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const ClockMeLogo(size: 48, elevated: false),
    );
  }
}

class _ServerPill extends StatelessWidget {
  const _ServerPill({required this.host, required this.onTap});

  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LoginUi.field,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: LoginUi.live,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  host.replaceFirst(RegExp(r'^https?://'), ''),
                  overflow: TextOverflow.ellipsis,
                  style: HomeType.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: LoginUi.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const HugeIcon(
                icon: HugeIcons.strokeRoundedArrowReloadHorizontal,
                size: 15,
                color: LoginUi.onVariant,
              ),
            ],
          ),
        ),
      ),
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
    required this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController username;
  final TextEditingController password;
  final bool obscure;
  final bool submitting;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LoginUi.card,
      elevation: 0,
      shadowColor: const Color(0x14000000),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LoginFieldLabel('Username'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: username,
                  enabled: !submitting,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  style: HomeType.body(fontSize: 14, color: LoginUi.onSurface),
                  decoration: loginFieldDecoration(
                    hint: 'your.username',
                    prefix: HugeIcons.strokeRoundedUser,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                const LoginFieldLabel('Password'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: password,
                  enabled: !submitting,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => onSubmit(),
                  style: HomeType.body(
                    fontSize: 14,
                    color: LoginUi.onSurface,
                    letterSpacing: obscure ? 1.4 : 0,
                  ),
                  decoration: loginFieldDecoration(
                    hint: 'Enter your password',
                    prefix: HugeIcons.strokeRoundedSquareLockPassword,
                    suffix: IconButton(
                      onPressed: onToggleObscure,
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      icon: HugeIcon(
                        icon: obscure
                            ? HugeIcons.strokeRoundedView
                            : HugeIcons.strokeRoundedViewOff,
                        size: 20,
                        color: LoginUi.outline,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgot-password'),
                    onPressed: submitting ? null : onForgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.navBlue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot password?',
                      style: HomeType.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navBlue,
                      ),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  LoginErrorBanner(message: userFacingError(error!)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navBlue,
                    disabledBackgroundColor: AppColors.navBlue.withValues(
                      alpha: 0.55,
                    ),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    shadowColor: AppColors.navBlue.withValues(alpha: 0.3),
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
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Sign In',
                              style: HomeType.body(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowRight01,
                              size: 18,
                              color: Colors.white,
                            ),
                          ],
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
