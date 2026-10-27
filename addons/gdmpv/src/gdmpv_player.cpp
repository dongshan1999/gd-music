#include "gdmpv_player.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdio>
#include <thread>

using namespace godot;

// ── 生命周期 ──────────────────────────────────────────────

GDMPVPlayer::GDMPVPlayer() = default;

GDMPVPlayer::~GDMPVPlayer() {
	shutdown();
}

void GDMPVPlayer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize"), &GDMPVPlayer::initialize);
	ClassDB::bind_method(D_METHOD("shutdown"), &GDMPVPlayer::shutdown);

	ClassDB::bind_method(D_METHOD("load_file", "url", "headers"), &GDMPVPlayer::load_file, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("play"), &GDMPVPlayer::play);
	ClassDB::bind_method(D_METHOD("pause"), &GDMPVPlayer::pause);
	ClassDB::bind_method(D_METHOD("toggle_pause"), &GDMPVPlayer::toggle_pause);
	ClassDB::bind_method(D_METHOD("stop"), &GDMPVPlayer::stop);
	ClassDB::bind_method(D_METHOD("seek", "seconds"), &GDMPVPlayer::seek);

	ClassDB::bind_method(D_METHOD("get_position"), &GDMPVPlayer::get_position);
	ClassDB::bind_method(D_METHOD("get_duration"), &GDMPVPlayer::get_duration);
	ClassDB::bind_method(D_METHOD("is_playing"), &GDMPVPlayer::is_playing);
	ClassDB::bind_method(D_METHOD("is_paused"), &GDMPVPlayer::is_paused);
	ClassDB::bind_method(D_METHOD("is_initialized"), &GDMPVPlayer::is_initialized);
	ClassDB::bind_method(D_METHOD("get_last_error"), &GDMPVPlayer::get_last_error);
	ClassDB::bind_method(D_METHOD("set_volume", "ratio"), &GDMPVPlayer::set_volume);
	ClassDB::bind_method(D_METHOD("get_volume"), &GDMPVPlayer::get_volume);

	ADD_SIGNAL(MethodInfo("finished"));
	ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::BOOL, "playing")));
	ADD_SIGNAL(MethodInfo("error_occurred", PropertyInfo(Variant::STRING, "message")));
}

Error GDMPVPlayer::initialize() {
	if (initialized) {
		return OK;
	}

	ctx = mpv_create();
	if (ctx == nullptr) {
		last_error = "mpv_create 失败";
		return ERR_CANT_CREATE;
	}

	// 这些选项必须在 mpv_initialize 之前设置
	mpv_set_option_string(ctx, "vo", "null");               // 纯音频，不要视频输出
	mpv_set_option_string(ctx, "vid", "no");                // 不解析视频轨
	mpv_set_option_string(ctx, "audio-exclusive", "no");    // 与 Godot AudioServer 共存
	mpv_set_option_string(ctx, "audio-client-name", "gd-music");
	mpv_set_option_string(ctx, "cache", "yes");             // 网络流缓存
	mpv_set_option_string(ctx, "demuxer-max-bytes", "150MiB");
	mpv_set_option_string(ctx, "demuxer-readahead-secs", "30");
	mpv_set_option_string(ctx, "idle", "yes");              // 无文件时不退出实例
	mpv_set_option_string(ctx, "keep-open", "no");
	// 只在错误级别出声：上游的零音轨问题已修完，全部打开会刷屏并拖慢主线程。
	mpv_set_option_string(ctx, "msg-level", "all=error");

	if (mpv_initialize(ctx) < 0) {
		last_error = "mpv_initialize 失败";
		mpv_terminate_destroy(ctx);
		ctx = nullptr;
		return ERR_CANT_CREATE;
	}

	// 观察属性：由事件线程维护缓存，主线程只读
	mpv_observe_property(ctx, 1, "time-pos", MPV_FORMAT_DOUBLE);
	mpv_observe_property(ctx, 2, "duration", MPV_FORMAT_DOUBLE);
	mpv_observe_property(ctx, 3, "pause", MPV_FORMAT_FLAG);
	mpv_observe_property(ctx, 4, "eof-reached", MPV_FORMAT_FLAG);
	mpv_observe_property(ctx, 5, "paused-for-cache", MPV_FORMAT_FLAG);

	// 让 mpv 把日志作为事件抛出，由事件线程转发进 logcat。
	// 只请求 error 及以上：status 级会把每条 cplayer/info 都转发上来，稳定播放时白白刷屏。
	mpv_request_log_messages(ctx, "error");

	event_running.store(true);
	std::thread([this] { _event_loop(); }).detach();

	initialized = true;
	return OK;
}

void GDMPVPlayer::shutdown() {
	if (shutting_down) {
		return;
	}
	shutting_down = true;

	if (event_running.exchange(false)) {
		// 唤醒处于 wait_event 阻塞中的事件线程
		if (ctx != nullptr) {
			mpv_wakeup(ctx);
		}
		// 事件线程会在下一次循环发现 event_running == false 后自然退出
		std::this_thread::sleep_for(std::chrono::milliseconds(30));
	}

	if (ctx != nullptr) {
		mpv_terminate_destroy(ctx);
		ctx = nullptr;
	}
	initialized = false;
}

