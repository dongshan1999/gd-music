# DX README

更新时间：2026-06-23 17:54

## 概览

`dx/` 是项目内的运行时基础框架，提供这些基础能力：

- 全局 manager 根节点
- 时间与倒计时
- 全局事件总线
- 弹窗管理
- 保存与序列化
- 跨平台虚拟文件路径
- 本地化
- 简单对象池
- JSON 配置管理
- 日志

当前自动加载入口：

- `DX="*res://dx/runtime/scenes/managers/dx.tscn"`

运行时通过 `DX_Root` 暴露统一访问入口：

- `DX.time`
- `DX.logger`
- `DX.signals`
- `DX.config`
- `DX.background_state`
- `DX.countdown`
- `DX.pool`
- `DX.save`
- `DX.files`
- `DX.localization`
- `DX.popup`
- `DX.debug`
- `DX.effect`
- `DX.res`

---

## 入口类

### DX_Root

作用：

- DX 框架总入口
- 启动并注册各 manager
- 转发生命周期：`in_ready / in_process / in_exit_tree / in_quit / in_pause / in_focus`

常用方式：

```gdscript
DX.logger.log("Boot", "ready")
var now_unix := DX.time.now_unix()
var dx_root := DX as DX_Root
var texture := DX.res.get_texture(&"example_icon")
```

常用方法：

- `register_manager(manager_name, manager)`
- `get_manager(manager_name)`
- `has_manager(manager_name)`
- `get_manager_names()`

---

## 时间

### DX_TimeManager

作用：

- 管理当前 unix 时间缓存
- 管理 debug 时间偏移
- 管理 `Engine.time_scale`

常用方式：

```gdscript
var now_unix := DX.time.now_unix()
var now_datetime := DX.time.now()
DX.time.set_debug_time_offset_seconds(3600)
```

常用方法：

- `now() -> DX_DateTime`
- `now_unix() -> int`
- `get_time_scale()`
- `set_time_scale(value)`
- `set_debug_time_scale(value, enabled := true)`
- `clear_debug_time_scale()`
- `set_debug_time_offset_seconds(value)`
- `get_debug_time_offset_seconds()`

### DX_DateTime

作用：

- 轻量时间对象包装
- 主存储为 `unix_timestamp`
- 年月日时分秒按需展开

常用方式：

```gdscript
var dt := DX.time.now()
var text := dt.format("yyyy-MM-dd HH:mm:ss")
var unix := dt.unix_timestamp
var date_only := dt.date
```

常用方法：

- `DX_DateTime.now()`
- `DX_DateTime.today()`
- `DX_DateTime.from_unix_timestamp(timestamp)`
- `DX_DateTime.from_dictionary(value)`
- `DX_DateTime.parse(value)`
- `clone()`
- `to_unix_timestamp()`
- `to_dictionary()`
- `to_iso_string()`
- `format(pattern := DEFAULT_FORMAT)`

常用属性：

- `year / month / day`
- `hour / minute / second`
- `weekday / day_of_week / day_of_year`
- `date`
- `unix_timestamp`

### DX_TimeUtility

作用：

- 纯静态时间工具
- 放纯函数，不持有运行时状态

适合：

- unix 转换
- 日期字典转换
- 起始日计算
- 时间格式化

常用方法：

- `now_unix(offset_seconds := 0)`
- `parse_unix(value)`
- `datetime_dict_from_unix(timestamp)`
- `unix_from_dictionary(value)`
- `unix_from_components(...)`
- `start_of_day_unix(timestamp)`
- `is_leap_year(year_value)`
- `days_in_month(year_value, month_value)`
- `calculate_weekday(year_value, month_value, day_value)`
- `format_datetime_dict(value, pattern := DEFAULT_FORMAT)`

---

## 全局事件

### DX_SignalManager

作用：

- DX 内的全局事件总线
- 使用“事件类 + 事件实例”模型，不再用字符串 key

常用方式：

```gdscript
dx.signals.subscribe(AppBackgroundEventScript, _on_app_background_changed)
dx.signals.fire(AppBackgroundEventScript.new(true))

func _on_app_background_changed(event: DX_AppBackgroundEvent) -> void:
	var is_background := event.is_background
```

