import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/github_store/models.dart';
import '../../data/services/github_store/url_parser.dart';
import '../../data/services/github_store/github_store_service.dart';
import '../providers.dart';
import '../../data/storage/prefs_storage.dart';

@immutable
class StoreState {
  final bool showAll;
  final RepoRef? repo;
  final String currentPath; // relative to repo.root
  final AsyncValue<List<RepoItem>> listing;
  final String searchQuery;
  final List<RepoRef> sources;
  final bool showMedia;
  final bool onlyImportable;
  final bool hideUnsupported;
  const StoreState({
    required this.repo,
    required this.currentPath,
    required this.listing,
    required this.searchQuery,
    required this.sources,
    this.showMedia = false,
    this.onlyImportable = false,
    this.hideUnsupported = false,
    this.showAll = false,
  });

  StoreState copyWith({
    RepoRef? repo,
    String? currentPath,
    AsyncValue<List<RepoItem>>? listing,
    String? searchQuery,
    List<RepoRef>? sources,
    bool? showMedia,
    bool? onlyImportable,
    bool? hideUnsupported,
    bool? showAll,
  }) => StoreState(
    repo: repo ?? this.repo,
    currentPath: currentPath ?? this.currentPath,
    listing: listing ?? this.listing,
    searchQuery: searchQuery ?? this.searchQuery,
    sources: sources ?? this.sources,
    showMedia: showMedia ?? this.showMedia,
    onlyImportable: onlyImportable ?? this.onlyImportable,
    hideUnsupported: hideUnsupported ?? this.hideUnsupported,
    showAll: showAll ?? this.showAll,
  );

  static const initial = StoreState(
    repo: null,
    currentPath: '',
    listing: AsyncData(<RepoItem>[]),
    searchQuery: '',
    sources: <RepoRef>[],
    showMedia: false,
    onlyImportable: false,
    hideUnsupported: false,
    showAll: false,
  );
}

final payloadsStoreControllerProvider = NotifierProvider<PayloadsStoreController, StoreState>(
  PayloadsStoreController.new,
);

class PayloadsStoreController extends Notifier<StoreState> {
  bool _showAll = false;
  static const _prefsKey = 'tapducky.store.lastRepo';
  static const _sourcesKey = 'tapducky.store.sources';
  GitHubStoreService get _svc => ref.read(githubStoreServiceProvider);
  static const _showAllKey = 'tapducky.store.showAll';
  static const _showMediaKey = 'tapducky.store.showMedia';
  static const _onlyImportableKey = 'tapducky.store.onlyImportable';
  static const _hideUnsupportedKey = 'tapducky.store.hideUnsupported';

  @override
  StoreState build() => StoreState.initial;

  void setSearch(String q) => state = state.copyWith(searchQuery: q);

  Future<void> setUrl(String url) async {
    final parsed = parseGitHubUrl(url);
    if (parsed == null) {
      state = state.copyWith(
        repo: null,
        listing: const AsyncError('Only GitHub links are supported', StackTrace.empty),
      );
      return;
    }
    state = state.copyWith(repo: parsed, currentPath: parsed.path, listing: const AsyncLoading());
    await _saveLast(parsed);
    await _load();
  }

  Future<void> navigateInto(RepoItem item) async {
    if (state.repo == null) return;
    if (item.type == RepoItemType.dir) {
      state = state.copyWith(currentPath: item.path, listing: const AsyncLoading());
      await _load();
    }
  }

  Future<void> navigateUp() async {
    if (state.repo == null) return;
    final p = state.currentPath;
    if (p.isEmpty) return;
    final parts = p.split('/');
    if (parts.isEmpty) return;
    final up = parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/');
    state = state.copyWith(currentPath: up, listing: const AsyncLoading());
    await _load();
  }

  Future<void> refresh() async {
    if (state.repo == null) return;
    state = state.copyWith(listing: const AsyncLoading());
    await _load();
  }

