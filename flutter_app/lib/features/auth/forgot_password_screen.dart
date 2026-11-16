import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dio_client.dart';
import '../../core/theme.dart';
import '../home/home_typography.dart';
import 'auth_repository.dart';
import 'login_ui.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialIdentifier = ''});

  final String initialIdentifier;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifier;
  bool _submitting = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _identifier = TextEditingController(text: widget.initialIdentifier);
  }

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });
    try {
      final message = await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_identifier.text.trim());
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _success = message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : userFacingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          appBar: AppBar(
            backgroundColor: LoginUi.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: LoginUi.onSurface,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Forgot password',
                    style: HomeType.headline(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: const Color(0xFF24334A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your username or email. We will send a reset link to the address on your account.',
                    style: HomeType.body(
                      fontSize: 13,
                      height: 1.45,
                      color: const Color(0xFF506079),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const LoginFieldLabel('Username or email'),
                            const SizedBox(height: 6),
                            TextFormField(
                              key: const Key('forgot-identifier'),
                              controller: _identifier,
                              enabled: !_submitting && _success == null,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.username],
                              textCapitalization: TextCapitalization.none,
                              autocorrect: false,
                              onFieldSubmitted: (_) => _submit(),
                              style: HomeType.body(
                                fontSize: 14,
                                color: const Color(0xFF24334A),
                              ),
                              decoration: loginFieldDecoration(
                                hint: 'your.username or name@company.com',
                                prefix: HugeIcons.strokeRoundedMail01,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your username or email.';
                                }
                                return null;
                              },
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              LoginErrorBanner(message: _error!),
                            ],
                            if (_success != null) ...[
                              const SizedBox(height: 14),
                              _SuccessBanner(message: _success!),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              key: const Key('forgot-password-send'),
                              onPressed: _submitting || _success != null
                                  ? null
                                  : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.navBlue,
                                disabledBackgroundColor: AppColors.navBlue
                                    .withValues(alpha: 0.55),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _success == null
                                          ? 'Send reset link'
                                          : 'Link sent',
                                      style: HomeType.body(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedCheckmarkCircle02,
            size: 18,
            color: AppColors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: HomeType.body(
                color: const Color(0xFF166534),
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
