#pragma once

// gdmpv —— 把 libmpv 作为 Godot 的音频播放引擎外挂进来。
// 设计目标：native 侧掌握全部播放状态，GDScript 侧只读，避免双状态机。

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <mpv/client.h>

#include <atomic>
#include <mutex>

namespace godot {

class GDMPVPlayer : public Node {
	GDCLASS(GDMPVPlayer, Node)

private:
	mpv_handle *ctx = nullptr;
	void *event_thread = nullptr; // pthread_t / std::thread 由实现文件管理
	std::atomic<bool> event_running{false};
	mutable std::mutex state_mutex;

	// 由事件线程写入、主线程读取的缓存值
	double cached_position = -1.0;
	double cached_duration = -1.0;
	bool cached_paused = true;
	bool cached_playing = false;
	bool cached_eof = false;
	String last_error;

	bool initialized = false;
	bool shutting_down = false;

	void _event_loop();
	void _handle_mpv_event(mpv_event *ev);
	void _dispatch_finished();
	void _dispatch_state_changed(bool p_playing);
	void _dispatch_error(const String &p_message);

protected:
	static void _bind_methods();

public:
	GDMPVPlayer();
	~GDMPVPlayer() override;

	// 生命周期
	Error initialize();
	void shutdown();

	// 播放控制
	Error load_file(const String &p_url, const Dictionary &p_headers = Dictionary());
	void play();
	void pause();
	void toggle_pause();
	void stop();
	void seek(double p_seconds);

	// 状态查询（非阻塞，读缓存）
	double get_position() const;
	double get_duration() const;
	bool is_playing() const;
	bool is_paused() const;
	bool is_initialized() const;
	String get_last_error() const;

	// 音量 0.0 ~ 1.0
	void set_volume(double p_ratio);
	double get_volume() const;
};

} // namespace godot
