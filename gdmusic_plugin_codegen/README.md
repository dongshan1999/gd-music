# GDMusic Plugin Codegen

这个目录是一个独立开发区，用来研究把参考插件源码
`source_plugins/*/index.ts` 转成 Godot 可接收的 `.gd` 插件骨架。

此目录提供插件生成工具和运行时接口。Bilibili 的维护实现已迁移到
`res://plugins/builtin/bilibili.gd` 并随应用内置；`.generated/gdmusic_bilibili_plugin.gd`
保留为手动导入的兼容入口。其余自动生成骨架不会自动加载。主要用途：

1. 定义一版 Godot 原生插件接口
2. 定义一版 Godot 侧基础数据结构
3. 提供一个批量脚本，把 `source_plugins/*/index.ts` 生成 `.gd` 骨架

## 目录结构

```text
gdmusic_plugin_codegen/
  README.md
  scripts/
	generate_gd_skeletons.js
	check_source_utf8.js
  godot/
	base/
	  gdmusic_plugin_base.gd
	  gdmusic_plugin_methods.gd
	  gdmusic_plugin_types.gd
	runtime/
	  gdmusic_hash_utils.gd
	  gdmusic_http_json_client.gd
	  gdmusic_text_utils.gd
	tests/
	  test_bilibili_plugin.gd
  source_plugins/
	*/index.ts
  source_types/
	plugin.d.ts
  generated/
	*.gd
	manifest.json
	migration_report.md
```

## 设计原则

1. 以 `source_plugins/*/index.ts` 为主输入
2. 以 `source_types/plugin.d.ts` 为接口参考
3. 不尝试自动迁移复杂 JS 实现
4. 只自动生成：
   - 插件元信息
   - 支持的能力声明
   - JS 依赖和迁移难度标记
   - GDScript 方法骨架
   - TODO 注释

## 生成命令

```powershell
.\gdmusic_plugin_codegen\scripts\generate_all_source_plugins.ps1
```

或显式指定输入输出目录：

```powershell
node .\gdmusic_plugin_codegen\scripts\generate_gd_skeletons.js `
  "E:\project\godot\test\gdmusic_plugin_codegen\source_plugins" `
  "E:\project\godot\test\gdmusic_plugin_codegen\.generated"
```

