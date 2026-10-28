package com.ayoma

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.media3.exoplayer.drm.ExoMediaDrm
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.MediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** What the server's `/playback` endpoint returns, as sent from Dart. */
data class PlayerSource(
    val url: String,
    val streamType: String,
    val headers: Map<String, String>,
    val drmType: String,
    val licenseUrl: String,
    val licenseHeaders: Map<String, String>,
    val clearKeys: List<Pair<String, String>>,
    val maxHeight: Int,
    val muted: Boolean,
) {
    companion object {
        fun from(args: Map<*, *>): PlayerSource {
            val drm = args["drm"] as? Map<*, *> ?: emptyMap<String, Any>()
            val keys = (drm["clearKeys"] as? List<*>).orEmpty().mapNotNull { item ->
                val map = item as? Map<*, *> ?: return@mapNotNull null
                val kid = map["kid"]?.toString().orEmpty()
                val key = map["key"]?.toString().orEmpty()
                if (kid.isEmpty() || key.isEmpty()) null else kid to key
            }
            val (url, urlHeaders) = splitUrlHeaders(args["url"]?.toString().orEmpty())
            return PlayerSource(
                url = url,
                streamType = args["streamType"]?.toString() ?: "auto",
                headers = urlHeaders + stringMap(args["headers"]).mapKeys { canonicalHeader(it.key) },
                drmType = drm["type"]?.toString() ?: "none",
                licenseUrl = drm["licenseUrl"]?.toString().orEmpty(),
                licenseHeaders = stringMap(drm["licenseHeaders"]),
                clearKeys = keys,
                maxHeight = (args["maxHeight"] as? Number)?.toInt() ?: 0,
                muted = args["muted"] == true,
            )
        }

        private fun stringMap(value: Any?): Map<String, String> =
            (value as? Map<*, *>).orEmpty()
                .mapNotNull { (k, v) -> if (k == null || v == null) null else k.toString() to v.toString() }
                .toMap()

        /**
         * IPTV-style links carry headers after a pipe:
         * `http://host/live.m3u8|User-Agent=VLC/3.0&Referer=https://site/`.
         * Headers set on the channel itself take priority over these.
         */
        fun splitUrlHeaders(raw: String): Pair<String, Map<String, String>> {
            val trimmed = raw.trim()
            val pipe = trimmed.indexOf('|')
            if (pipe < 0) return trimmed to emptyMap()
            val headers = trimmed.substring(pipe + 1).split('&').mapNotNull { part ->
                val eq = part.indexOf('=')
                if (eq <= 0) return@mapNotNull null
                val name = decode(part.substring(0, eq)).trim()
                val value = decode(part.substring(eq + 1)).trim()
                if (name.isEmpty() || value.isEmpty()) null else canonicalHeader(name) to value
            }.toMap()
            return trimmed.substring(0, pipe).trim() to headers
        }

        private fun decode(value: String): String =
            runCatching { URLDecoder.decode(value.replace("+", "%2B"), "UTF-8") }.getOrDefault(value)

        fun canonicalHeader(name: String): String = when (name.trim().lowercase()) {
            "user-agent", "useragent", "user_agent" -> "User-Agent"
            "referer", "referrer" -> "Referer"
            "origin" -> "Origin"
            "cookie" -> "Cookie"
            "authorization" -> "Authorization"
            else -> name.trim()
        }
    }
}

