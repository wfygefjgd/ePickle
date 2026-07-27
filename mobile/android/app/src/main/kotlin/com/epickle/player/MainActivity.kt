package com.epickle.player

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.ProxyInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelProxy = "epickle/system_proxy"
    private val channelBrowser = "epickle/browser_http"
    private val channelPrivacy = "privacy_browser/engine"
    private val channelStripchat = "epickle/stripchat_live_control"

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val activeTasks = mutableMapOf<String, HttpURLConnection>()
    private var stripchatView: StripchatLiveView? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppContextHolder.ctx = this
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, channelProxy).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemProxy" -> result.success(readSystemProxy())
                "applyJvmHttpProxy" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        val host = call.argument<String>("host")?.trim().orEmpty()
                        val port = call.argument<Int>("port") ?: 0
                        if (host.isNotEmpty() && port in 1..65535) {
                            System.setProperty("http.proxyHost", host)
                            System.setProperty("http.proxyPort", port.toString())
                            System.setProperty("https.proxyHost", host)
                            System.setProperty("https.proxyPort", port.toString())
                            System.clearProperty("http.nonProxyHosts")
                            System.clearProperty("https.nonProxyHosts")
                        }
                    } else {
                        System.clearProperty("http.proxyHost")
                        System.clearProperty("http.proxyPort")
                        System.clearProperty("https.proxyHost")
                        System.clearProperty("https.proxyPort")
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, channelBrowser).setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            val rawUrl = args?.get("url") as? String
            if (rawUrl.isNullOrBlank()) {
                result.error("bad_args", "url required", null)
                return@setMethodCallHandler
            }
            val headers = (args["headers"] as? Map<*, *>)?.entries?.associate {
                it.key.toString() to it.value.toString()
            } ?: emptyMap()
            val timeoutMs = (args["timeoutMs"] as? Int) ?: 10000
            when (call.method) {
                "get" -> executor.execute {
                    try {
                        val resp = httpGet(rawUrl, headers, timeoutMs)
                        mainHandler.post { result.success(resp) }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("http_failed", e.message, null)
                        }
                    }
                }
                "renderGet" -> executor.execute {
                    try {
                        val resp = httpRender(rawUrl, headers, timeoutMs)
                        mainHandler.post { result.success(resp) }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("render_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, channelStripchat).setMethodCallHandler { call, result ->
            when (call.method) {
                "setMuted" -> {
                    val muted = call.arguments as? Boolean ?: true
                    stripchatView?.setMuted(muted)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, channelPrivacy).setMethodCallHandler { call, result ->
            when (call.method) {
                "nuclearWipe" -> {
                    wipeEverything()
                    result.success(null)
                }
                "exitApp" -> {
                    result.success(null)
                    mainHandler.postDelayed({ finishAffinity() }, 200)
                }
                else -> result.notImplemented()
            }
        }

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "epickle/stripchat_live",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val params = (args as? Map<*, *>)
                    val url = params?.get("url") as? String ?: "https://stripchat.com/"
                    val muted = params?.get("muted") as? Boolean ?: true
                    val stripchatMode = params?.get("stripchatMode") as? Boolean ?: true
                    val view = StripchatLiveView(context, url, muted, stripchatMode)
                    stripchatView = view
                    return view
                }
            }
        )
    }

    // ---------- System Proxy ----------

    private fun emptyProxy(): Map<String, Any?> = mapOf(
        "host" to null, "port" to null, "type" to null, "source" to "none"
    )

    @SuppressLint("NewApi")
    private fun readSystemProxy(): Map<String, Any?> {
        val hostProp = System.getProperty("http.proxyHost")
            ?: System.getProperty("https.proxyHost")
        val portProp = System.getProperty("http.proxyPort")
            ?: System.getProperty("https.proxyPort")
        if (!hostProp.isNullOrBlank() && !portProp.isNullOrBlank()) {
            val port = portProp.toIntOrNull()
            if (port != null && port in 1..65535) {
                return mapOf(
                    "host" to hostProp, "port" to port,
                    "type" to "http", "source" to "system_property"
                )
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                val proxy: ProxyInfo? = cm.defaultProxy
                if (proxy != null) {
                    val h = proxy.host
                    val p = proxy.port
                    if (!h.isNullOrBlank() && p in 1..65535) {
                        return mapOf(
                            "host" to h, "port" to p,
                            "type" to "http", "source" to "connectivity"
                        )
                    }
                }
            } catch (_: Exception) {}
        }
        try {
            val list = java.net.ProxySelector.getDefault()
                ?.select(java.net.URI("https://www.google.com"))
            if (list != null) {
                for (px in list) {
                    if (px.type() == java.net.Proxy.Type.HTTP ||
                        px.type() == java.net.Proxy.Type.SOCKS
                    ) {
                        val addr = px.address() as? java.net.InetSocketAddress ?: continue
                        val h = addr.hostString ?: continue
                        val p = addr.port
                        if (p in 1..65535) {
                            val t =
                                if (px.type() == java.net.Proxy.Type.SOCKS) "socks5" else "http"
                            return mapOf(
                                "host" to h, "port" to p,
                                "type" to t, "source" to "proxy_selector"
                            )
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return emptyProxy()
    }

    // ---------- HTTP GET ----------

    private fun httpGet(
        rawUrl: String, headers: Map<String, String>, timeoutMs: Int
    ): Map<String, Any?> {
        val id = UUID.randomUUID().toString()
        var conn: HttpURLConnection? = null
        try {
            val url = URL(rawUrl)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                instanceFollowRedirects = true
                for ((k, v) in headers) setRequestProperty(k, v)
            }
            activeTasks[id] = conn
            conn.connect()
            val code = conn.responseCode
            val body = try {
                conn.inputStream.bufferedReader().use { it.readText() }
            } catch (_: Exception) {
                conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
            }
            val cookies = mutableMapOf<String, String>()
            val cookieHeader = conn.getHeaderField("Set-Cookie")
            if (!cookieHeader.isNullOrBlank()) {
                cookieHeader.split(";").forEach { part ->
                    val idx = part.indexOf('=')
                    if (idx > 0) {
                        val k = part.substring(0, idx).trim()
                        val v = part.substring(idx + 1).trim()
                        if (k.isNotEmpty()) cookies[k] = v
                    }
                }
            }
            return mapOf(
                "statusCode" to code,
                "body" to body,
                "finalUrl" to conn.url.toString(),
                "cookies" to cookies
            )
        } finally {
            activeTasks.remove(id)
            conn?.disconnect()
        }
    }

    // ---------- Browser Render (WebView in background) ----------

    private fun httpRender(
        rawUrl: String, headers: Map<String, String>, timeoutMs: Int
    ): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val lock = Object()
        var done = false
        val handler = Handler(mainLooper)

        handler.post {
            val webView = WebView(this@MainActivity).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mediaPlaybackRequiresUserGesture = false
                settings.userAgentString = headers["user-agent"]
                    ?: "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36"
            }
            val timeoutRunnable = Runnable {
                synchronized(lock) {
                    if (done) return@Runnable
                    done = true
                }
                result["error"] = "browser_render_timeout"
                webView.stopLoading()
                webView.destroy()
            }
            handler.postDelayed(timeoutRunnable, timeoutMs.toLong())
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(v: WebView?, url: String?) {
                    synchronized(lock) {
                        if (done) return
                    }
                    handler.postDelayed({
                        synchronized(lock) {
                            if (done) return
                        }
                        webView.evaluateJavascript(
                            """(function(){var resources=new Set();try{performance.getEntriesByType('resource').forEach(function(e){resources.add(e.name)})}catch(e){}document.querySelectorAll('video,source,iframe').forEach(function(n){if(n.src)resources.add(n.src);if(n.currentSrc)resources.add(n.currentSrc)});return JSON.stringify({html:document.documentElement.outerHTML,href:location.href,resources:Array.from(resources).slice(0,400)})})()"""
                        ) { value ->
                            synchronized(lock) {
                                if (done) return@synchronized
                                done = true
                            }
                            handler.removeCallbacks(timeoutRunnable)
                            val raw = value?.trim()?.trim('"')
                                ?.replace("\\n", "\n")
                                ?.replace("\\\"", "\"")
                                ?.replace("\\/", "/")
                                ?: "{}"
                            var html = ""
                            var href = rawUrl
                            try {
                                val htmlMatch = Regex("\"html\":\"((?:[^\"\\\\]|\\\\.)*)\"", RegexOption.DOT_MATCHES_ALL)
                                    .find(raw ?: "")
                                if (htmlMatch != null) {
                                    html = htmlMatch.groupValues[1]
                                        .replace("\\\"", "\"")
                                        .replace("\\n", "\n")
                                        .replace("\\t", "\t")
                                        .replace("\\/", "/")
                                        .replace("\\\\", "\\")
                                }
                                val hrefMatch = Regex("\"href\":\"([^\"]+)\"").find(raw ?: "")
                                if (hrefMatch != null) href = hrefMatch.groupValues[1]
                            } catch (_: Exception) {}
                            val cm = CookieManager.getInstance()
                            val cookieStr = cm.getCookie(href)
                            val cookies = mutableMapOf<String, String>()
                            cookieStr?.split(";")?.forEach { part ->
                                val idx = part.indexOf('=')
                                if (idx > 0) cookies[part.substring(0, idx).trim()] = part.substring(idx + 1).trim()
                            }
                            val resources = Regex("\"resources\":\\[([^\\]]*)\\]")
                                .find(raw ?: "")?.groupValues?.get(1)
                                ?.split(",")?.mapNotNull { it.trim().trim('"').ifEmpty { null } } ?: emptyList()
                            val augmented = if (resources.isNotEmpty()) {
                                html + "\n<!-- WebView resource URLs -->\n" + resources.joinToString("") { "<source src=\"$it\">" }
                            } else html
                            result["statusCode"] = 200
                            result["body"] = augmented
                            result["finalUrl"] = href
                            result["cookies"] = cookies
                            webView.stopLoading()
                            webView.destroy()
                            synchronized(lock) { lock.notifyAll() }
                        }
                    }, 800)
                }

                override fun onReceivedError(
                    v: WebView?, request: WebResourceRequest?,
                    error: android.webkit.WebResourceError?
                ) {
                    if (request?.isForMainFrame != true) return
                    synchronized(lock) {
                        if (done) return
                        done = true
                    }
                    handler.removeCallbacks(timeoutRunnable)
                    result["error"] = "browser_render_failed:" + (error?.description?.toString() ?: "unknown")
                    webView.stopLoading()
                    webView.destroy()
                    synchronized(lock) { lock.notifyAll() }
                }
            }
            webView.loadUrl(rawUrl, headers.filterKeys { it.lowercase() != "user-agent" })
        }

        synchronized(lock) {
            if (!done) lock.wait(timeoutMs.toLong() + 2000)
        }
        if (result.containsKey("error")) {
            throw Exception(result["error"].toString())
        }
        return mapOf(
            "statusCode" to (result["statusCode"] ?: 200),
            "body" to (result["body"] ?: ""),
            "finalUrl" to (result["finalUrl"] ?: rawUrl),
            "cookies" to (result["cookies"] ?: emptyMap<String, String>())
        )
    }

    // ---------- Privacy Wipe ----------

    private fun wipeEverything() {
        try {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        } catch (_: Exception) {}
        val dataDir = applicationInfo.dataDir
        File(dataDir, "app_webview").deleteRecursively()
        File(dataDir, "cache").deleteRecursively()
        File(dataDir, "files").deleteRecursively()
        File(dataDir, "shared_prefs").listFiles()?.forEach { it.delete() }
        cacheDir.deleteRecursively()
        databaseList().forEach { deleteDatabase(it) }
    }

    override fun onDestroy() {
        activeTasks.values.forEach { try { it.disconnect() } catch (_: Exception) {} }
        activeTasks.clear()
        executor.shutdownNow()
        super.onDestroy()
    }
}