// ── 事件线程 ──────────────────────────────────────────────

void GDMPVPlayer::_event_loop() {
	while (event_running.load()) {
		mpv_event *ev = mpv_wait_event(ctx, 0.5);
		if (ev == nullptr) {
			continue;
		}
		if (ev->event_id == MPV_EVENT_NONE) {
			continue;
		}
		_handle_mpv_event(ev);
	}
}

void GDMPVPlayer::_handle_mpv_event(mpv_event *ev) {
	switch (ev->event_id) {
		case MPV_EVENT_FILE_LOADED: {
			std::lock_guard<std::mutex> lock(state_mutex);
			cached_eof = false;
			cached_duration = -1.0;
			break;
		}
		case MPV_EVENT_PROPERTY_CHANGE: {
			auto *prop = static_cast<mpv_event_property *>(ev->data);
			if (prop == nullptr || prop->data == nullptr) {
				break;
			}
			std::lock_guard<std::mutex> lock(state_mutex);
			const std::string name = prop->name != nullptr ? prop->name : "";
			if (name == "time-pos") {
				cached_position = *static_cast<double *>(prop->data);
			} else if (name == "duration") {
				cached_duration = *static_cast<double *>(prop->data);
			} else if (name == "pause") {
				cached_paused = *static_cast<int *>(prop->data) != 0;
			} else if (name == "eof-reached") {
				cached_eof = *static_cast<int *>(prop->data) != 0;
			} else if (name == "paused-for-cache") {
				// 缓冲中：暂不改变 playing 状态，供上层展示 loading
			}
			break;
		}
		case MPV_EVENT_LOG_MESSAGE: {
			auto *msg = static_cast<mpv_event_log_message *>(ev->data);
			if (msg != nullptr && msg->text != nullptr) {
				UtilityFunctions::print("[gdmpv][", msg->prefix, "/", msg->level, "] ", String(msg->text).strip_edges());
			}
			break;
		}
		case MPV_EVENT_END_FILE: {
			auto *end = static_cast<mpv_event_end_file *>(ev->data);
			const int reason = end != nullptr ? (int)end->reason : -1;
			// ⚠ STOP 不是「播完了」。切歌或手动 stop 时 mpv 也会发 END_FILE(STOP)，
			// 早期版本把任何 END_FILE 都当成播放结束，导致「切歌 → STOP →
			// finished → 切歌」的死循环（表现为歌曲无限快进）。只有 EOF 才算自然播完。
			const bool natural_eof = reason == MPV_END_FILE_REASON_EOF;
			const bool failed = reason == MPV_END_FILE_REASON_ERROR;
			if (failed) {
				UtilityFunctions::print("[gdmpv] end-file 失败 error=",
						end != nullptr ? (int)end->error : 0);
			}
			{
				std::lock_guard<std::mutex> lock(state_mutex);
				if (natural_eof || failed) {
					cached_eof = true;
					cached_playing = false;
				} else {
					// STOP / REDIRECT / QUIT 是我们主动打断（切歌、stop()、重新 loadfile），
					// 不是播放结束。若这里也置 eof，is_playing() 会永久返回 false，
					// 表现为「暂停后再点播放没有任何反应、也永远不会恢复」。
					cached_eof = false;
					cached_playing = false;
					cached_paused = false;
					cached_position = 0.0;
				}
				if (failed) {
					last_error = end->error < 0 ? String(mpv_error_string(end->error)) : String("播放结束（异常）");
				}
			}
			if (failed) {
				_dispatch_error(last_error);
			}
			_dispatch_state_changed(false);
			// STOP / REDIRECT / QUIT 都是我们主动打断，不是一次「播放结束」。
			if (natural_eof || failed) {
				_dispatch_finished();
			}
			break;
		}
		case MPV_EVENT_SHUTDOWN: {
			event_running.store(false);
			break;
		}
		default:
			break;
	}
}

void GDMPVPlayer::_dispatch_finished() {
	// 事件线程 → 主线程：必须走 call_deferred，MessageQueue 本身是线程安全的
	call_deferred("emit_signal", StringName("finished"));
}

void GDMPVPlayer::_dispatch_state_changed(bool p_playing) {
	call_deferred("emit_signal", StringName("state_changed"), p_playing);
}

void GDMPVPlayer::_dispatch_error(const String &p_message) {
	call_deferred("emit_signal", StringName("error_occurred"), p_message);
}

// ── 播放控制 ──────────────────────────────────────────────

