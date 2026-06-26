# 待确认问题

1. 动态 debug 项当前采用源码注释标记而不是自定义 GDScript 注解，格式为 `# @dx_debug_action(...)`、`# @dx_debug_string(...)`、`# @dx_debug_number(...)`。这是因为 Godot 4 的 GDScript 不能像 C# 那样直接定义任意运行时特性。
2. 当前 debug 面板已经去除表达式区和运行时反射属性区，只保留显式标记出来的 action/string/number 调试项；如果后续需要更强能力，需要再单独设计交互和权限边界。
3. 触发按钮当前默认仅在 `OS.is_debug_build()` 下显示；如果后续需要正式包也可见，需要再确认发布策略。