object AppContextHolder {
    var ctx: Context? = null
}

// ---------- Stripchat Live WebView ----------

class StripchatLiveView(
    private val context: Context,
    private val roomUrl: String,
    private var muted: Boolean,
    private val isStripchat: Boolean
) : PlatformView {
    private val webView: WebView = WebView(context)
    private val handler = Handler(Looper.getMainLooper())
    private var videoRevealed = false

    init {
        setupWebView()
        loadRoom()
    }

    private fun setupWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            loadsImagesAutomatically = true
            loadWithOverviewMode = true
            useWideViewPort = true
        }
        webView.setBackgroundColor(0xFF000000.toInt())
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(v: WebView?, url: String?) {
                super.onPageFinished(v, url)
                if (isStripchat && !videoRevealed) {
                    handler.postDelayed({ installVideoFocus() }, 800)
                }
            }

            override fun shouldOverrideUrlLoading(
                v: WebView?, request: WebResourceRequest?
            ): Boolean {
                if (!isStripchat || request == null) return false
                val host = request.url.host?.lowercase() ?: return true
                return !(host == "stripchat.com" || host.endsWith(".stripchat.com"))
            }

            override fun onReceivedError(
                v: WebView?, request: WebResourceRequest?,
                error: android.webkit.WebResourceError?
            ) {
                if (request?.isForMainFrame == true && isStripchat) {
                    handler.postDelayed({ if (!videoRevealed) loadRoom() }, 3000)
                }
            }
        }
    }

    private fun loadRoom() {
        webView.stopLoading()
        val extraHeaders = hashMapOf<String, String>()
        if (isStripchat) extraHeaders["Referer"] = "https://stripchat.com/"
        webView.loadUrl(roomUrl, extraHeaders)
    }

    private fun installVideoFocus() {
        if (!isStripchat || videoRevealed) return
        val flag = if (muted) "true" else "false"
        val script = """(function(){window.__epickleMuted=$flag;var v=document.querySelector('meta[name=viewport]');if(!v){v=document.createElement('meta');v.name='viewport';document.head.appendChild(v)}v.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover';if(!document.getElementById('__epickle_live_style')){var s=document.createElement('style');s.id='__epickle_live_style';s.textContent='html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:#000!important}video{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;object-fit:contain!important;background:#000!important;z-index:2147483647!important}';document.documentElement.appendChild(s)}var videos=Array.from(document.querySelectorAll('video'));if(!videos.length)return false;var ranked=videos.map(function(v){var r=v.getBoundingClientRect();var area=Math.max(0,r.width)*Math.max(0,r.height);var active=(v.srcObject||v.currentSrc||v.src)?100000000:0;var ready=v.readyState>=2?10000000:0;return{v:v,score:active+ready+area}}).sort(function(a,b){return b.score-a.score});var video=ranked[0].v;video.setAttribute('playsinline','');video.controls=false;video.muted=$flag;window.scrollTo(0,0);if(video.paused)video.play().catch(function(){});return true})()"""
        webView.evaluateJavascript(script) { value ->
            val focused = value == "true"
            if (focused) {
                videoRevealed = true
            } else {
                handler.postDelayed({ installVideoFocus() }, 1000)
            }
        }
    }

    fun setMuted(value: Boolean) {
        muted = value
        val flag = if (value) "true" else "false"
        webView.post {
            webView.evaluateJavascript(
                "window.__epickleMuted=$flag;document.querySelectorAll('video').forEach(function(v){v.muted=$flag})"
            )
        }
    }

    override fun getView(): android.view.View = webView

    override fun dispose() {
        webView.stopLoading()
        webView.webViewClient = null
        webView.removeAllViews()
        webView.destroy()
    }
}