如果不传参数，脚本会默认读取当前目录下的 `source_plugins/`
并输出到当前 codegen 目录下的隐藏目录 `gdmusic_plugin_codegen\.generated\`。

## 输出隔离

为避免 Godot 扫描到自动生成骨架并触发全局 `class_name` 冲突，
当前生成规则改为：

1. 默认输出到隐藏目录 `gdmusic_plugin_codegen\.generated\`
2. 生成的 `.gd` 文件不写 `class_name`

这样这些骨架文件既可以保留在项目附近继续人工迁移，
又不会和运行期脚本注册全局类名发生冲突。

## 源码编码检查

`source_plugins/` 和 `source_types/` 当前按 UTF-8 保存。
如果终端里看到中文乱码，不要直接改源码编码，先执行：

```powershell
node .\gdmusic_plugin_codegen\scripts\check_source_utf8.js
```

这个脚本只做 UTF-8 校验，不会修改文件。

## 当前限制

这个脚本不会自动转换这些实现细节：

- axios / HTTP 请求逻辑
- cheerio / HTML 解析
- crypto-js / 签名
- webdav / 文件系统协议
- JS 动态对象模型

所以生成结果是“可接收的 Godot 插件骨架”，不是“可直接运行的完整插件”。

## 当前输出内容

每个生成的 `.gd` 骨架现在还会附带：

- `JS_DEPENDENCIES`
- `MIGRATION_CAPABILITIES`
- `MIGRATION_DIFFICULTY`
- `get_migration_notes()`

同时会生成两个汇总文件：

- `.generated/manifest.json`
- `.generated/migration_report.md`

其中 `migration_report.md` 用来快速筛选先迁移的插件。

## 当前手写迁移进度

除了自动生成骨架外，当前还额外提供了手写的可运行插件：

- `.generated/gdmusic_airsonic_plugin.gd`
- `.generated/gdmusic_bilibili_plugin.gd`
- `.generated/gdmusic_kuaishou_plugin.gd`
- `.generated/gdmusic_audiomack_plugin.gd`
- `.generated/gdmusic_geciwang_plugin.gd`

这版插件目前包含：

- Airsonic / Subsonic 搜索
- 专辑详情
- 艺术家作品
- 榜单列表
- 榜单详情
- 媒体流地址生成
- 歌词获取
- token / password 两种认证路径

其中当前已覆盖：

- 搜索 `music / album / artist`
- 专辑详情
- UP 主作品
- 榜单列表
- 榜单详情
- 音源地址获取
- 收藏夹导入

对应测试入口：

- `godot/tests/test_bilibili_plugin.gd`

## 下一步建议

1. 先从 `low` 难度插件开始人工迁移
2. 抽一层 Godot 通用 HTTP 适配器
3. 再补 HTML / 签名 / WebDAV 等专项适配层
4. 最后再决定是否继续扩大迁移范围

## 当前进度

- 已支持通过脚本批量扫描 `source_plugins/*/index.ts`
- 已支持一键生成全部 `.gd` 骨架：
  - `.\gdmusic_plugin_codegen\scripts\generate_all_source_plugins.ps1`
- 默认输出目录已调整为：
  - `gdmusic_plugin_codegen\.generated\`
- 为避免 Godot 全局脚本类冲突，自动生成骨架已移除 `class_name`
- 当前已批量生成 13 个插件骨架
- 当前已有 5 个手写可运行插件：
  - `.generated/gdmusic_airsonic_plugin.gd`
  - `.generated/gdmusic_bilibili_plugin.gd`
  - `.generated/gdmusic_kuaishou_plugin.gd`
  - `.generated/gdmusic_audiomack_plugin.gd`
  - `.generated/gdmusic_geciwang_plugin.gd`
- `manifest.json` 已新增汇总信息：
  - `summary.totalPlugins`
  - `summary.handwrittenPlugins`
  - `summary.skeletonPlugins`
  - `summary.byDifficulty`
- `migration_report.md` 已新增：
  - 当前已完成插件列表
  - 推荐优先迁移候选列表
  - 完整状态表（status / priority / difficulty）

## 当前状态说明

- `.generated/` 中的文件属于“自动生成迁移骨架”
- `.generated/` 中带 `gdmusic_` 前缀的文件属于“手写可运行实现”
- 当前自动化能力主要覆盖：
  - 元信息提取
  - 支持方法识别
  - 迁移难度分析
  - GDScript 方法骨架生成
- 当前还不能把所有 TypeScript 插件直接全自动转成可运行 Godot 插件

## 下一步计划

1. 继续验证和修正当前手写可运行插件的联网行为：
   - `audiomack`
   - `geciwang`
   - `bilibili`
2. 继续按插件类型拆分迁移路线：
   - 纯 HTTP JSON 类插件优先提高自动化率
   - HTML 解析 / 签名 / WebDAV 类插件继续保留半自动迁移
3. 持续抽通用适配层，减少手写重复工作：
   - HTTP 请求适配
   - 时间处理适配
   - 签名 / Hash 适配
   - HTML 文本提取适配
   - WebDAV 适配
4. 继续迁移剩余 `low` / `medium` 难度插件，验证“骨架 -> 半自动补全 -> 可运行插件”的流程
5. 当前优先尝试：
   - `yinyuetai`
   - `youtube`
   - `suno`

## 只给网站地址时的开发方式

如果没有现成的 TypeScript 插件，而只是给一个网站地址，推荐按下面的顺序从 0 开发：

1. 先定义最小可用范围：
   - `search`
   - `get_media_source`
   - `get_lyric`（如果站点支持）
   - `get_toplists`（如果站点有稳定榜单接口）
2. 先看网站的真实网络请求，不先搬 DOM：
   - 搜索接口
   - 详情接口
   - 播放地址接口
   - 歌词接口
   - 榜单接口
   - cookie / token / 签名要求
3. 再判断难度：
   - 纯 JSON 公共接口：优先直接做
   - HTML 抽取：保留半自动
   - 强签名 / 指纹 / WebDAV：单独做专项适配
4. 代码实现时优先复用：
   - `gdmusic_http_json_client.gd`
   - `gdmusic_hash_utils.gd`
   - `gdmusic_text_utils.gd`
5. 最后再把站点数据映射成宿主所需结构，而不是照搬网站原始返回

这样做的目标不是“把网站页面搬进 Godot”，而是“直接围绕宿主接口做最小可运行插件”。
