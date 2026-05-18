# DX README

## 概览

`dx/` 是项目内的运行时基础框架，提供这些基础能力：

- 全局 manager 根节点
- 时间与倒计时
- 全局事件总线
- 弹窗管理
- 保存与序列化
- 本地化
- 简单对象池
- 通用数据存取
- 日志

当前自动加载入口：

- `DX="*res://dx/runtime/scenes/managers/dx.tscn"`

运行时通过 `DX_Root` 暴露统一访问入口：

- `DX.time`
- `DX.logger`
- `DX.signals`
- `DX.data`
- `DX.background_state`
- `DX.countdown`
- `DX.pool`
- `DX.save`
- `DX.localization`
- `DX.popup`

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
```

常用方法：

- `register_manager(manager_name, manager)`
- `get_manager(manager_name)`
- `has_manager(manager_name)`
- `get_manager_names()`

---

## 常量与路径

### DX_ScriptPaths

作用：

- 集中保存 DX 内脚本路径字符串
- 用法与 `scripts/constants/music_app_script_paths.gd` 一致

常用方式：

```gdscript
const DX_ScriptPathsType := preload("res://dx/runtime/scripts/constants/dx_script_paths.gd")
const AppBackgroundEventScript := preload(DX_ScriptPathsType.APP_BACKGROUND_EVENT)
```

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

## 数据与对象池

### DX_DataManager

作用：

- 简单运行时键值存储
- 按 bucket 分组

常用方法：

- `set_value(bucket, key, value)`
- `get_value(bucket, key, default_value := null)`
- `has_value(bucket, key)`
- `get_bucket(bucket)`
- `clear_bucket(bucket)`
- `clear()`

### DX_PoolManager

作用：

- 简单节点对象池
- 适合可复用节点模板
- 支持节点通过鸭子方法响应出池/回池生命周期

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

## 保存与序列化

### DX_SaveData

作用：

- 默认存档数据对象
- 当前内置承载音乐应用存档

常用方法：

- `normalize()`

### DX_SaveManager

作用：

- JSON 保存/读取
- 对象与字典相互转换
- 当前全局数据对象挂在 `DX.save.data`

常用方式：

```gdscript
var save_data := DX.save.load_data()
DX.save.save_data()
var ok := DX.save.save("app/test.json", {"ok": true})
```

常用方法：

- `save(relative_path, value)`
- `load(relative_path, default_value := null)`
- `load_data(relative_path := DEFAULT_DATA_PATH)`
- `save_data(relative_path := "")`

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
- `deserialize(data, target, max_depth := DEFAULT_MAX_DEPTH)`
- `create_from_dict(data, default_object, max_depth := DEFAULT_MAX_DEPTH)`
- `clear_cache()`
- `refresh_cache_for(object)`
- `clear_last_error()`
- `has_error()`
- `get_last_error()`
- `get_error_messages()`

---

## 本地化

### DX_LocalizationManager

作用：

- 文本翻译和绑定刷新
- 支持格式化参数

常用方式：

```gdscript
var text := DX.localization.text("music_app.home.title")
DX.localization.bind_text(label, "music_app.home.title")
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

- `PopupId.COMMON_DIALOG`
- `PopupId.COMMON_TOAST`
- `PopupId.MUSIC_APP_HOME`
- `PopupId.MUSIC_APP_PLAYLIST`
- `PopupId.MUSIC_APP_PLAYER`
- `PopupId.MUSIC_APP_PLAYBACK_QUEUE`
- `PopupId.MUSIC_APP_LOCAL_MUSIC`
- `PopupId.MUSIC_APP_LOCAL_SCAN`
- `PopupId.MUSIC_APP_PLUGIN_BROWSER`

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
DX.popup.show(DX_PopupRegistry.PopupId.MUSIC_APP_HOME)
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

---

## 当前建议

1. DX 内模块优先通过 `DX` 根访问 manager，不要在业务里重复 new manager。
2. 高频时间判断优先用 `DX.time.now_unix()`，需要展示时再转 `DX_DateTime`。
3. 跨模块广播优先用 `DX.signals`，局部节点通信优先用 Godot 原生 `signal`。
4. `dx_script_paths.gd` 只放路径字符串，不直接存 `preload()` 结果。
5. 弹窗根节点统一继承 `DX_PopupView`，并通过 `DX.popup` 管理。
