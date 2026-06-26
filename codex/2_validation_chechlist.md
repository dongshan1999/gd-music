# 验收清单

1. 已新增 DX 运行时触发按钮场景 `res://dx/runtime/scenes/debug/dx_debug_trigger.tscn`，用于打开统一 debug 工具。
2. 已新增 DX 动态 debug 弹窗 `res://dx/runtime/scenes/debug/dx_debug_popup.tscn`，包含动态调试项区、日志输出区。
3. 已新增 `res://dx/runtime/scripts/managers/debug/debug_manager.gd`，并接入 DX manager 生命周期，不再依赖业务专用 debug controller/view。
4. 已在 `popup_registry.gd` 注册 `DX_DEBUG` 弹窗。
5. 已支持通过源码注释标记生成动态调试项：
   `# @dx_debug_action(...)`
   `# @dx_debug_string(...)`
   `# @dx_debug_number(...)`
6. 已去除运行时反射属性面板，只保留显式标记的调试项。
7. 已去除表达式执行与表达式监视区。
8. 日志面板已接入 `DX.logger` 历史输出；当前项目已能捕获 DX 侧日志与接入 `OS.add_logger()` 的原生日志历史。
9. 已验证项目可正常启动；当前剩余输出主要是仓库内既有 warning，不是本轮新增 parse error。
