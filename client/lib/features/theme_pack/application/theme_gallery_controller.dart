import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/theme_pack_importer.dart';
import '../data/theme_pack_store.dart';
import '../domain/theme_pack.dart';

/// 主题库状态。
enum ThemeGalleryStatus { idle, loading, ready, failed }

/// 主题库控制器：索引装载、导入、应用、删除。
///
/// 应用主题时通过 [onApplied] 把包交给主题层（P3 之前只影响圆角与壁纸），
/// 控制器本身不直接改 `ThemeProvider`，便于单测。
class ThemeGalleryController extends ChangeNotifier {
  ThemeGalleryController({
    required this.store,
    required this.importer,
    this.onApplied,
  });

  final ThemePackStore store;
  final ThemePackImporter importer;

  /// 应用/取消应用的回调（由 UI 层接到 ThemeProvider）。
  final void Function(ThemePack? pack)? onApplied;

  ThemeGalleryStatus _status = ThemeGalleryStatus.idle;
  String? _error;
  List<ThemePack> _packs = const [];
  String? _appliedId;
  bool _importing = false;
  List<ImportOutcome> _lastImport = const [];

  ThemeGalleryStatus get status => _status;
  String? get error => _error;
  List<ThemePack> get packs => _packs;
  String? get appliedId => _appliedId;
  bool get importing => _importing;
  List<ImportOutcome> get lastImport => _lastImport;

  ThemePack? get appliedPack =>
      _packs.where((p) => p.id == _appliedId).cast<ThemePack?>().firstWhere((p) => p != null,
          orElse: () => null);

  bool isApplied(String id) => _appliedId == id;

  Future<void> load() async {
    _status = ThemeGalleryStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final records = await store.loadIndex();
      final packs = <ThemePack>[];
      final missing = <InstalledPackRecord>[];
      for (final record in records) {
        final pack = await store.readPack(record.id, record.version);
        if (pack == null) {
          missing.add(record);
          continue;
        }
        packs.add(pack);
      }
      // 读不出来的包直接从索引里剔除（自愈）
      for (final record in missing) {
        await store.remove(record.id, record.version);
      }
      _packs = _orderPacks(packs, await store.loadAppliedId());
      _appliedId = await store.loadAppliedId();
      if (_appliedId != null && !_packs.any((p) => p.id == _appliedId)) {
        // 当前应用包已失效 → 回退默认并通知上层
        _appliedId = null;
        await store.setAppliedId(null);
        onApplied?.call(null);
      }
      _status = ThemeGalleryStatus.ready;
    } catch (error) {
      _status = ThemeGalleryStatus.failed;
      _error = '$error';
    }
    notifyListeners();
  }

  List<ThemePack> _orderPacks(List<ThemePack> packs, String? appliedId) {
    final sorted = [...packs];
    sorted.sort((a, b) {
      if (a.id == appliedId) return -1;
      if (b.id == appliedId) return 1;
      if (a.isBuiltin != b.isBuiltin) return a.isBuiltin ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(sorted);
  }

  /// 导入一批本地文件；成功后刷新列表，**不自动应用**。
  Future<List<ImportOutcome>> importPaths(List<String> paths) async {
    if (_importing) return _lastImport;
    _importing = true;
    notifyListeners();
    try {
      final results = <ImportOutcome>[];
      for (final path in paths) {
        results.add(await importer.importFile(File(path)));
      }
      _lastImport = results;
      final okCount = results.where((r) => r.ok).length;
      if (okCount > 0) {
        final records = await store.loadIndex();
        final packs = <ThemePack>[];
        for (final record in records) {
          final pack = await store.readPack(record.id, record.version);
          if (pack != null) packs.add(pack);
        }
        _packs = _orderPacks(packs, _appliedId);
      }
      return results;
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  Future<bool> apply(String id) async {
    final pack = _packs.firstWhere((p) => p.id == id, orElse: () => _packs.first);
    try {
      onApplied?.call(pack);
      await store.setAppliedId(pack.id);
      _appliedId = pack.id;
      _packs = _orderPacks(_packs, _appliedId);
      notifyListeners();
      return true;
    } catch (error) {
      _error = '$error';
      // 失败时保持原状
      onApplied?.call(null);
      notifyListeners();
      return false;
    }
  }

  /// 取消应用（回到默认主题）。
  Future<void> reset() async {
    onApplied?.call(null);
    await store.setAppliedId(null);
    _appliedId = null;
    _packs = _orderPacks(_packs, null);
    notifyListeners();
  }

  Future<bool> remove(String id) async {
    final pack = _packs.firstWhere((p) => p.id == id, orElse: () => _packs.first);
    final wasApplied = _appliedId == pack.id;
    if (wasApplied) {
      onApplied?.call(null);
      _appliedId = null;
      await store.setAppliedId(null);
    }
    await store.remove(pack.id, pack.version);
    _packs = List.unmodifiable(_packs.where((p) => p.id != pack.id));
    notifyListeners();
    return true;
  }

  Future<int> totalBytes() => store.totalBytes();
}