常用方法：

- `subscribe(event_class, callback)`
- `unsubscribe(event_class, callback)`
- `fire(event)`
- `clear(event_class := null)`
- `has_listeners(event_class)`

### DX_SignalEvent

作用：

- 所有 DX 事件类的基类

### DX_AppPauseEvent
### DX_AppFocusEvent
### DX_AppBackgroundEvent

作用：

- 应用暂停事件
- 应用焦点事件
- 应用前后台状态事件

载荷字段：

- `DX_AppPauseEvent.paused`
- `DX_AppFocusEvent.focused`
- `DX_AppBackgroundEvent.is_background`

---

## 应用状态

### DX_BackgroundStateManager

作用：

- 监听 DX 根转发过来的 pause/focus 生命周期
- 向 `DX_SignalManager` 发出前后台相关事件

外部通常不直接调用，只由 `DX_Root` 驱动。

### DX_CountdownInfo

作用：

- 单个倒计时对象
- 保存结束时间、剩余秒数、运行状态
- 可订阅 update / completed 回调

常用方法：

- `is_completed()`
- `refresh_end_unix_timestamp(value)`
- `pause()`
- `resume(now_unix_timestamp)`
- `subscribe_update(callback)`
- `subscribe_completed(callback)`
- `notify_update()`
- `complete()`

枚举：

- `CountdownStatus.RUNNING`
- `CountdownStatus.PAUSED`
- `CountdownStatus.COMPLETED`

### DX_CountdownManager

作用：

- 管理多个倒计时
- 每帧刷新剩余时间
- 响应应用前后台切换，处理不允许后台运行的倒计时

常用方式：

```gdscript
var info := DX.countdown.start_seconds(&"demo", 30)
DX.countdown.subscribe_update(&"demo", _on_countdown_update)
DX.countdown.subscribe_completed(&"demo", _on_countdown_completed)
```

常用方法：

- `start(info)`
- `start_seconds(id, duration_seconds, destroy_on_complete := true, run_in_background := true)`
- `get_countdown(id)`
- `contains(id)`
- `subscribe_update(id, callback, immediate := true)`
- `subscribe_completed(id, callback)`
- `refresh_end_time(id, end_unix_timestamp)`
- `pause(id)`
- `resume(id)`
- `remove(id)`
- `clear(clear_inactive := true)`
- `get_active_items()`

---

## 配置与对象池

### DX_ConfigData

作用：

- 配置根数据对象
- 继承 `DX_JsonObject`
- 挂载业务配置根对象，例如 `data.app`
- `normalize()` 负责补齐缺失的业务配置对象

根配置伪代码：

```gdscript
class_name DX_ConfigData
extends DX_JsonObject

const AppConfigScript := preload("res://path/to/app_config.gd")

var app: AppConfigScript = AppConfigScript.new()

func normalize() -> void:
	if app == null:
		app = AppConfigScript.new()
	app.normalize()
```

业务配置伪代码：

```gdscript
class_name AppConfig
extends DX_JsonObject

const ItemConfigScript := preload("res://path/to/item_config.gd")
const RuleConfigScript := preload("res://path/to/rule_config.gd")

var items: Array[ItemConfigScript] = []
var rule: RuleConfigScript = RuleConfigScript.new()

func normalize() -> void:
	if items == null:
		items = []
	if rule == null:
		rule = RuleConfigScript.new()

	for item_config in items:
		if item_config != null:
			item_config.normalize()
	rule.normalize()

func get_item_config(item_id: StringName):
	for item_config in items:
		if item_config != null and item_config.item_id == item_id:
			return item_config
	return null
```

配置 JSON 形状：

```json
{
	"app": {
		"items": [
			{"item_id": "example_item", "display_name": "Example Item"}
		],
		"rule": {
			"some_value": 10
		}
	}
}
```

### DX_ConfigManager

作用：

- JSON 配置读取
- 当前配置对象挂在 `DX.config.data`
- 进入运行时后自动从默认配置路径加载一次
- 手动调用 `load(path)` 会替换 `DX.config.data`

