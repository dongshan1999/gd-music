package com.gdmusic.android;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.content.pm.PackageManager;
import android.util.Log;

import java.util.HashSet;
import java.util.Set;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

/** Bridges the Godot playback state to the Android foreground service. */
public final class GDMusicBackgroundAudioPlugin extends GodotPlugin {
    private static final int NOTIFICATION_PERMISSION_REQUEST_CODE = 7302;
    private static final String TAG = "GDMusicBackgroundAudio";
    private static volatile GDMusicBackgroundAudioPlugin instance;

    public GDMusicBackgroundAudioPlugin(Godot godot) {
        super(godot);
        instance = this;
        Log.i(TAG, "Godot plugin initialized");
    }

    @Override
    public String getPluginName() {
        return "GDMusicBackgroundAudio";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("media_control", String.class));
        return signals;
    }

    @UsedByGodot
    public void start(String title, String artist) {
        Log.i(TAG, "start playback service: " + title);
        Context context = getContext();
        if (context == null) {
            Log.w(TAG, "Cannot start playback service: plugin context is null");
            return;
        }

        // Start the foreground service immediately. Requesting POST_NOTIFICATIONS
        // can show a modal permission dialog and must not delay startForeground().
        Intent intent = new Intent(context, GDMusicBackgroundService.class)
                .setAction(GDMusicBackgroundService.ACTION_START)
                .putExtra(GDMusicBackgroundService.EXTRA_TITLE, title)
                .putExtra(GDMusicBackgroundService.EXTRA_ARTIST, artist);
        startServiceCompat(context, intent);
        requestNotificationPermission();
    }

    @UsedByGodot
    public void updateMetadata(String title, String artist) {
        updatePlayback(title, artist, 0, 0, true);
    }

    /** Updates the card metadata and the current playback position. */
    @UsedByGodot
    public void updatePlayback(String title, String artist, int positionSeconds, int durationSeconds, boolean playing) {
        Context context = getContext();
        if (context == null) {
            return;
        }
        Intent intent = new Intent(context, GDMusicBackgroundService.class)
                .setAction(GDMusicBackgroundService.ACTION_UPDATE)
                .putExtra(GDMusicBackgroundService.EXTRA_TITLE, title)
                .putExtra(GDMusicBackgroundService.EXTRA_ARTIST, artist)
                .putExtra(GDMusicBackgroundService.EXTRA_POSITION_SECONDS, Math.max(0, positionSeconds))
                .putExtra(GDMusicBackgroundService.EXTRA_DURATION_SECONDS, Math.max(0, durationSeconds))
                .putExtra(GDMusicBackgroundService.EXTRA_PLAYING, playing);
        startServiceCompat(context, intent);
    }

    /** 把封面（base64 编码的 JPEG）交给前台服务，用于通知栏与锁屏。 */
    @UsedByGodot
    public void updateArtwork(String artworkBase64) {
        Context context = getContext();
        if (context == null || artworkBase64 == null) {
            return;
        }
        Intent intent = new Intent(context, GDMusicBackgroundService.class)
                .setAction(GDMusicBackgroundService.ACTION_ARTWORK)
                .putExtra(GDMusicBackgroundService.EXTRA_ARTWORK, artworkBase64);
        startServiceCompat(context, intent);
    }

    /**
     * 由系统网络栈代发一条 GET（Godot 的 HTTPRequest 在部分机型上连超时都不回调）。
     * 结果通过 {@code media_control} 信号回传，格式 {@code http_result:<请求号>:<base64>}，
     * 失败时是 {@code http_error:<请求号>:<异常类名>}。
     */
    @UsedByGodot
    public void httpGet(String url, String requestId) {
        Context context = getContext();
        if (context == null || url == null || requestId == null) {
            return;
        }
        Intent intent = new Intent(context, GDMusicBackgroundService.class)
                .setAction(GDMusicBackgroundService.ACTION_HTTP_GET)
                .putExtra(GDMusicBackgroundService.EXTRA_HTTP_URL, url)
                .putExtra(GDMusicBackgroundService.EXTRA_HTTP_REQUEST_ID, requestId);
        startServiceCompat(context, intent);
    }

    @UsedByGodot
    public void pause() {
        sendSimpleAction(GDMusicBackgroundService.ACTION_PAUSE);
    }

    @UsedByGodot
    public void resume() {
        sendSimpleAction(GDMusicBackgroundService.ACTION_RESUME);
    }

    @UsedByGodot
    public void stop() {
        Context context = getContext();
        if (context != null) {
            context.stopService(new Intent(context, GDMusicBackgroundService.class));
        }
    }

    /** Requests the Android 13+ notification permission before the first playback. */
    @UsedByGodot
    public void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return;
        }
        Activity activity = getActivity();
        if (activity == null || activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }
        activity.requestPermissions(
                new String[]{android.Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST_CODE
        );
    }

    /** True while a Godot instance with this plugin loaded is alive in this process. */
    public static boolean isAlive() {
        return instance != null;
    }

    /** Delivers notification and headset commands to the active Godot singleton. */
    public static void dispatchMediaControl(String action) {
        GDMusicBackgroundAudioPlugin plugin = instance;
        if (plugin != null && action != null) {
            plugin.emitSignal("media_control", action);
        }
    }

    private void sendSimpleAction(String action) {
        Context context = getContext();
        if (context != null) {
            startServiceCompat(context, new Intent(context, GDMusicBackgroundService.class).setAction(action));
        }
    }

    private static void startServiceCompat(Context context, Intent intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
        } catch (IllegalStateException | SecurityException error) {
            // Android can reject a background service start after the app is restricted.
            // Keep playback alive in Godot and leave the failure visible in logcat.
            Log.e(TAG, "Unable to start background playback service: " + intent.getAction(), error);
        }
    }

    @Override
    public void onMainDestroy() {
        if (instance == this) {
            instance = null;
        }
        super.onMainDestroy();
    }
}
