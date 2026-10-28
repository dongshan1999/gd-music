package com.gdmusic.android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Base64;
import android.util.Log;

/** Owns Android's background playback lifetime while Godot remains the decoder. */
public final class GDMusicBackgroundService extends Service {
    private static final long SKIP_THROTTLE_MS = 400L;
    private long lastSkipToNextAt = 0L;
    private static final String TAG = "GDMusicBackgroundService";
    public static final String ACTION_START = "com.gdmusic.android.action.START";
    public static final String ACTION_UPDATE = "com.gdmusic.android.action.UPDATE";
    public static final String ACTION_PAUSE = "com.gdmusic.android.action.PAUSE";
    public static final String ACTION_RESUME = "com.gdmusic.android.action.RESUME";
    public static final String ACTION_MEDIA_PLAY = "com.gdmusic.android.action.MEDIA_PLAY";
    public static final String ACTION_MEDIA_PAUSE = "com.gdmusic.android.action.MEDIA_PAUSE";
    public static final String ACTION_MEDIA_TOGGLE = "com.gdmusic.android.action.MEDIA_TOGGLE";
    public static final String ACTION_MEDIA_NEXT = "com.gdmusic.android.action.MEDIA_NEXT";
    public static final String ACTION_MEDIA_PREVIOUS = "com.gdmusic.android.action.MEDIA_PREVIOUS";
    public static final String ACTION_MEDIA_STOP = "com.gdmusic.android.action.MEDIA_STOP";
    public static final String ACTION_ARTWORK = "com.gdmusic.android.action.ARTWORK";
    public static final String MEDIA_PLAY = "play";
    public static final String MEDIA_PAUSE = "pause";
    public static final String MEDIA_TOGGLE = "toggle";
    public static final String MEDIA_NEXT = "next";
    public static final String MEDIA_PREVIOUS = "previous";
    public static final String MEDIA_STOP = "stop";
    /** 锁屏/通知栏拖进度时回传的动作前缀，格式 `seek_to:<毫秒>`。 */
    public static final String MEDIA_SEEK_PREFIX = "seek_to:";
    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_ARTIST = "artist";
    public static final String EXTRA_POSITION_SECONDS = "position_seconds";
    public static final String EXTRA_DURATION_SECONDS = "duration_seconds";
    public static final String EXTRA_PLAYING = "playing";
    public static final String EXTRA_ARTWORK = "artwork";
    /** 由 Godot 侧发起的 HTTPS GET：Godot 自带的 HTTPRequest 在部分机型上
     *  连 request_completed 超时都不触发，登录等关键请求改走系统网络栈。 */
    public static final String ACTION_HTTP_GET = "com.gdmusic.android.action.HTTP_GET";
    public static final String EXTRA_HTTP_URL = "http_url";
    public static final String EXTRA_HTTP_REQUEST_ID = "http_request_id";
    private static final int HTTP_CONNECT_TIMEOUT_MS = 8000;
    private static final int HTTP_READ_TIMEOUT_MS = 8000;

    private static final int NOTIFICATION_ID = 7301;
    // Versioned so devices that already created the old LOW-importance
    // channel receive the visible media channel after an app update.
    private static final String CHANNEL_ID = "gdmusic_playback_v2";
    private static final String WAKE_LOCK_TAG = "gd-music:BackgroundPlayback";
    /** 播放中定期刷新 PlaybackState 的时刻，避免系统外推漂移后进度条跳动。 */
    private static final long PLAYBACK_STATE_REFRESH_MS = 1000L;