Error GDMPVPlayer::load_file(const String &p_url, const Dictionary &p_headers) {
	if (ctx == nullptr) {
		return ERR_UNCONFIGURED;
	}

	// 注意：http-header-fields 是逗号分隔的 "Name: value" 列表
	if (p_headers.size() > 0) {
		String header_line;
		Array keys = p_headers.keys();
		for (int i = 0; i < keys.size(); i++) {
			if (i > 0) {
				header_line += ",";
			}
			header_line += String(keys[i]) + ": " + String(p_headers[keys[i]]);
		}
		CharString header_utf8 = header_line.utf8();
		mpv_set_property_string(ctx, "http-header-fields", header_utf8.get_data());
	} else {
		mpv_set_property_string(ctx, "http-header-fields", "");
	}

	{
		std::lock_guard<std::mutex> lock(state_mutex);
		cached_position = 0.0;
		cached_eof = false;
		last_error = "";
	}

	CharString url_utf8;
	{
		// mpv 不认识 res:// 和 user://，必须先落成真实文件系统路径。
		String resolved_url = p_url;
		if (resolved_url.begins_with("res://") || resolved_url.begins_with("user://")) {
			resolved_url = ProjectSettings::get_singleton()->globalize_path(resolved_url);
		}
		url_utf8 = resolved_url.utf8();
	}
	const char *cmd[] = { "loadfile", url_utf8.get_data(), nullptr };
	int rc = mpv_command(ctx, cmd);
	if (rc < 0) {
		last_error = String("loadfile 失败: ") + mpv_error_string(rc);
		UtilityFunctions::print("[gdmpv] loadfile 失败 rc=", rc,
				" url=", String(url_utf8.get_data()));
		return ERR_CANT_OPEN;
	}
	return OK;
}

void GDMPVPlayer::play() {
	if (ctx == nullptr) {
		return;
	}
	mpv_set_property_string(ctx, "pause", "no");
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		cached_paused = false;
		cached_playing = true;
	}
	_dispatch_state_changed(true);
}

void GDMPVPlayer::pause() {
	if (ctx == nullptr) {
		return;
	}
	mpv_set_property_string(ctx, "pause", "yes");
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		cached_paused = true;
		cached_playing = false;
	}
	_dispatch_state_changed(false);
}

void GDMPVPlayer::toggle_pause() {
	if (is_paused()) {
		play();
	} else {
		pause();
	}
}

void GDMPVPlayer::stop() {
	if (ctx == nullptr) {
		return;
	}
	const char *cmd[] = { "stop", nullptr };
	mpv_command(ctx, cmd);
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		// 主动 stop 之后必须把所有标志复位：否则 cached_eof / cached_paused
		// 会残留成「上一首已播完 / 处于暂停」，下一次 play() 看起来毫无效果。
		cached_playing = false;
		cached_paused = false;
		cached_eof = false;
		cached_position = 0.0;
	}
	_dispatch_state_changed(false);
}

void GDMPVPlayer::seek(double p_seconds) {
	if (ctx == nullptr) {
		return;
	}
	// absolute+exact：精确跳转，避免关键帧对齐造成的偏差
	String cmd = "seek " + String::num(p_seconds, 3) + " absolute+exact";
	CharString cmd_utf8 = cmd.utf8();
	int seek_rc = mpv_command_string(ctx, cmd_utf8.get_data());
	if (seek_rc < 0) {
		UtilityFunctions::print("[gdmpv] seek 失败 rc=", seek_rc, " cmd=", cmd);
	}

	// TODO(Phase 1)：seek 之后先标记 seeking，等 MPV_EVENT_SEEK /
	// MPV_EVENT_PLAYBACK_RESTART 再允许上层回读位置，防止进度条回弹。
}

// ── 状态查询 ──────────────────────────────────────────────

double GDMPVPlayer::get_position() const {
	std::lock_guard<std::mutex> lock(state_mutex);
	return cached_position;
}

double GDMPVPlayer::get_duration() const {
	std::lock_guard<std::mutex> lock(state_mutex);
	return cached_duration;
}

bool GDMPVPlayer::is_playing() const {
	std::lock_guard<std::mutex> lock(state_mutex);
	return cached_playing && !cached_eof;
}

bool GDMPVPlayer::is_paused() const {
	std::lock_guard<std::mutex> lock(state_mutex);
	return cached_paused;
}

bool GDMPVPlayer::is_initialized() const {
	return initialized;
}

String GDMPVPlayer::get_last_error() const {
	std::lock_guard<std::mutex> lock(state_mutex);
	return last_error;
}

void GDMPVPlayer::set_volume(double p_ratio) {
	if (ctx == nullptr) {
		return;
	}
	const double clamped = p_ratio < 0.0 ? 0.0 : (p_ratio > 1.0 ? 1.0 : p_ratio);
	// mpv 的 volume 量纲是 0~100；mpv_set_property 要非 const 的 void*，故用局部变量。
	double mpv_volume = clamped * 100.0;
	mpv_set_property(ctx, "volume", MPV_FORMAT_DOUBLE, &mpv_volume);
}

double GDMPVPlayer::get_volume() const {
	if (ctx == nullptr) {
		return 1.0;
	}
	double mpv_volume = 100.0;
	if (mpv_get_property(ctx, "volume", MPV_FORMAT_DOUBLE, &mpv_volume) < 0) {
		return 1.0;
	}
	return mpv_volume / 100.0;
}
