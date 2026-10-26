package com.gdmusic.android;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

/** Owns Android's background playback lifetime while Godot remains the decoder. */
public final class GDMusicBackgroundService extends Service {
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
    public static final String MEDIA_PLAY = "play";
    public static final String MEDIA_PAUSE = "pause";
    public static final String MEDIA_TOGGLE = "toggle";
    public static final String MEDIA_NEXT = "next";
    public static final String MEDIA_PREVIOUS = "previous";
    public static final String MEDIA_STOP = "stop";
    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_ARTIST = "artist";
    public static final String EXTRA_POSITION_SECONDS = "position_seconds";
    public static final String EXTRA_DURATION_SECONDS = "duration_seconds";
    public static final String EXTRA_PLAYING = "playing";

    private static final int NOTIFICATION_ID = 7301;
    // Versioned so devices that already created the old LOW-importance
    // channel receive the visible media channel after an app update.
    private static final String CHANNEL_ID = "gdmusic_playback_v2";
    private static final String WAKE_LOCK_TAG = "gd-music:BackgroundPlayback";

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
        Log.i(TAG, "onStartCommand action=" + action + " title=" + title);
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
        Log.i(TAG, "foreground media notification posted id=" + NOTIFICATION_ID);
        updateMediaSession();
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
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
                dispatchMediaIntent(ACTION_MEDIA_NEXT);
            }

            @Override
            public void onSkipToPrevious() {
                dispatchMediaIntent(ACTION_MEDIA_PREVIOUS);
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

    private Notification.Action createAction(int icon, String label, String action) {
        int pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingIntentFlags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent pendingIntent = PendingIntent.getService(
                this,
                action.hashCode(),
                new Intent(this, GDMusicBackgroundService.class).setAction(action),
                pendingIntentFlags
        );
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
                | PlaybackState.ACTION_STOP;
        int state = paused ? PlaybackState.STATE_PAUSED : PlaybackState.STATE_PLAYING;
        float playbackSpeed = paused ? 0.0f : 1.0f;
        mediaSession.setMetadata(new MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "gd-music")
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMillis)
                .build());
        mediaSession.setPlaybackState(new PlaybackState.Builder()
                .setActions(actions)
                .setState(state, positionMillis, playbackSpeed)
                .build());
        mediaSession.setActive(true);
        updateNotification();
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
