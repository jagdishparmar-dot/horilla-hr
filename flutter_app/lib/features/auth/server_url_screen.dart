import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/branding.dart';
import '../../core/config.dart';
import '../../core/server_url_provider.dart';
import '../../core/theme.dart';
import '../home/home_typography.dart';
import '../more/more_widgets.dart';

class ServerUrlScreen extends ConsumerStatefulWidget {
  const ServerUrlScreen({super.key, this.editing = false});

  final bool editing;

  @override
  ConsumerState<ServerUrlScreen> createState() => _ServerUrlScreenState();
}

class _ServerUrlScreenState extends ConsumerState<ServerUrlScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(
      text: ServerUrl.display(ref.read(serverUrlProvider).apiBaseUrl),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final ok = await ref.read(serverUrlProvider.notifier).save(_url.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (widget.editing) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverUrlProvider);
    if (widget.editing) {
      return MorePage(
        title: 'Server address',
        backLabel: 'More',
        body: _form(server, onBlue: false),
      );
    }

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
            const _Backdrop(),
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
                            'Connect to your ClockMe server to continue.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 36),
                          _form(server, onBlue: true),
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

  Widget _form(ServerUrlState server, {required bool onBlue}) {
    final card = Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.editing ? 'Server address' : 'Your server',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter the ClockMe address your company uses. We will save it on this device.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 22),
              TextFormField(
                key: const Key('server-url-field'),
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://hr.yourcompany.com',
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(12),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedLink01,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your server address.';
                  }
                  try {
                    ServerUrl.normalize(value);
                  } on FormatException catch (e) {
                    return e.message;
                  }
                  return null;
                },
              ),
              if (server.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  server.error!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              if (server.storageError && !widget.editing) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => ref.read(serverUrlProvider.notifier).reload(),
                  child: const Text('Try again'),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                key: const Key('server-url-save'),
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.editing ? 'Save' : 'Continue',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onBlue) return card;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        card,
        const SizedBox(height: 16),
        Text(
          'Changing the server signs you out of this device.',
          style: HomeType.body(fontSize: 13, color: moreMuted),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(decoration: BoxDecoration(gradient: Brand.hero));
  }
}
