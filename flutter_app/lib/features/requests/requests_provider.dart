import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_provider.dart';
import 'models.dart';
import 'requests_repository.dart';

final leaveBalancesProvider = FutureProvider.autoDispose<List<LeaveBalance>>((
  ref,
) async {
  return ref.watch(requestsRepositoryProvider).fetchBalances();
});

final requestListFilterProvider = StateProvider.autoDispose<RequestListFilter>(
  (ref) => RequestListFilter.all,
);

/// Optional status narrowing on top of the type filter. Null shows every status.
final requestStatusFilterProvider = StateProvider.autoDispose<RequestStatus?>(
  (ref) => null,
);

final leaveRequestsProvider =
    FutureProvider.autoDispose<List<LeaveRequestItem>>((ref) async {
      final home = await ref.watch(mobileHomeProvider.future);
      return ref
          .watch(requestsRepositoryProvider)
          .fetchMine(employeeId: home.employeeId);
    });

void invalidateRequests(dynamic ref) {
  // ignore: avoid_dynamic_calls
  ref.invalidate(leaveBalancesProvider);
  // ignore: avoid_dynamic_calls
  ref.invalidate(leaveRequestsProvider);
}

typedef AllocationEditor = Future<void> Function({
  required int id,
  required int leaveTypeId,
  required num days,
  required String description,
});

final allocationEditorProvider = Provider<AllocationEditor>((ref) {
  final repository = ref.watch(requestsRepositoryProvider);
  return ({
    required int id,
    required int leaveTypeId,
    required num days,
    required String description,
  }) {
    return repository.updateAllocation(
      id: id,
      leaveTypeId: leaveTypeId,
      days: days,
      description: description,
    );
  };
});
