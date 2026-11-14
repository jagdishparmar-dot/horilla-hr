import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/api/dio_client.dart';
import '../../core/branding.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme.dart';

class AppLockState {
  const AppLockState({required this.loaded, required this.enabled});

  final bool loaded;
  final bool enabled;
}

final appLockEnabledProvider =
    StateNotifierProvider<AppLockController, AppLockState>((ref) {
      return AppLockController(ref.watch(tokenStorageProvider));
    });

/// Unlocked for this process only. Cold start always starts locked when the
/// setting is on.
final appLockSessionProvider = StateProvider<bool>((ref) => false);

class AppLockController extends StateNotifier<AppLockState> {
  AppLockController(this._storage)
    : super(const AppLockState(loaded: false, enabled: false)) {
    _load();
  }

  final TokenStorage _storage;

  Future<void> _load() async {
    final enabled = await _storage.readAppLock();
    if (!mounted) return;
    state = AppLockState(loaded: true, enabled: enabled);
  }

  Future<bool> setEnabled(bool enabled) async {
    try {
      await _storage.writeAppLock(enabled);
    } catch (_) {
      return false;
    }
    if (!mounted) return false;
    state = AppLockState(loaded: true, enabled: enabled);
    return true;
  }
}

/// Prompts for biometric or device PIN.
///
/// When [passIfUnavailable] is set, a device with no PIN or biometric does
/// not trap the user on the lock screen. Turning the setting on still fails
/// in that case.
Future<bool> promptAppLock({
  required String reason,
  bool passIfUnavailable = false,
}) async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return passIfUnavailable;
    return await auth.authenticate(
      localizedReason: reason,
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  } on LocalAuthException catch (e) {
    if (!passIfUnavailable) return false;
    switch (e.code) {
      case LocalAuthExceptionCode.noCredentialsSet:
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return true;
      default:
        return false;
    }
  } catch (_) {
    return false;
  }
}

/// Shown only after sign-in, and only when the user has turned app lock on.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_prompting) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final lock = ref.read(appLockEnabledProvider);
      if (lock.loaded && lock.enabled) {
        ref.read(appLockSessionProvider.notifier).state = false;
      }
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    setState(() => _prompting = true);
    final ok = await promptAppLock(
      reason: 'Unlock ClockMe',
      passIfUnavailable: true,
    );
    if (!mounted) return;
    if (ok) {
      ref.read(appLockSessionProvider.notifier).state = true;
    }
    setState(() => _prompting = false);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockEnabledProvider);
    final unlocked = ref.watch(appLockSessionProvider);
    if (!lock.loaded) {
      return const Scaffold(
        backgroundColor: Brand.splash,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!lock.enabled || unlocked) return widget.child;
    return _LockScreen(busy: _prompting, onUnlock: _unlock);
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.busy, required this.onUnlock});

  final bool busy;
  final VoidCallback onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUnlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.splash,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const ClockMeLogo(size: 84),
              const SizedBox(height: 18),
              const Text(
                'ClockMe is locked',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use your fingerprint, face, or device PIN.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.busy ? null : widget.onUnlock,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.navBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: widget.busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Unlock',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
