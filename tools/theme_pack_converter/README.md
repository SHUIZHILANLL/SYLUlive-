# 主题包转换器（theme_pack_converter）

把 MIUI / HyperOS 主题包（`.mtheme` 解包后的目录）转换成 SYLUlive 的 `.syltheme` 主题包。

**只读输入、离线运行、不碰 App 代码。** 产物不要提交进仓库。

---

## 为什么需要它

MIUI 主题包是给 Android 系统 App 用的资源覆盖包：一个包 27 个模块、390 MB，里面 90% 是短信/相机/指南针这类我们根本用不上的资源，资源名也是 Android 体系（`cc_qs_tile_icon_color`、`com.android.systemui`）。

SYLUlive 真正需要的只有：**一套语义色 + 1~3 张壁纸 + 几张预览图 +（可选）字体**。所以中间必须有一层转换，把"Android 资源"翻译成"我们的 token"。

## 用法

```bash
# 1. 只读扫描：看有哪些模块、哪些颜色候选
python cli.py inspect "D:/themes/某个主题目录"

# 2. 构建主题包
python cli.py build "D:/themes/某个主题目录" \
    -o "D:/out" \
    --id shenli-joy13 \
    --name "深理·鲸" \
    --brand "#FF7B8BCF" \
    --font "../../client/assets/fonts/NotoSansCJKsc-Regular.otf" \
    --lib "../../client/lib"

# 3. 独立校验产物
python cli.py verify "D:/out/shenli-joy13.syltheme"

# 4. 统计 App 实际用到的 Material 图标（P4 换图标时用）
python cli.py icons --flutter-root "C:/flutter" --lib "../../client/lib"
```

产物：`<out>/<id>.syltheme` + `<out>/pack-report.md`（取色、体积、字体子集、tokens 全在这里）。

## 包结构

```
manifest.json     schema/id/name/version/minAppVersion/source/author/license/bytes
                  assets[]（含逐文件 sha256）/ preview[] / capabilities / notes
tokens.json       { "light": {...}, "dark": {...} }，只允许白名单 key
assets/
  wallpaper_portrait.jpg   1080×2400 q85
  wallpaper_landscape.jpg  2400×1080 q85
  wallpaper_lock.jpg       可选
  preview_*.jpg            720 宽，≤200KB
  fonts/<family>.ttf       子集字体（可选）
```

## 编码进来的规则（与 App 侧必须一致）

| 规则 | 实现位置 |
|---|---|
| tokens 白名单（超出即拒绝导入） | `pack.ALLOWED_TOKENS` |
| 永不可覆盖：`success/warning/danger/info`、`radius.pill`、全部 `spacing.*` | `pack.FORBIDDEN_*` |
| 圆角只允许原值 0.5×–2× | `pack.RADIUS_MIN/MAX_FACTOR` |
| 品牌色：色块 ≥3:1；`tag.text` 与 `tag.bg` ≥4.5:1 | `pack.build_tokens` + `colorutil` |
| 修正幅度 >25% 的颜色**直接丢弃**并告警（不悄悄变色） | `pack.build_tokens` |
| 字体必须子集化，家族名带包 id 前缀 | `fontsub.FONT_FAMILY` |

## 明确不做的事

- **不解析 `lockscreen/advance/manifest.xml`**：MIUI 高级锁屏是专有表达式语言，且该主题的锁屏代码有第三方版权声明。
- **不导入 `icons/res/drawable-*/*.png`**：478 个按 Android 包名命名的图标在 Flutter 里没有对应物。
- **不猜 `bg/surface/text/border`**：主题没提供中性色时宁可交给 App 默认值回落，也不从 9-patch 里瞎取色。
- **不打包产物进仓库**：`.syltheme` 是构建物。

## 测试

```bash
python -m unittest test_converter -v
```

## 已知限制

- 只读 `theme_values.xml` 的 `<color>`；`<dimen>` / `<drawable>` 覆盖暂不消费。
- `nightmode/` 里的深色值目前与浅色合并统计，尚未按 `nightmode/` 单独出 dark 调色板。
- 壁纸用 cover 裁切（居中）；人脸/主体偏置需要人工换图。
