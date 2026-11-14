import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fired when stored tokens are wiped because refresh was rejected.
///
/// [AuthNotifier] listens so the shell cannot stay signed in with an empty store.
class SessionRevocation {
  final _controller = StreamController<void>.broadcast(sync: true);

  Stream<void> get stream => _controller.stream;

  void notify() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  void dispose() {
    _controller.close();
  }
}

final sessionRevocationProvider = Provider<SessionRevocation>((ref) {
  final revocation = SessionRevocation();
  ref.onDispose(revocation.dispose);
  return revocation;
});