常用方式：

```gdscript
var config_data := DX.config.data
var app_config = config_data.app
var item_config = app_config.get_item_config(&"example_item")
var value = app_config.rule.some_value

var reloaded_config_data := DX.config.load("res://path/to/config.json")
```

常用方法：

- `load(config_path := "res://dx/data/config.json")`

### DX_PoolManager

作用：

- 简单节点对象池
- 适合可复用节点模板
- 支持节点通过鸭子方法响应出池/回池生命周期
- 缓冲池只负责基础显隐；碰撞、相机、处理启停由对象在生命周期钩子里自行处理

常用方法：

- `init(name, template, max_capacity := 100, expiration_seconds := 300.0)`
- `contains(name)`
- `pop(name, parent := null)`
- `push(name, node, parent := null)`
- `clear(name := &"")`

可选钩子：

- `on_pool_pop()`：节点从池中取出后调用
- `on_pool_push()`：节点放回池中后调用

---

## 日志

### DX_Logger

作用：

- DX 框架日志输出
- 支持总开关、级别开关、tag 开关

常用方式：

```gdscript
DX.logger.log("Save", "saved")
DX.logger.warning("Pool", "node missing")
DX.logger.error("Popup", "popup host missing")
```

常用方法：

- `set_enable(enabled)`
- `set_info_enable(enabled)`
- `set_warning_enable(enabled)`
- `set_error_enable(enabled)`
- `set_tag_enable(tag, enabled)`
- `is_tag_enabled(tag)`
- `load_settings()`
- `save_settings()`
- `log(tag_or_message, message := null)`
- `warning(tag_or_message, message := null)`
- `error(tag_or_message, message := null)`
- `exception(tag, err)`

---

## 调试

### DX_DebugManager

作用：

- 管理运行时 Debug 面板数据
- 提供 Options 风格的调试入口
- 显示日志、系统信息、Profiler 信息
- 只在 debug build 中生效

常用入口：

- `DX.debug`
- Debug 触发器：`dx/runtime/scenes/debug/dx_debug_trigger.tscn`
- Debug 弹窗：`dx/runtime/scenes/debug/dx_debug_popup.tscn`

### Debug Options 约定

业务调试项统一写在 `asset/scripts/debug/options/` 下，继承：

```gdscript
extends "res://dx/runtime/scripts/debug/debug_options_base.gd"
```

Options 只有两类订阅方式：

1. `register_options()`：注册不依赖运行对象的集中式按钮。
2. `get_targets() + bind(target)`：Options 自己明确找到目标对象，再注册字段和方法。

底层 `dx/runtime/scripts/debug` 不做项目级全局搜索，不写死业务 Autoload 名，也不读取 `component_list/components` 这类业务字段。目标怎么找由项目自己的 Options 决定。

集中式按钮示例：

```gdscript
class_name ExampleDebugOptions
extends "res://dx/runtime/scripts/debug/debug_options_base.gd"

const CHEAT_GROUP := "Cheat"

func register_options() -> void:
	group_display(CHEAT_GROUP, GroupDisplayMode.INLINE, DEFAULT_OPTIONS_TARGET_ID)
	action(CHEAT_GROUP, "执行测试操作", Callable(self, "run_test_action"))

func run_test_action() -> void:
	var target := get_bound_target("ExampleTarget")
	if target != null and target.has_method("debug_run_test_action"):
		target.call("debug_run_test_action")
```

绑定运行对象示例：

```gdscript
class_name ExampleTargetDebugOptions
extends "res://dx/runtime/scripts/debug/debug_options_base.gd"

const TARGET_ID := "ExampleTarget"
const GROUP := "Example"
const TARGET_SCRIPT_PATH := "res://path/to/example_target.gd"

func get_target_id() -> String:
	return TARGET_ID

func get_targets() -> Array:
	var target := find_in_current_scene_by_script(TARGET_SCRIPT_PATH)
	return [target] if target != null else []

func bind(target: Object) -> void:
	register_target(target)
	group_display(GROUP, GroupDisplayMode.INLINE)
	string(GROUP, target, "debug_name", "名称")
	number(GROUP, target, "debug_value", "数值", {"min": 0, "max": 100, "step": 1})
	boolean(GROUP, target, "debug_enabled", "启用")
	action(GROUP, target, "debug_run_test_action", "执行")
```

