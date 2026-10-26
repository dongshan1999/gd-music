class_name MusicAppBilibiliLoginPopup
extends "res://assets/scripts/ui/music_app/music_app_page.gd"

## B 站账号登录弹窗：默认扫码，也支持直接粘贴 cookie。

const LoginControllerScript := preload(
	"res://assets/scripts/ui/music_app/controllers/music_app_plugin_login_controller.gd"
)
const QrCodeScript := preload("res://dx/runtime/scripts/utility/qr_code.gd")

const POLL_INTERVAL_SECONDS := 2.0
const QR_PIXELS_PER_MODULE := 6
const QR_QUIET_ZONE := 4

@onready var status_label: Label = %LoginStatusLabel
@onready var qr_frame: PanelContainer = %LoginQrFrame
@onready var qr_texture: TextureRect = %LoginQrTexture
@onready var hint_label: Label = %LoginHintLabel
@onready var manual_toggle_button: Button = %LoginManualToggleButton
@onready var manual_box: VBoxContainer = %LoginManualBox
@onready var cookie_input: LineEdit = %LoginCookieInput
@onready var apply_button: Button = %LoginApplyButton
@onready var refresh_button: Button = %LoginRefreshButton
@onready var close_button: Button = %LoginCloseButton

var _controller
var _action_controller
var _login_controller
var _poll_timer: Timer
var _qrcode_key := ""
var _is_polling := false
var _is_busy := false
var _is_bound := false
var _is_logged_in := false

func setup(controller, action_controller = null) -> void:
	_controller = controller
	_action_controller = action_controller
	_login_controller = LoginControllerScript.new(controller)
	bind()
	await _sync_login_state()
	if _is_logged_in:
		return
	_request_qrcode()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	close_button.pressed.connect(close_popup)
	refresh_button.pressed.connect(_on_refresh_pressed)
	manual_toggle_button.pressed.connect(_on_manual_toggle_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	cookie_input.text_submitted.connect(func(_text: String) -> void: _on_apply_pressed())

	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_SECONDS
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll_timeout)
	add_child(_poll_timer)

func on_popup_shown() -> void:
	if _login_controller == null:
		return
	if _qrcode_key.is_empty():
		_request_qrcode()
	if not _is_logged_in:
		_sync_login_state()

func close_popup() -> void:
	_stop_polling()
	super.close_popup()

func _sync_login_state() -> void:
	if _login_controller == null:
		return
	var status: Dictionary = await _login_controller.fetch_current_login()
	if bool(status.get("logged_in", false)):
		_is_logged_in = true
		_stop_polling()
		var uname := str(status.get("uname", "")).strip_edges()
		status_label.text = "已登录：%s" % uname if not uname.is_empty() else "已登录"
		status_label.add_theme_color_override("font_color", Color(0.62, 0.85, 0.66, 1.0))
		qr_frame.visible = false
		qr_texture.texture = null
		hint_label.text = "当前账号已登录，搜索会带上登录凭据。"
		refresh_button.text = "重新扫码登录"
		refresh_button.visible = true
		return
	_is_logged_in = false
	status_label.text = "未登录（匿名访问，可能被风控拦截）"
	status_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82, 1.0))
	refresh_button.visible = false

func _request_qrcode() -> void:
	if _login_controller == null or _is_busy:
		return
	_is_logged_in = false
	_is_busy = true
	_stop_polling()
	refresh_button.visible = false
	hint_label.text = "正在申请二维码…"
	qr_frame.visible = false
	qr_texture.texture = null

	var result: Dictionary = await _login_controller.generate_qrcode()
	_is_busy = false
	if result.is_empty():
		hint_label.text = str(_login_controller.last_error) if not _login_controller.last_error.is_empty() else "二维码申请失败，请稍后重试。"
		refresh_button.text = "重试"
		refresh_button.visible = true
		return

	_qrcode_key = str(result.get("qrcode_key", ""))
	var login_url := str(result.get("url", ""))
	var image: Image = QrCodeScript.encode_image(
		login_url,
		QR_PIXELS_PER_MODULE,
		QR_QUIET_ZONE
	)
	if image == null or image.is_empty():
		hint_label.text = "二维码生成失败，请重试。"
		refresh_button.text = "重试"
		refresh_button.visible = true
		return

	qr_texture.texture = ImageTexture.create_from_image(image)
	qr_frame.visible = true
	hint_label.text = "用手机 B 站 App 扫描二维码并确认登录"
	_start_polling()

func _start_polling() -> void:
	if _poll_timer == null or _qrcode_key.is_empty():
		return
	_is_polling = true
	_poll_timer.start()

func _stop_polling() -> void:
	_is_polling = false
	if _poll_timer != null:
		_poll_timer.stop()

func _on_poll_timeout() -> void:
	if not _is_polling or _is_busy:
		return
	_is_busy = true
	var result: Dictionary = await _login_controller.poll_qrcode(_qrcode_key)
	_is_busy = false
	if not _is_polling:
		return

	match str(result.get("state", "")):
		LoginControllerScript.STATE_WAITING:
			hint_label.text = "等待扫码…"
		LoginControllerScript.STATE_SCANNED:
			hint_label.text = "已扫码，请在手机上确认登录"
		LoginControllerScript.STATE_EXPIRED:
			_stop_polling()
			qr_frame.visible = false
			hint_label.text = "二维码已失效。"
			refresh_button.text = "刷新二维码"
			refresh_button.visible = true
		LoginControllerScript.STATE_SUCCESS:
			_stop_polling()
			hint_label.text = "登录成功，正在保存凭据…"
			await _apply_cookie(str(result.get("cookie", "")))
		_:
			_stop_polling()
			hint_label.text = str(_login_controller.last_error) if not _login_controller.last_error.is_empty() else "登录状态异常，请刷新二维码。"
			refresh_button.text = "刷新二维码"
			refresh_button.visible = true

func _on_apply_pressed() -> void:
	var cookie_text := cookie_input.text.strip_edges()
	if cookie_text.is_empty():
		hint_label.text = "请先粘贴 cookie。"
		return
	await _apply_cookie(cookie_text)

func _apply_cookie(cookie_header: String) -> void:
	if _is_busy:
		return
	_is_busy = true
	hint_label.text = "正在校验登录凭据…"
	var result: Dictionary = await _login_controller.apply_cookie(cookie_header)
	_is_busy = false
	if bool(result.get("ok", false)):
		var uname := str(result.get("uname", "")).strip_edges()
		cookie_input.text = ""
		await _sync_login_state()
		_show_toast("登录成功" if uname.is_empty() else "登录成功：%s" % uname)
		close_popup()
		return
	hint_label.text = str(result.get("message", "登录失败，请重试。"))

func _on_refresh_pressed() -> void:
	# 上一次申请可能卡死在网络 await 上（协程不会恢复），这里强制解锁后重来。
	if _is_busy:
		_is_busy = false
	_request_qrcode()

func _on_manual_toggle_pressed() -> void:
	manual_box.visible = not manual_box.visible
	manual_toggle_button.text = "收起粘贴框" if manual_box.visible else "改用粘贴 Cookie"

func _show_toast(message: String) -> void:
	if _action_controller != null and _action_controller.has_method("show_toast"):
		_action_controller.show_toast(message)