  // --- View toggles ---
  Future<void> toggleShowMedia() async {
    final newVal = !state.showMedia;
    state = state.copyWith(showMedia: newVal);
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setString(_showMediaKey, newVal ? '1' : '0');
    } catch (_) {}
    await refresh();
  }

  Future<void> toggleOnlyImportable() async {
    final newVal = !state.onlyImportable;
    state = state.copyWith(onlyImportable: newVal);
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setString(_onlyImportableKey, newVal ? '1' : '0');
    } catch (_) {}
    await refresh();
  }

  Future<void> toggleHideUnsupported() async {
    final newVal = !state.hideUnsupported;
    state = state.copyWith(hideUnsupported: newVal);
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setString(_hideUnsupportedKey, newVal ? '1' : '0');
    } catch (_) {}
    await refresh();
  }

  Future<void> _load() async {
    try {
      final refRepo = state.repo!;
      final items = await _svc.listDirectory(
        refRepo,
        subPath: state.currentPath.replaceFirst(refRepo.path, ''),
        showMedia: state.showMedia,
        showAll: _showAll,
      );
      state = state.copyWith(listing: AsyncData(items));
    } catch (e, st) {
      state = StoreState(
        repo: state.repo,
        currentPath: state.currentPath,
        listing: AsyncError(e, st),
        searchQuery: state.searchQuery,
        sources: state.sources,
        showMedia: state.showMedia,
        onlyImportable: state.onlyImportable,
        hideUnsupported: state.hideUnsupported,
      );
    }
  }

  Future<void> loadLastFromPrefs() async {
    // Load view preferences early
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      final sm = prefs.getString(_showMediaKey);
      final oi = prefs.getString(_onlyImportableKey);
      final hu = prefs.getString(_hideUnsupportedKey);
      state = state.copyWith(
        showMedia: sm == '1',
        onlyImportable: oi == '1',
        hideUnsupported: hu == '1',
      );
      final sa = prefs.getString(_showAllKey);
      _showAll = sa == '1';
    } catch (_) {}

    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      final json = prefs.getJsonMap(_prefsKey);
      if (json == null) return;
      final owner = (json['owner'] ?? '').toString();
      final repo = (json['repo'] ?? '').toString();
      if (owner.isEmpty || repo.isEmpty) return;
      final branch = (json['branch'] ?? 'main').toString();
      final path = (json['path'] ?? '').toString();
      final originalUrl = (json['originalUrl'] ?? 'https://github.com/$owner/$repo').toString();
      final refRepo = RepoRef(owner: owner, repo: repo, branch: branch, path: path, originalUrl: originalUrl);
      // Load sources as well
      final sources = await _loadSources();
      state = state.copyWith(repo: refRepo, currentPath: refRepo.path, sources: sources);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _saveLast(RepoRef refRepo) async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setJsonMap(_prefsKey, refRepo.toJson());
    } catch (_) {}
  }

  Future<void> clearLastFromPrefs() async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  Future<List<RepoRef>> _loadSources() async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      final list = prefs.getJsonList(_sourcesKey);
      return list
          .map((e) => RepoRef(
                owner: (e['owner'] ?? '').toString(),
                repo: (e['repo'] ?? '').toString(),
                branch: (e['branch'] ?? 'main').toString(),
                path: (e['path'] ?? '').toString(),
                originalUrl: (e['originalUrl'] ?? '').toString(),
                alias: (e['alias'])?.toString(),
              ))
          .where((r) => r.owner.isNotEmpty && r.repo.isNotEmpty)
          .toList();
    } catch (_) {
      return const <RepoRef>[];
    }
  }

  Future<void> addSource(RepoRef refRepo) async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      final current = await _loadSources();
      final exists = current.any((r) =>
          r.owner == refRepo.owner && r.repo == refRepo.repo && r.branch == refRepo.branch && r.path == refRepo.path);
      if (!exists) {
        final defaultAlias = refRepo.alias ?? '${refRepo.owner}/${refRepo.repo}';
        final updated = [...current, refRepo.copyWith(alias: defaultAlias)];
        await prefs.setJsonList(_sourcesKey, updated.map((e) => e.toJson()).toList());
        state = state.copyWith(sources: updated);
      }
    } catch (_) {}
  }

  Future<void> removeSource(RepoRef refRepo) async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      final current = await _loadSources();
      final updated = current
          .where((r) => !(r.owner == refRepo.owner && r.repo == refRepo.repo && r.branch == refRepo.branch && r.path == refRepo.path))
          .toList();
      await prefs.setJsonList(_sourcesKey, updated.map((e) => e.toJson()).toList());
      state = state.copyWith(sources: updated);
    } catch (_) {}
  }

  Future<void> updateSourceAlias(RepoRef refRepo, String alias) async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      final current = await _loadSources();
      final updated = current.map((r) {
        if (r.owner == refRepo.owner && r.repo == refRepo.repo && r.branch == refRepo.branch && r.path == refRepo.path) {
          return r.copyWith(alias: alias);
        }
        return r;
      }).toList();
      await prefs.setJsonList(_sourcesKey, updated.map((e) => e.toJson()).toList());
      state = state.copyWith(sources: updated);
    } catch (_) {}
  }

  Future<void> setSources(List<RepoRef> newList) async {
    try {
      final prefs = await ref.read(prefsStorageProvider.future);
      await prefs.setJsonList(_sourcesKey, newList.map((e) => e.toJson()).toList());
      state = state.copyWith(sources: newList);
    } catch (_) {}
  }
}