    private PowerManager.WakeLock wakeLock;
    private AudioManager audioManager;
    private AudioFocusRequest audioFocusRequest;
    private AudioManager.OnAudioFocusChangeListener audioFocusListener;
    private MediaSession mediaSession;
    private String title = "gd-music";
    private String artist = "正在播放";
    private long positionMillis;
    private long durationMillis;
    private boolean paused;
    private Bitmap artworkBitmap;
    /** 播放位置基准：以「位置 + 基准时刻」表达，供系统按 1x 速度自行外推。 */
    private long positionBaseMillis;
    private long positionBaseElapsedRealtime;
    private final Handler progressHandler = new Handler(Looper.getMainLooper());
    private final Runnable progressTicker = new Runnable() {
        @Override
        public void run() {
            if (paused || mediaSession == null) {
                return;
            }
            // 每秒回调一次 Godot：App 在后台时引擎主循环基本不推进，mpv 播完发出的
            // finished 走 call_deferred，会一直卡在消息队列里 —— 表现为「锁屏/后台播完
            // 不自动切下一首」。这里复用 media_control 通道把「该巡检了」送进 GDScript。
            GDMusicBackgroundAudioPlugin.dispatchMediaControl("tick");
            pushPlaybackState();
            progressHandler.postDelayed(this, PLAYBACK_STATE_REFRESH_MS);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        initializeWakeLock();
        initializeAudioFocus();
        initializeMediaSession();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        // 网络上代发：与播放状态无关，投递后台线程后继续走下面的 startForeground
        //（服务可能正是被这次请求拉起，5 秒时限不能跳）。
        if (ACTION_HTTP_GET.equals(action) && intent != null) {
            String httpUrl = intent.getStringExtra(EXTRA_HTTP_URL);
            String httpRequestId = intent.getStringExtra(EXTRA_HTTP_REQUEST_ID);
            if (httpUrl != null && httpRequestId != null) {
                fetchHttpInBackground(httpUrl, httpRequestId);
            }
        }
        if (intent != null) {
            String nextTitle = intent.getStringExtra(EXTRA_TITLE);
            String nextArtist = intent.getStringExtra(EXTRA_ARTIST);
            if (nextTitle != null && !nextTitle.isEmpty()) {
                title = nextTitle;
            }
            if (nextArtist != null && !nextArtist.isEmpty()) {
                artist = nextArtist;
            }
            if (intent.hasExtra(EXTRA_POSITION_SECONDS)) {
                positionMillis = Math.max(0L, intent.getIntExtra(EXTRA_POSITION_SECONDS, 0) * 1000L);
            }
            if (intent.hasExtra(EXTRA_DURATION_SECONDS)) {
                durationMillis = Math.max(0L, intent.getIntExtra(EXTRA_DURATION_SECONDS, 0) * 1000L);
            }
            if (intent.hasExtra(EXTRA_PLAYING)) {
                paused = !intent.getBooleanExtra(EXTRA_PLAYING, !paused);
            }
            if (action != null && action.equals(ACTION_ARTWORK)) {
                String encodedArtwork = intent.getStringExtra(EXTRA_ARTWORK);
                artworkBitmap = decodeArtwork(encodedArtwork);
            }
        }

        if (ACTION_MEDIA_PLAY.equals(action)) {
            paused = false;
            requestAudioFocus();
            acquireWakeLock();
            GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_PLAY);
        } else if (ACTION_MEDIA_PAUSE.equals(action)) {
            paused = true;
            releaseAudioFocus();
            releaseWakeLock();
            GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_PAUSE);
        } else if (ACTION_MEDIA_TOGGLE.equals(action)) {
            paused = !paused;
            if (paused) {
                releaseAudioFocus();
                releaseWakeLock();
            } else {
                requestAudioFocus();
                acquireWakeLock();
            }
            GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_TOGGLE);
        } else if (ACTION_MEDIA_NEXT.equals(action)) {
            GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_NEXT);
        } else if (ACTION_MEDIA_PREVIOUS.equals(action)) {
            GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_PREVIOUS);
        } else if (ACTION_MEDIA_STOP.equals(action)) {
            GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_STOP);
            stopSelf();
            return START_NOT_STICKY;
        } else if (ACTION_PAUSE.equals(action)) {
            paused = true;
            releaseAudioFocus();
            releaseWakeLock();
        } else if (ACTION_RESUME.equals(action)) {
            paused = false;
            requestAudioFocus();
            acquireWakeLock();
        } else if (ACTION_START.equals(action) || action == null) {
            paused = false;
            requestAudioFocus();
            acquireWakeLock();
        }

        // Android requires a foreground service to call startForeground promptly.
        // Always publish the notification before touching MediaSession state.
        Notification notification = buildNotification();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            );
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
        updateMediaSession();
        return START_STICKY;
    }

    /** 在后台线程发一条 GET，把结果以 `http_result:<id>:<base64>` 回传给 Godot。 */
    private void fetchHttpInBackground(final String url, final String requestId) {
        Thread worker = new Thread(new Runnable() {
            @Override
            public void run() {
                String resultAction;
                try {
                    java.net.HttpURLConnection connection =
                            (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
                    connection.setRequestMethod("GET");
                    connection.setConnectTimeout(HTTP_CONNECT_TIMEOUT_MS);
                    connection.setReadTimeout(HTTP_READ_TIMEOUT_MS);
                    connection.setRequestProperty("User-Agent",
                            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36");
                    connection.setRequestProperty("Referer", "https://www.bilibili.com/");
                    int status = connection.getResponseCode();
                    java.io.InputStream stream = (status >= 200 && status < 300)
                            ? connection.getInputStream()
                            : connection.getErrorStream();
                    // 必须按字节读：封面是 JPEG/PNG，按行读文本会把二进制内容拆坏。
                    java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream();
                    if (stream != null) {
                        byte[] chunk = new byte[8192];
                        int read;
                        while ((read = stream.read(chunk)) != -1) {
                            buffer.write(chunk, 0, read);
                        }
                        stream.close();
                    }
                    connection.disconnect();
                    String encoded = Base64.encodeToString(buffer.toByteArray(), Base64.NO_WRAP);
                    resultAction = "http_result:" + requestId + ":" + encoded;
                } catch (Exception error) {
                    resultAction = "http_error:" + requestId + ":" + error.getClass().getSimpleName();
                }
                final String finalAction = resultAction;
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        GDMusicBackgroundAudioPlugin.dispatchMediaControl(finalAction);
                    }
                });
            }
        }, "gdmusic-http");
        worker.start();
    }

    @Override
    public void onDestroy() {
        progressHandler.removeCallbacks(progressTicker);
        releaseAudioFocus();
        releaseWakeLock();
        if (mediaSession != null) {
            mediaSession.setActive(false);
            mediaSession.release();
            mediaSession = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void initializeWakeLock() {
        PowerManager powerManager = (PowerManager) getSystemService(POWER_SERVICE);
        if (powerManager == null) {
            return;
        }
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG);
        wakeLock.setReferenceCounted(false);
    }

    private void initializeAudioFocus() {
        audioManager = (AudioManager) getSystemService(AUDIO_SERVICE);
        audioFocusListener = new AudioManager.OnAudioFocusChangeListener() {
            @Override
            public void onAudioFocusChange(int focusChange) {
                if (focusChange == AudioManager.AUDIOFOCUS_LOSS
                        || focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                    if (!paused) {
                        paused = true;
                        releaseWakeLock();
                        updateNotification();
                        GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_PAUSE);
                    }
                } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN && !paused) {
                    acquireWakeLock();
                    updateNotification();
                }
            }
        };
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioAttributes attributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
            audioFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attributes)
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener(audioFocusListener)
                    .build();
        }
    }

    private void initializeMediaSession() {
        mediaSession = new MediaSession(this, "gd-music");
        // Declare a local music session so Android/MIUI can promote it to the
        // system media player card instead of treating it as a generic app
        // notification.
        mediaSession.setPlaybackToLocal(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build());
        mediaSession.setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS
                        | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
        );
        mediaSession.setCallback(new MediaSession.Callback() {
            @Override
            public void onPlay() {
                dispatchMediaIntent(ACTION_MEDIA_PLAY);
            }

            @Override
            public void onPause() {
                dispatchMediaIntent(ACTION_MEDIA_PAUSE);
            }

            @Override
            public void onSkipToNext() {
                // 蓝牙 AVRCP 有时会连续下发多次「下一首」（元数据刷新后重同步），
                // 不加节流会把队列一口气跳过好几首。
                long now = SystemClock.elapsedRealtime();
                if (now - lastSkipToNextAt < SKIP_THROTTLE_MS) {
                    return;
                }
                lastSkipToNextAt = now;
                dispatchMediaIntent(ACTION_MEDIA_NEXT);
            }

            @Override
            public void onSkipToPrevious() {
                dispatchMediaIntent(ACTION_MEDIA_PREVIOUS);
            }

            @Override
            public void onSeekTo(long position) {
                GDMusicBackgroundAudioPlugin.dispatchMediaControl(MEDIA_SEEK_PREFIX + Math.max(0L, position));
            }

            @Override
            public void onStop() {
                dispatchMediaIntent(ACTION_MEDIA_STOP);
            }
        });
    }

    private void dispatchMediaIntent(String action) {
        onStartCommand(new Intent(this, GDMusicBackgroundService.class).setAction(action), 0, 0);
    }

    private boolean requestAudioFocus() {
        if (audioManager == null) {
            return false;
        }
        int result;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
            result = audioManager.requestAudioFocus(audioFocusRequest);
        } else {
            result = audioManager.requestAudioFocus(
                    audioFocusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN
            );
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
    }

    private void releaseAudioFocus() {
        if (audioManager == null) {
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
            audioManager.abandonAudioFocusRequest(audioFocusRequest);
        } else if (audioFocusListener != null) {
            audioManager.abandonAudioFocus(audioFocusListener);
        }
    }

    private void acquireWakeLock() {
        if (wakeLock != null && !wakeLock.isHeld()) {
            wakeLock.acquire();
        }
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
    }

    private Notification buildNotification() {
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent contentIntent = null;
        if (launchIntent != null) {
            int pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                pendingIntentFlags |= PendingIntent.FLAG_IMMUTABLE;
            }
            contentIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags);
            if (mediaSession != null) {
                mediaSession.setSessionActivity(contentIntent);
            }
        }

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        }
        builder.setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(title)
                .setContentText(artist)
                .setSubText(paused ? "已暂停" : "正在播放")
                .setShowWhen(false)
                .setOngoing(!paused)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_TRANSPORT)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .addAction(createAction(
                        android.R.drawable.ic_media_previous,
                        "上一首",
                        ACTION_MEDIA_PREVIOUS
                ))
                .addAction(createAction(
                        paused ? android.R.drawable.ic_media_play : android.R.drawable.ic_media_pause,
                        paused ? "播放" : "暂停",
                        paused ? ACTION_MEDIA_PLAY : ACTION_MEDIA_PAUSE
                ))
                .addAction(createAction(
                        android.R.drawable.ic_media_next,
                        "下一首",
                        ACTION_MEDIA_NEXT
                ));
        if (artworkBitmap != null) {
            builder.setLargeIcon(artworkBitmap);
        }
        if (contentIntent != null) {
            builder.setContentIntent(contentIntent);
        }
        if (mediaSession != null) {
            builder.setStyle(new Notification.MediaStyle()
                    .setMediaSession(mediaSession.getSessionToken())
                    .setShowActionsInCompactView(0, 1, 2));
        }
        return builder.build();
    }

    /** 把 Godot 传来的 base64 JPEG 解成 Bitmap；任何异常都退化成「无封面」。 */
    private static Bitmap decodeArtwork(String encoded) {
        if (encoded == null || encoded.isEmpty()) {
            return null;
        }
        try {
            byte[] bytes = android.util.Base64.decode(encoded, android.util.Base64.DEFAULT);
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        } catch (IllegalArgumentException error) {
            Log.w(TAG, "Unable to decode artwork payload", error);
            return null;
        }
    }

    private Notification.Action createAction(int icon, String label, String action) {
        int pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingIntentFlags |= PendingIntent.FLAG_IMMUTABLE;
        }
        // ⚠ 必须用 getForegroundService：应用退到后台后，系统禁止后台进程
        // startService()（即使服务已在运行）。用 getService 时点击通知栏按钮
        // 会被静默丢弃，表现为「App 在后台时媒体通知栏/灵动岛点了没反应」。
        // getForegroundService 走 startForegroundService()，后台允许，且
        // onStartCommand 里本来就会补 startForeground()，满足 5 秒约束。
        Intent actionIntent = new Intent(this, GDMusicBackgroundService.class).setAction(action);
        PendingIntent pendingIntent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pendingIntent = PendingIntent.getForegroundService(this, action.hashCode(), actionIntent, pendingIntentFlags);
        } else {
            pendingIntent = PendingIntent.getService(this, action.hashCode(), actionIntent, pendingIntentFlags);
        }
        return new Notification.Action.Builder(icon, label, pendingIntent).build();
    }

    private void updateMediaSession() {
        if (mediaSession == null) {
            return;
        }
        long actions = PlaybackState.ACTION_PLAY
                | PlaybackState.ACTION_PAUSE
                | PlaybackState.ACTION_PLAY_PAUSE
                | PlaybackState.ACTION_SKIP_TO_NEXT
                | PlaybackState.ACTION_SKIP_TO_PREVIOUS
                | PlaybackState.ACTION_SEEK_TO
                | PlaybackState.ACTION_STOP;
        int state = paused ? PlaybackState.STATE_PAUSED : PlaybackState.STATE_PLAYING;
        float playbackSpeed = paused ? 0.0f : 1.0f;
        MediaMetadata.Builder metadata = new MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "gd-music")
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMillis);
        if (artworkBitmap != null) {
            metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, artworkBitmap);
            metadata.putBitmap(MediaMetadata.METADATA_KEY_ART, artworkBitmap);
        }
        mediaSession.setMetadata(metadata.build());
        mediaSession.setActive(true);
        positionBaseMillis = Math.max(0L, positionMillis);
        positionBaseElapsedRealtime = SystemClock.elapsedRealtime();
        pushPlaybackState();
        scheduleProgressTicker();
        updateNotification();
    }

    /**
     * 只下发 PlaybackState（不重建通知）。
     *
     * 位置以「基准位置 + 已过时间」计算，并按 1x 速度交给系统外推；
     * 小米 HyperOS 的媒体卡片/灵动岛进度条依赖这段持续更新的状态，
     * 只下发一次会在几秒后变成一条不动的进度。
     */
    private void pushPlaybackState() {
        if (mediaSession == null) {
            return;
        }
        long actions = PlaybackState.ACTION_PLAY
                | PlaybackState.ACTION_PAUSE
                | PlaybackState.ACTION_PLAY_PAUSE
                | PlaybackState.ACTION_SKIP_TO_NEXT
                | PlaybackState.ACTION_SKIP_TO_PREVIOUS
                | PlaybackState.ACTION_SEEK_TO
                | PlaybackState.ACTION_STOP;
        int state = paused ? PlaybackState.STATE_PAUSED : PlaybackState.STATE_PLAYING;
        float playbackSpeed = paused ? 0.0f : 1.0f;
        long elapsed = SystemClock.elapsedRealtime() - positionBaseElapsedRealtime;
        long current = paused ? positionBaseMillis : positionBaseMillis + Math.max(0L, elapsed);
        if (durationMillis > 0 && current > durationMillis) {
            current = durationMillis;
        }
        mediaSession.setPlaybackState(new PlaybackState.Builder()
                .setActions(actions)
                .setState(state, current, playbackSpeed, SystemClock.elapsedRealtime())
                .build());
    }

    /** 播放中每秒刷新一次状态；暂停/停止后停掉，避免无意义唤醒。 */
    private void scheduleProgressTicker() {
        progressHandler.removeCallbacks(progressTicker);
        if (!paused) {
            progressHandler.postDelayed(progressTicker, PLAYBACK_STATE_REFRESH_MS);
        }
    }

    private void updateNotification() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) {
            try {
                manager.notify(NOTIFICATION_ID, buildNotification());
            } catch (SecurityException error) {
                Log.e(TAG, "Notification permission denied; media card cannot be shown", error);
            }
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "gd-music 播放",
                // IMPORTANCE_DEFAULT keeps the foreground media notification
                // visible in Xiaomi's notification shade. MediaStyle still
                // prevents repeated sound/vibration through setOnlyAlertOnce.
                NotificationManager.IMPORTANCE_DEFAULT
        );
        channel.setDescription("后台播放状态");
        channel.setShowBadge(false);
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        manager.createNotificationChannel(channel);
    }
}
