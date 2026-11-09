import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'requests_repository.dart';

final leaveBalancesProvider =
    FutureProvider.autoDispose<List<LeaveBalance>>((ref) async {
  return ref.watch(requestsRepositoryProvider).fetchBalances();
});

final leaveRequestsProvider =
    FutureProvider.autoDispose<List<LeaveRequestItem>>((ref) async {
  return ref.watch(requestsRepositoryProvider).fetchRequests();
});

void invalidateRequests(dynamic ref) {
  // ignore: avoid_dynamic_calls
  ref.invalidate(leaveBalancesProvider);
  // ignore: avoid_dynamic_calls
  ref.invalidate(leaveRequestsProvider);
}
