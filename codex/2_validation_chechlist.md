# 验收清单

1. `scripts/ui/music_app/controllers` 下所有控制器方法都补充中文注释。
2. `scripts/ui/music_app/music_app_showcase.gd` 的方法都补充中文注释。
3. 新增 `scripts/constants/` 下的脚本路径常量脚本，并在音乐 App 相关脚本中替换对应硬编码脚本路径。
4. 场景路径常量已统一收口到 `scripts/constants/music_app_script_paths.gd`，并在音乐 App 相关脚本中替换对应硬编码场景路径。
5. 新增 `scripts/constants/` 下的表情/符号常量脚本，并替换音乐 App 相关脚本中的硬编码表情符号。
6. 本轮不改 `dx` 文件夹脚本。
7. Godot 项目能够正常启动，不能引入新的 GDScript 解析错误。
