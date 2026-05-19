# GDMusic Plugin Codegen

这个目录是一个独立开发区，用来研究把参考插件源码
`source_plugins/*/index.ts` 转成 Godot 可接收的 `.gd` 插件骨架。

这里不接入当前项目运行逻辑，只做三件事：

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
	plugins/
	  gdmusic_airsonic_plugin.gd
	  gdmusic_bilibili_plugin.gd
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
node .\gdmusic_plugin_codegen\scripts\generate_gd_skeletons.js `
  "E:\project\godot\test\gdmusic_plugin_codegen\source_plugins" `
  "E:\project\godot\test\gdmusic_plugin_codegen\generated"
```

如果不传参数，脚本会默认读取当前目录下的 `source_plugins/`
并输出到当前目录下的 `generated/`。

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

- `generated/manifest.json`
- `generated/migration_report.md`

其中 `migration_report.md` 用来快速筛选先迁移的插件。

## 当前手写迁移进度

除了自动生成骨架外，当前还额外提供了一版手写的可运行插件：

- `godot/plugins/gdmusic_airsonic_plugin.gd`

这版插件目前包含：

- Airsonic / Subsonic 搜索
- 专辑详情
- 艺术家作品
- 榜单列表
- 榜单详情
- 媒体流地址生成
- 歌词获取
- token / password 两种认证路径

另外还额外提供了一版手写的 Bilibili 插件：

- `godot/plugins/gdmusic_bilibili_plugin.gd`

当前已覆盖：

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
