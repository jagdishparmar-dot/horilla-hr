import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme.dart';
import '../more/more_widgets.dart';
import 'colleague_screen.dart';
import 'directory_models.dart';
import 'directory_repository.dart';

const _tint = Color(0xFF22B8E8);

/// Searchable, paged list of colleagues. Reads `GET /employee/directory/`.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<DirectoryEntry> _entries = [];
  List<DirectoryDepartment> _departments = const [];
  int _total = 0;
  int _page = 0;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  String _query = '';
  int? _departmentId;

  /// Bumped on every fresh load so a slow, superseded response is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 240) _loadMore();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final generation = ++_generation;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await ref
          .read(directoryRepositoryProvider)
          .fetchPage(search: _query, departmentId: _departmentId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(page.entries);
        // The department list covers the whole directory, so keep the last
        // non-empty one rather than letting a narrow search blank the chips.
        if (page.departments.isNotEmpty || _departmentId == null) {
          _departments = page.departments;
        }
        _total = page.count;
        _hasNext = page.hasNext;
        _page = 1;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(directoryRepositoryProvider)
          .fetchPage(
            page: _page + 1,
            search: _query,
            departmentId: _departmentId,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries.addAll(page.entries);
        _hasNext = page.hasNext;
        _page += 1;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _loadingMore = false);
      showSnack(context, cleanError(e));
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (value.trim() == _query) return;
      _query = value.trim();
      _load();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    final changed = _query.isNotEmpty;
    _query = '';
    setState(() {});
    if (changed) _load();
  }

  void _selectDepartment(int? id) {
    if (_departmentId == id) return;
    _departmentId = id;
    _load();
  }

  bool get _isForbidden =>
      _error is ApiException && (_error as ApiException).statusCode == 403;

  @override
  Widget build(BuildContext context) {
    return MorePage(
      title: 'Directory',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name, badge, role or department',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
          if (_departments.isNotEmpty && !_isForbidden)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _DepartmentChip(
                    label: 'All',
                    selected: _departmentId == null,
                    onTap: () => _selectDepartment(null),
                  ),
                  for (final d in _departments)
                    _DepartmentChip(
                      label: d.name,
                      selected: _departmentId == d.id,
                      onTap: () => _selectDepartment(d.id),
                    ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null && _entries.isEmpty) {
      if (_isForbidden) {
        return RefreshIndicator(
          onRefresh: () => _load(showSpinner: false),
          child: CenteredScroll(
            child: EmptyPanel(
              icon: HugeIcons.strokeRoundedUserLock01,
              title: 'Directory unavailable',
              message: cleanError(_error!),
              color: _tint,
            ),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: CenteredScroll(
          child: ErrorPanel(
            message: cleanError(_error!),
            onRetry: () => _load(),
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      final filtered = _query.isNotEmpty || _departmentId != null;
      return RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: CenteredScroll(
          child: EmptyPanel(
            icon: filtered
                ? HugeIcons.strokeRoundedSearch01
                : HugeIcons.strokeRoundedUserGroup,
            title: filtered ? 'No matches' : 'No colleagues yet',
            message: filtered
                ? 'Try a different name or clear the filters.'
                : 'People in your company will show up here.',
            color: _tint,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: _entries.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                _total == 1 ? '1 colleague' : '$_total colleagues',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            );
          }
          if (index == _entries.length + 1) {
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final entry = _entries[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ColleagueTile(entry: entry),
          );
        },
      ),
    );
  }
}

class _DepartmentChip extends StatelessWidget {
  const _DepartmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: AppColors.navBlue,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? AppColors.navBlue : Colors.grey.shade300,
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _ColleagueTile extends StatelessWidget {
  const _ColleagueTile({required this.entry});

  final DirectoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final role = entry.roleLine;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: cardDecoration(),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ColleagueScreen(entry: entry),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                EmployeeAvatar(name: entry.name, url: entry.photo, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (role.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (entry.badgeId != null) ...[
                  const SizedBox(width: 8),
                  Pill(text: entry.badgeId!, color: AppColors.navBlue),
                ],
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