目标查找辅助方法：

- `get_root_node(path)`：从 SceneTree root 下取节点，适合 Autoload。
- `get_current_scene()`：取当前场景根节点。
- `find_in_current_scene_by_script(script_path)`：只在当前场景节点树中按脚本路径找节点。

字段注册 API：

- `number(group, target, member_name, name, range := {}, target_id := "")`
- `string(group, target, member_name, name, target_id := "")`
- `boolean(group, target, member_name, name, target_id := "")`
- `select(group, target, member_name, name, options, target_id := "")`
- `readonly(group, getter, name, target_id := "")`
- `action(group, target, method_name, name, target_id := "")`
- `action(group, name, callback, member_name := "", target_id := "")`
- `group_display(group, mode, target_id := "")`
- `get_bound_target(target_id := "")`

`number` 传入范围时会显示为滑条：

```gdscript
number("Example", target, "debug_value", "数值", {
	"min": 0,
	"max": 100,
	"step": 1,
})
```

`select` 支持数组或 GDScript enum 字典：

```gdscript
enum DebugMode { NORMAL, GOD }

select("Example", target, "debug_mode", "模式", DebugMode)
select("Example", target, "debug_item_id", "选项", [
	{"label": "选项 A", "value": &"option_a"},
	{"label": "选项 B", "value": &"option_b"},
])
```

Group 显示模式：

- `GroupDisplayMode.INLINE`：字段直接显示。
- `GroupDisplayMode.COLLAPSE`：字段折叠在分组里。
- `GroupDisplayMode.PAGE`：分组作为分页入口，点击进入后显示字段。

新增 Options 后，需要在 `dx/dx.gd` 的 `DebugOptionsScripts` 中登记：

```gdscript
const DebugOptionsScripts: Array[Script] = [
	preload("res://path/to/example_target_debug_options.gd"),
]
```

约束：

- 不再使用 `@dx_debug_*` 注释扫描。
- 不使用 `bool()` 或 `enum()` 作为注册 API 名称，使用 `boolean()` 和 `select()`。
- 不在 DX 底层写项目业务名，项目目标查找写在项目 Options 里。
- 不在目标脚本里手动订阅/退订 Debug，避免业务逻辑被调试系统污染。

---

## 保存与序列化

### DX_SaveData

作用：

- 存档根数据对象
- 继承 `DX_JsonObject`
- 挂载业务存档根对象，例如 `data.app`
- `normalize()` 负责补齐缺失的业务存档对象

根存档伪代码：

```gdscript
class_name DX_SaveData
extends DX_JsonObject

const AppSaveDataScript := preload("res://path/to/app_save_data.gd")

var app: AppSaveDataScript = AppSaveDataScript.new()

func normalize() -> void:
	if app == null:
		app = AppSaveDataScript.new()
	app.normalize()
```

业务存档伪代码：

```gdscript
class_name AppSaveData
extends DX_JsonObject

const ProfileSaveDataScript := preload("res://path/to/profile_save_data.gd")
const RuntimeSaveDataScript := preload("res://path/to/runtime_save_data.gd")

var profile: ProfileSaveDataScript = ProfileSaveDataScript.new()
var runtime: RuntimeSaveDataScript = RuntimeSaveDataScript.new()

func normalize() -> void:
	if profile == null:
		profile = ProfileSaveDataScript.new()
	profile.normalize()

	if runtime == null:
		runtime = RuntimeSaveDataScript.new()
	runtime.normalize()

func clear() -> void:
	profile.clear()
	runtime.clear()
```

存档 JSON 形状：

```json
{
	"app": {
		"profile": {
			"selected_id": "example"
		},
		"runtime": {
			"status": "running"
		}
	}
}
```

### DX_SaveManager

作用：

