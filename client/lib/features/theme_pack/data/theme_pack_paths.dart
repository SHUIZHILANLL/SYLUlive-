import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 主题包的设备侧目录布局。
///
/// 单独抽出来是为了：① 测试可注入临时目录，不碰真实 App 目录；
/// ② 所有路径只有一个来源，避免索引/解压/壁纸各处自己拼字符串。
///
/// ```
/// <root>/
///   index.json                已安装索引 + 当前应用
///   builtin/                  随 App 交付的默认包（只读语义）
///   <id>@<version>/           一个已安装的包
///   .staging/<uuid>/          导入中的临时目录（校验通过才 rename 进来）
///   .trash/<uuid>/            删除中
/// ```
class ThemePackPaths {
  ThemePackPaths(this.root);

  /// 根目录。
  final Directory root;

  /// 生产环境：App 支持目录下的 `theme_packs/`。
  static Future<ThemePackPaths> forApp() async {
    final support = await getApplicationSupportDirectory();
    return ThemePackPaths(Directory('${support.path}/theme_packs'));
  }

  File get indexFile => File('${root.path}/index.json');
  Directory get builtinDir => Directory('${root.path}/builtin');
  Directory get stagingDir => Directory('${root.path}/.staging');
  Directory get trashDir => Directory('${root.path}/.trash');

  /// 包目录名：`<id>@<version>`，允许同 id 多版本共存。
  String packDirName(String id, String version) => '$id@$version';

  Directory packDir(String id, String version) =>
      Directory('${root.path}/${packDirName(id, version)}');

  File packManifest(String id, String version) =>
      File('${packDir(id, version).path}/manifest.json');

  /// 校验完成标记：只有它存在才认为安装完整。
  File verifiedMarker(String id, String version) =>
      File('${packDir(id, version).path}/.verified');

  Future<void> ensureLayout() async {
    for (final dir in [root, builtinDir, stagingDir, trashDir]) {
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
    }
  }
}
