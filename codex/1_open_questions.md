# 待确认问题

1. 本次默认整理范围先按 `scripts/ui/music_app` 模块及其直接依赖执行：
   - `scripts/save/music`
   - `scripts/popup`
   - 场景路径也纳入常量替换
   - 本轮先忽略 `dx` 文件夹，不扩展到整个仓库所有脚本

2. GDScript 的 `extends "res://..."` / `preload("res://...")` 存在编译期限制。
   - 本次会优先把可替换的脚本路径与场景路径统一收口到 `scripts/constants/music_app_script_paths.gd`
   - 对于 `extends` 这类不适合走外部路径常量的场景，优先保留现有写法