- JSON 保存/读取
- 对象与字典相互转换
- 当前全局数据对象挂在 `DX.save.data`
- 进入运行时后自动读取默认存档路径
- `save(false)` 只标记脏数据，稍后自动保存
- `save(true)` 立即写盘
- 应用退出、暂停或失焦时会强制落盘

常用方式：

```gdscript
var save_data := DX.save.data
save_data.app.profile.selected_id = &"example"
save_data.app.runtime.status = &"running"

DX.save.save(false)

var loaded_save_data := DX.save.load()
var ok := DX.save.save(true)
```

常用方法：

- `save(force := true)`
- `load()`

### DX_JsonObject

作用：

- 序列化配置基类
- 对象可通过 `_get_serialize_config()` 定义序列化策略

### DX_JsonSerializer

作用：

- 对象 <-> 字典 序列化与反序列化工具
- `DX_SaveManager` 的底层依赖

常用方法：

- `serialize(obj, include_ignored := false, max_depth := DEFAULT_MAX_DEPTH)`
- `deserialize(data_or_json, target, max_depth := DEFAULT_MAX_DEPTH)`
- `create_from_dict(script_path, data, include_ignored := false, max_depth := DEFAULT_MAX_DEPTH)`
- `clear_cache()`
- `refresh_cache_for(object)`

---

## 文件

### DX_FileManager

作用：

- 提供跨平台文件读写入口
- 用虚拟路径隔离 Windows 原生路径、Godot `user://` 和 Android SAF `content://`
- 避免业务层把 Android 虚拟路径误当作真实文件路径

当前虚拟路径：

| 路径 | 平台 | 状态 | 说明 |
| --- | --- | --- | --- |
| `app://exports/demo.csv` | 全平台 | 可读写 | 映射到 `user://exports/demo.csv`，适合 App 私有导入导出缓存 |
| `local://E:/tmp/demo.csv` | Windows/editor | 可读写 | 映射到桌面原生路径，Android 不支持 |
| `saf-file://content://...` | Android | 可读写 | 单文件 SAF URI，适合导入或写入系统返回的单文件目标 |
| `saf-tree://content://...#exports/demo.csv` | Android | 可读写 | 目录 SAF URI + 相对路径，适合用户选择导出文件夹后写文件 |

常用方式：

```gdscript
var write_result := DX.files.write_text("app://exports/demo.csv", "时间,类型,金额\n")
if not write_result.ok:
	DX.logger.error("Files", write_result.error)

var read_result := DX.files.read_text("app://exports/demo.csv")
if read_result.ok:
	print(read_result.text)
```

常用方法：

- `app_path(relative_path) -> String`
- `local_path(native_path) -> String`
- `saf_file_path(uri) -> String`
- `saf_tree_path(uri, relative_path := "") -> String`
- `read_bytes(path) -> Dictionary`
- `read_text(path) -> Dictionary`
- `write_bytes(path, data) -> Dictionary`
- `write_text(path, text) -> Dictionary`
- `exists(path) -> bool`
- `make_dir_recursive(path) -> Dictionary`
- `globalize(path) -> String`
- `persist_saf_uri_permission(path_or_uri, persist := true) -> bool`
- `pick_file(title, filters, callback, current_directory := "") -> Dictionary`
- `pick_directory(title, callback, current_directory := "") -> Dictionary`
- `path_join(base_path, relative_path) -> String`

返回值约定：

```gdscript
{
	"ok": true,
	"path": "user://exports/demo.csv",
	"data": PackedByteArray(),
	"text": "file text",
	"bytes": 12,
	"error": ""
}
```

Android 规则：

- 不把 `content://` 转成绝对路径。
- 文件选择统一走 `DX.files.pick_file()` 和 `DX.files.pick_directory()`。
- 文件选择器拿到 URI 后，DX 会转成 `saf-file://content://...` 或 `saf-tree://content://...`。
- 向用户选择的 SAF 目录写文件时，使用 `DX.files.path_join(tree_path, file_name)` 得到 `saf-tree://...#file_name`。
- 需要长期访问时调用 `DX.files.persist_saf_uri_permission(uri)`。
- SAF 读写通过 Godot `FileAccess` 处理 `content://` 或 `content://...#relative/path`，不要自己拼真实路径。