/** Method channel `ayoma/player`; each player streams events on `ayoma/player/<id>`. */
@OptIn(UnstableApi::class)
class AyomaPlayerPlugin(
    private val context: Context,
    private val messenger: BinaryMessenger,
    private val textures: TextureRegistry,
    private val keepScreenOn: (Boolean) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val players = HashMap<Long, AyomaPlayer>()
    private val channel = MethodChannel(messenger, "ayoma/player")
    private val http: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(8, 5, TimeUnit.MINUTES))
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    val source = PlayerSource.from(call.arguments as Map<*, *>)
                    val producer = textures.createSurfaceProducer()
                    val id = producer.id()
                    val events = EventChannel(messenger, "ayoma/player/$id")
                    players[id] = AyomaPlayer(context, http, producer, events, source)
                    result.success(id)
                }
                "play" -> withPlayer(call, result) { it.play() }
                "pause" -> withPlayer(call, result) { it.pause() }
                "setMuted" -> withPlayer(call, result) { it.setMuted(call.argument<Boolean>("muted") == true) }
                "setMaxHeight" -> withPlayer(call, result) { it.setMaxHeight(call.argument<Int>("maxHeight") ?: 0) }
                "retry" -> withPlayer(call, result) { it.retry() }
                "keepScreenOn" -> {
                    keepScreenOn(call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "dispose" -> {
                    players.remove(idOf(call))?.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("PLAYER", e.message ?: e.toString(), null)
        }
    }

    private fun idOf(call: MethodCall): Long = (call.argument<Number>("id") ?: -1).toLong()

    private inline fun withPlayer(call: MethodCall, result: MethodChannel.Result, action: (AyomaPlayer) -> Unit) {
        val player = players[idOf(call)]
        if (player == null) {
            result.error("NO_PLAYER", "Player not found", null)
            return
        }
        action(player)
        result.success(null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        players.values.forEach { it.release() }
        players.clear()
    }
}

@OptIn(UnstableApi::class)
class AyomaPlayer(
    context: Context,
    private val http: OkHttpClient,
    private val producer: TextureRegistry.SurfaceProducer,
    private val events: EventChannel,
    private val source: PlayerSource,
) : Player.Listener, TextureRegistry.SurfaceProducer.Callback, EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayList<Map<String, Any?>>()
    private val player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())
    private var autoRetries = 0
    private var surfaceWidth = 0
    private var surfaceHeight = 0
    private var attachedSurface: Surface? = null
    private var released = false

    /** Resolved MIME type (or [PROGRESSIVE]); null while a probe is still running. */
    private var format: String? = null
    private var triedFallback = false

    init {
        // DefaultDataSource adds udp://, content:// and data: on top of OkHttp for http(s).
        val streamData = DefaultDataSource.Factory(context, dataSource(http, source.headers))
        val mediaSources = DefaultMediaSourceFactory(context)
            .setDataSourceFactory(streamData)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(LOAD_RETRIES))
        drmSessionManager(http)?.let { manager -> mediaSources.setDrmSessionManagerProvider { manager } }

        val renderers = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)
            .forceEnableMediaCodecAsynchronousQueueing()

        // Live TV on mobile data: start quickly, then keep a deep buffer.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(30_000, 90_000, 1_000, 2_500)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()

        // A cautious first guess avoids picking a quality the network cannot hold.
        val bandwidth = DefaultBandwidthMeter.Builder(context)
            .setInitialBitrateEstimate(1_000_000)
            .build()
        val trackSelector = DefaultTrackSelector(
            context,
            AdaptiveTrackSelection.Factory(
                8_000,
                20_000,
                20_000,
                0.7f,
            ),
        )

        // After each stall, sit further behind the live edge so it does not repeat.
        val liveSpeed = DefaultLivePlaybackSpeedControl.Builder()
            .setTargetLiveOffsetIncrementOnRebufferMs(2_000)
            .build()

        player = ExoPlayer.Builder(context, renderers)
            .setMediaSourceFactory(mediaSources)
            .setLoadControl(loadControl)
            .setBandwidthMeter(bandwidth)
            .setTrackSelector(trackSelector)
            .setLivePlaybackSpeedControl(liveSpeed)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        player.addListener(this)
        player.volume = if (source.muted) 0f else 1f
        applyMaxHeight(source.maxHeight)

        events.setStreamHandler(this)
        producer.setCallback(this)
        // Sized up front so the first frame (720p or less) needs no new surface.
        surfaceWidth = 1280
        surfaceHeight = 720
        producer.setSize(surfaceWidth, surfaceHeight)
        attachSurface()

        player.playWhenReady = true
        val known = when (source.streamType) {
            "hls" -> MimeTypes.APPLICATION_M3U8
            "dash" -> MimeTypes.APPLICATION_MPD
            "smooth" -> MimeTypes.APPLICATION_SS
            "rtsp" -> MimeTypes.APPLICATION_RTSP
            "ts", "progressive" -> PROGRESSIVE
            else -> formatFromUrl(source.url) ?: detected[source.url]
        }
        if (known != null) {
            load(known)
        } else {
            // Links such as …/live.php or …/stream?id=5 hide the format; ask the server once.
            detect(tried = null)
        }
    }

    /** Probes the link off the main thread, then loads whatever it found (never [tried] again). */
    private fun detect(tried: String?) {
        sendState()
        thread(name = "ayoma-probe") {
            val found = probe()?.takeIf { it != tried }
                ?: if (tried == MimeTypes.APPLICATION_M3U8) PROGRESSIVE else MimeTypes.APPLICATION_M3U8
            if (tried != null) detected[source.url] = found
            handler.post { if (!released) load(found) }
        }
    }

    private fun load(format: String) {
        this.format = format
        val builder = MediaItem.Builder().setUri(source.url)
        if (format != PROGRESSIVE) builder.setMimeType(format)
        player.setMediaItem(builder.build())
        player.prepare()
    }

    /**
     * Fetches the first few KB (following redirects) and decides from the final URL,
     * the Content-Type, or the bytes themselves. Shares the player's connection pool,
     * so the real request right after reuses the same connection.
     */
    private fun probe(): String? = runCatching {
        val request = Request.Builder().url(source.url).apply {
            source.headers.forEach { (name, value) -> header(name, value) }
            if (source.headers.keys.none { it.equals("User-Agent", true) }) header("User-Agent", DEFAULT_USER_AGENT)
            header("Range", "bytes=0-4095")
        }.build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@runCatching null
            formatFromUrl(response.request.url.toString())?.let { return@runCatching it }
            val type = response.header("Content-Type").orEmpty().lowercase()
            formatFromContentType(type)?.let { return@runCatching it }
            val head = ByteArray(4096)
            var read = 0
            response.body?.byteStream()?.let { input ->
                while (read < head.size) {
                    val n = input.read(head, read, head.size - read)
                    if (n <= 0) break
                    read += n
                }
            }
            formatFromBytes(head, read)
        }
    }.getOrNull()?.also { detected[source.url] = it }

    private fun dataSource(http: OkHttpClient, headers: Map<String, String>): OkHttpDataSource.Factory {
        val factory = OkHttpDataSource.Factory(http)
        val userAgent = headers.entries.firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }?.value
        factory.setUserAgent(userAgent ?: DEFAULT_USER_AGENT)
        factory.setDefaultRequestProperties(headers.filterKeys { !it.equals("User-Agent", ignoreCase = true) })
        return factory
    }

    private fun drmSessionManager(http: OkHttpClient): DrmSessionManager? {
        val (uuid, callback) = when (source.drmType) {
            "clearkey" -> C.CLEARKEY_UUID to clearKeyCallback(http)
            "widevine" -> C.WIDEVINE_UUID to licenseCallback(http)
            else -> return null
        }
        return DefaultDrmSessionManager.Builder()
            .setUuidAndExoMediaDrmProvider(uuid, mediaDrmProvider)
            .setMultiSession(false)
            .build(callback)
    }

    private fun clearKeyCallback(http: OkHttpClient): MediaDrmCallback {
        if (source.clearKeys.isEmpty()) return licenseCallback(http)
        val keys = JSONArray()
        source.clearKeys.forEach { (kid, key) ->
            keys.put(JSONObject().put("kty", "oct").put("kid", base64Url(kid)).put("k", base64Url(key)))
        }
        val license = JSONObject().put("keys", keys).put("type", "temporary")
        return LocalMediaDrmCallback(license.toString().toByteArray(Charsets.UTF_8))
    }

    /** License servers often check the same Referer/Origin as the stream. */
    private fun licenseCallback(http: OkHttpClient): MediaDrmCallback {
        val headers = source.headers + source.licenseHeaders
        val callback = HttpMediaDrmCallback(source.licenseUrl, dataSource(http, headers))
        headers.forEach { (name, value) -> callback.setKeyRequestProperty(name, value) }
        return callback
    }

    fun play() {
        if (format == null) {
            player.playWhenReady = true
            return
        }
        if (player.playbackState == Player.STATE_IDLE) player.prepare()
        player.play()
    }

    fun pause() = player.pause()

    fun setMuted(muted: Boolean) {
        player.volume = if (muted) 0f else 1f
    }

    fun setMaxHeight(maxHeight: Int) = applyMaxHeight(maxHeight)

    fun retry() {
        handler.removeCallbacksAndMessages(null)
        autoRetries = 0
        restart()
    }

    private fun restart() {
        if (released || format == null) return
        player.seekToDefaultPosition()
        player.prepare()
        player.play()
    }

    private fun applyMaxHeight(maxHeight: Int) {
        val params = player.trackSelectionParameters.buildUpon()
        if (maxHeight > 0) params.setMaxVideoSize(Int.MAX_VALUE, maxHeight) else params.clearVideoSizeConstraints()
        player.trackSelectionParameters = params.build()
    }

    fun release() {
        released = true
        handler.removeCallbacksAndMessages(null)
        events.setStreamHandler(null)
        sink = null
        player.removeListener(this)
        player.release()
        producer.setCallback(null)
        producer.release()
        attachedSurface = null
    }

    /** Only hands ExoPlayer a new surface when Flutter actually replaced it. */
    private fun attachSurface() {
        val surface = producer.surface
        if (surface === attachedSurface) return
        attachedSurface = surface
        player.setVideoSurface(surface)
    }

    // Player.Listener

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState == Player.STATE_READY) autoRetries = 0
        sendState()
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) = sendState()

    /**
     * Adaptive streams change resolution often. Resizing (and so replacing) the
     * surface each time stalls the decoder, so the surface only ever grows.
     */
    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width == 0 || videoSize.height == 0) return
        if (videoSize.width > surfaceWidth || videoSize.height > surfaceHeight) {
            surfaceWidth = maxOf(surfaceWidth, videoSize.width)
            surfaceHeight = maxOf(surfaceHeight, videoSize.height)
            producer.setSize(surfaceWidth, surfaceHeight)
            attachSurface()
        }
        val width = (videoSize.width * videoSize.pixelWidthHeightRatio).toInt()
        send(mapOf("event" to "size", "width" to width, "height" to videoSize.height))
    }

    override fun onPlayerError(error: PlaybackException) {
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            restart()
            return
        }
        // The link is not the chosen or guessed format (e.g. admin picked HLS for a TS link).
        if (error.errorCode in FORMAT_ERRORS && !triedFallback) {
            triedFallback = true
            detected.remove(source.url)
            detect(tried = format)
            return
        }
        if (error.errorCode in RECOVERABLE && autoRetries < AUTO_RETRIES) {
            autoRetries++
            sendState()
            handler.postDelayed({ restart() }, 1_500L * autoRetries)
            return
        }
        send(
            mapOf(
                "event" to "error",
                "code" to error.errorCodeName,
                "drm" to (error.errorCode in 6000..6999),
                "message" to (error.cause?.message ?: error.message ?: error.errorCodeName),
            ),
        )
    }

    private fun sendState() {
        val state = when (player.playbackState) {
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "ended"
            else -> "idle"
        }
        send(mapOf("event" to "state", "state" to state, "playing" to player.isPlaying))
    }

    // SurfaceProducer.Callback: the surface is torn down when the app is backgrounded.

    override fun onSurfaceAvailable() {
        producer.setSize(surfaceWidth, surfaceHeight)
        attachSurface()
    }

    override fun onSurfaceCleanup() {
        attachedSurface = null
        player.setVideoSurface(null)
    }

    // EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        pending.forEach { events.success(it) }
        pending.clear()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun send(event: Map<String, Any?>) {
        val target = sink
        if (target == null) pending.add(event) else target.success(event)
    }

    companion object {
        private const val LOAD_RETRIES = 6
        private const val AUTO_RETRIES = 3
        private const val DEFAULT_USER_AGENT = "AyomaMax/1.0 (Linux; Android) ExoPlayer"
        private const val PROGRESSIVE = "progressive"

        /** Formats found by probing, so reopening a channel skips the probe. */
        private val detected = ConcurrentHashMap<String, String>()

        private val progressiveExtensions = setOf(
            "mp4", "m4v", "m4a", "mkv", "webm", "mov", "3gp", "ts", "mts", "flv", "mp3", "aac", "ogg", "wav",
        )

        fun formatFromUrl(url: String): String? {
            when (Uri.parse(url).scheme?.lowercase()) {
                "rtsp" -> return MimeTypes.APPLICATION_RTSP
                "udp" -> return PROGRESSIVE
            }
            val path = url.substringBefore('#').substringBefore('?').lowercase()
            val extension = path.substringAfterLast('/').substringAfterLast('.', "")
            return when {
                extension == "m3u8" || extension == "m3u" || path.contains(".m3u8") -> MimeTypes.APPLICATION_M3U8
                extension == "mpd" || path.contains(".mpd") -> MimeTypes.APPLICATION_MPD
                extension == "ism" || extension == "isml" || path.contains(".ism/") -> MimeTypes.APPLICATION_SS
                extension in progressiveExtensions -> PROGRESSIVE
                else -> null
            }
        }

        fun formatFromContentType(type: String): String? = when {
            "mpegurl" in type -> MimeTypes.APPLICATION_M3U8
            "dash+xml" in type -> MimeTypes.APPLICATION_MPD
            "vnd.ms-sstr" in type -> MimeTypes.APPLICATION_SS
            type.startsWith("video/") || type.startsWith("audio/") -> PROGRESSIVE
            else -> null
        }

        fun formatFromBytes(bytes: ByteArray, length: Int): String {
            if (length > 0 && bytes[0] == 0x47.toByte()) return PROGRESSIVE
            val text = String(bytes, 0, length, Charsets.UTF_8).trimStart('\uFEFF', ' ', '\n', '\r', '\t')
            return when {
                text.startsWith("#EXTM3U") || text.contains("#EXT-X-") -> MimeTypes.APPLICATION_M3U8
                text.contains("<MPD") -> MimeTypes.APPLICATION_MPD
                text.contains("<SmoothStreamingMedia") -> MimeTypes.APPLICATION_SS
                else -> PROGRESSIVE
            }
        }

        private val FORMAT_ERRORS = setOf(
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
        )

        private val RECOVERABLE = setOf(
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            PlaybackException.ERROR_CODE_TIMEOUT,
            PlaybackException.ERROR_CODE_DECODING_FAILED,
            PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
        )

        /** Widevine L1 needs a secure surface, which a Flutter texture is not. */
        private val mediaDrmProvider = ExoMediaDrm.Provider { uuid ->
            val drm = FrameworkMediaDrm.newInstance(uuid)
            if (uuid == C.WIDEVINE_UUID) {
                runCatching { drm.setPropertyString("securityLevel", "L3") }
            }
            drm
        }

        private val hex = Regex("^[0-9a-fA-F]{32}$")

        /** ClearKey wants base64url without padding; the admin may enter hex. */
        fun base64Url(value: String): String {
            val trimmed = value.trim()
            val bytes = if (hex.matches(trimmed)) {
                ByteArray(16) { i -> trimmed.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
            } else {
                return trimmed.replace('+', '-').replace('/', '_').trimEnd('=')
            }
            return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        }
    }
}
