/// 全局圆角 token。
///
/// 设计约定（见 `docs/design/DESIGN_SYSTEM.md`）：
/// - 只有 `sm / md / lg / sheet` 四档可被主题包覆盖，范围限定在原值的 0.5×–2×；
/// - `pill`（999）属于语义值（胶囊形），**永不可覆盖**；
/// - 未应用主题包时必须与历史常量完全一致，保证零视觉回归。
///
/// 覆盖是进程级状态：由主题包层在应用/取消主题时调用 [applyOverrides] /
/// [resetOverrides]，随后由 `ThemeProvider.notifyListeners()` 触发重建。
abstract final class AppRadius {
  static const double _sm = 8.0;
  static const double _md = 12.0;
  static const double _lg = 16.0;
  static const double _sheet = 24.0;

  /// 胶囊圆角：语义值，不参与主题覆盖。
  static const double pill = 999.0;

  /// 主题包允许的取值范围（相对原值的倍数），与转换器 `pack.py` 保持一致。
  static const double minFactor = 0.5;
  static const double maxFactor = 2.0;

  static double? _smOverride;
  static double? _mdOverride;
  static double? _lgOverride;
  static double? _sheetOverride;

  static double get sm => _smOverride ?? _sm;
  static double get md => _mdOverride ?? _md;
  static double get lg => _lgOverride ?? _lg;
  static double get sheet => _sheetOverride ?? _sheet;

  /// 原值，供 `AppTheme` 兼容常量与测试断言使用。
  static const double defaultSm = _sm;
  static const double defaultMd = _md;
  static const double defaultLg = _lg;
  static const double defaultSheet = _sheet;

  static bool get isOverridden =>
      _smOverride != null || _mdOverride != null || _lgOverride != null || _sheetOverride != null;

  /// 应用主题包的圆角。超出 0.5×–2× 的值会被夹紧而不是拒绝，
  /// 避免一个坏包让整个界面布局崩掉。
  static void applyOverrides({
    double? sm,
    double? md,
    double? lg,
    double? sheet,
  }) {
    _smOverride = _clamp(sm, _sm);
    _mdOverride = _clamp(md, _md);
    _lgOverride = _clamp(lg, _lg);
    _sheetOverride = _clamp(sheet, _sheet);
  }

  /// 回到出厂圆角（未应用主题包 / 主题包损坏回退时调用）。
  static void resetOverrides() {
    _smOverride = null;
    _mdOverride = null;
    _lgOverride = null;
    _sheetOverride = null;
  }

  static double? _clamp(double? value, double base) {
    if (value == null || value.isNaN || value.isInfinite) return null;
    final min = base * minFactor;
    final max = base * maxFactor;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