---

## 本地化

### DX_LocalizationManager

作用：

- 文本翻译和绑定刷新
- 支持格式化参数

常用方式：

```gdscript
var text := DX.localization.text("example.title")
DX.localization.bind_text(label, "example.title")
DX.localization.set_locale(DX_LocalizationManager.Locale.ZH_CN)
```

常用方法：

- `text(tr_key, format_payload := null)`
- `bind_text(target, tr_key, format_payload := null)`
- `unbind_text(target)`
- `set_locale(locale)`
  - Recommended: `DX_LocalizationManager.Locale.EN`, `DX_LocalizationManager.Locale.ZH`, `DX_LocalizationManager.Locale.ZH_CN`
- `refresh_all()`

### DX_LocalizeComp

作用：

- 节点级本地化组件
- 进入树后自动绑定目标节点文本

适合：

- Label / Button / RichTextLabel 等有 `text` 属性的节点

---

## 弹窗

### DX_PopupRegistry

作用：

- 统一登记弹窗 id 和对应场景

常用方法：

- `has_popup(popup_id)`
- `get_scene(popup_id)`

枚举：

- `PopupId.EXAMPLE_POPUP`
- `PopupId.EXAMPLE_FULLSCREEN_POPUP`

实际枚举以 `dx/runtime/scripts/managers/popup/popup_registry.gd` 中的 `PopupId` 为准。

### DX_PopupView

作用：

- 所有弹窗页面根视图基类

常用方法：

- `get_resolved_popup_layer()`
- `close_popup()`
- `on_popup_shown()`
- `on_popup_hidden()`

枚举：

- `PopupLayer.NORMAL`
- `PopupLayer.FULLSCREEN`

### DX_PopupManager

作用：

- 弹窗显示、隐藏、置顶、分层宿主管理

信号：

- `popup_shown(popup_id, popup)`
- `popup_hidden(popup_id)`

常用方式：

```gdscript
DX.popup.show(DX_PopupRegistry.PopupId.EXAMPLE_POPUP)
DX.popup.hide()
```

常用方法：

- `show(popup_id)`
- `get_popup(popup_id)`
- `hide()`
- `hide_popup(target_popup)`
- `is_showing()`
- `get_current_popup()`
- `set_normal_host(host)`
- `set_fullscreen_host(host)`
- `clear_normal_host(host := null)`
- `clear_fullscreen_host(host := null)`

### 弹窗 CV 约定

业务弹窗采用 CV 结构：

- Controller：纯 GDScript 类，继承 `RefCounted`，不作为场景节点存在。负责弹窗数据、状态、按钮行为和关闭回调等控制逻辑。
- View：继承 `DX_PopupView`，挂在弹窗预制体根节点。只负责 UI 节点引用、显示刷新和把按钮事件转发给 Controller。
- 弹窗预制体只落 View 和 UI 节点，不添加 Controller 节点。
- 每个弹窗独立目录存放，场景名、view 脚本名、controller 脚本名使用同一弹窗前缀，例如：
  - `asset/scenes/ui/popups/example_popup/example_popup.tscn`
  - `asset/scripts/ui/popups/example_popup/example_popup_view.gd`
  - `asset/scripts/ui/popups/example_popup/example_popup_controller.gd`
- 弹窗必须在 `DX_PopupRegistry.PopupId` 和 `POPUP_SCENES` 中注册，再通过 `DX.popup.show(popup_id)` 打开。
- 业务入口只负责传入数据或回调，不直接操作弹窗内部 UI 节点。

---

## 当前建议

1. DX 内模块优先通过 `DX` 根访问 manager，不要在业务里重复 new manager。
2. 高频时间判断优先用 `DX.time.now_unix()`，需要展示时再转 `DX_DateTime`。
3. 跨模块广播优先用 `DX.signals`，局部节点通信优先用 Godot 原生 `signal`。
4. 弹窗根节点统一继承 `DX_PopupView`，并通过 `DX.popup` 管理。
5. 业务导入导出优先走 `DX.files`，不要在 Android 上把 `content://` 当作原生路径处理。
