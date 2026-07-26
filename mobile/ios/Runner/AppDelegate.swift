import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?
  private var browserHttpChannel: FlutterMethodChannel?
  private var browserTasks: [UUID: URLSessionDataTask] = [:]
  private var browserRenderRequests: [UUID: BrowserRenderRequest] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "privacy_browser/engine",
      binaryMessenger: messenger
    )
    privacyChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "nuclearWipe":
        PrivacyNativeWipe.run {
          result(nil)
        }
      case "exitApp":
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          exit(0)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let browserChannel = FlutterMethodChannel(
      name: "epickle/browser_http",
      binaryMessenger: messenger
    )
    browserHttpChannel = browserChannel
    browserChannel.setMethodCallHandler { [weak self] call, result in
      guard let self,
            let arguments = call.arguments as? [String: Any],
            let rawUrl = arguments["url"] as? String,
            let url = URL(string: rawUrl) else {
        result(FlutterMethodNotImplemented)
        return
      }

      let headers = (arguments["headers"] as? [String: Any])?.reduce(
        into: [String: String]()
      ) { output, entry in
        output[entry.key] = String(describing: entry.value)
      } ?? [:]
      let timeoutMs = arguments["timeoutMs"] as? Int ?? 10000

      switch call.method {
      case "get":
        self.startBrowserGet(
          url: url,
          headers: headers,
          timeoutMs: timeoutMs,
          result: result
        )
      case "renderGet":
        self.startBrowserRender(
          url: url,
          headers: headers,
          timeoutMs: timeoutMs,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    cancelBrowserRequests()
    super.applicationDidEnterBackground(application)
  }

  private func startBrowserGet(
    url: URL,
    headers: [String: String],
    timeoutMs: Int,
    result: @escaping FlutterResult
  ) {
    let requestId = UUID()
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = max(1, Double(timeoutMs) / 1000.0)
    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }

    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      DispatchQueue.main.async {
        self?.browserTasks.removeValue(forKey: requestId)
        if let error = error {
          result(FlutterError(
            code: "native_http_failed",
            message: error.localizedDescription,
            details: nil
          ))
          return
        }
        guard let http = response as? HTTPURLResponse else {
          result(FlutterError(
            code: "native_http_invalid_response",
            message: "Missing HTTP response",
            details: nil
          ))
          return
        }
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var cookies: [String: String] = [:]
        let finalUrl = http.url ?? url
        HTTPCookieStorage.shared.cookies(for: finalUrl)?.forEach {
          cookies[$0.name] = $0.value
        }
        result([
          "statusCode": http.statusCode,
          "body": body,
          "finalUrl": finalUrl.absoluteString,
          "cookies": cookies,
        ])
      }
    }
    browserTasks[requestId] = task
    task.resume()
  }

  private func startBrowserRender(
    url: URL,
    headers: [String: String],
    timeoutMs: Int,
    result: @escaping FlutterResult
  ) {
    let requestId = UUID()
    let request = BrowserRenderRequest(
      url: url,
      headers: headers,
      timeout: max(1, Double(timeoutMs) / 1000.0)
    ) { [weak self] payload, error in
      self?.browserRenderRequests.removeValue(forKey: requestId)
      if let error {
        result(error)
      } else {
        result(payload)
      }
    }
    browserRenderRequests[requestId] = request
    request.start(in: window?.rootViewController?.view)
  }

  private func cancelBrowserRequests() {
    browserTasks.values.forEach { $0.cancel() }
    browserTasks.removeAll()
    let renderRequests = Array(browserRenderRequests.values)
    browserRenderRequests.removeAll()
    renderRequests.forEach { $0.cancel() }
  }
}

private final class BrowserRenderRequest: NSObject, WKNavigationDelegate {
  private let url: URL
  private let headers: [String: String]
  private let deadline: Date
  private let completion: ([String: Any]?, FlutterError?) -> Void
  private var webView: WKWebView?
  private var timeoutWorkItem: DispatchWorkItem?
  private var completed = false
  private var statusCode = 200

  init(
    url: URL,
    headers: [String: String],
    timeout: TimeInterval,
    completion: @escaping ([String: Any]?, FlutterError?) -> Void
  ) {
    self.url = url
    self.headers = headers
    deadline = Date().addingTimeInterval(timeout)
    self.completion = completion
    super.init()
  }

  func start(in container: UIView?) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let view = WKWebView(
      frame: CGRect(x: 0, y: 0, width: 2, height: 2),
      configuration: configuration
    )
    view.alpha = 0.01
    view.isUserInteractionEnabled = false
    view.navigationDelegate = self
    if let userAgent = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value {
      view.customUserAgent = userAgent
    }
    container?.addSubview(view)
    webView = view

    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    for (name, value) in headers where name.lowercased() != "user-agent" {
      request.setValue(value, forHTTPHeaderField: name)
    }
    view.load(request)

    let timeout = max(1, deadline.timeIntervalSinceNow)
    let workItem = DispatchWorkItem { [weak self] in
      self?.finishError(
        code: "browser_render_timeout",
        message: "Browser rendering timed out"
      )
    }
    timeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
  }

  func cancel() {
    finishError(
      code: "browser_render_cancelled",
      message: "Browser rendering cancelled"
    )
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if navigationResponse.isForMainFrame,
       let response = navigationResponse.response as? HTTPURLResponse {
      statusCode = response.statusCode
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      self?.collectHtml()
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    finishError(code: "browser_render_failed", message: error.localizedDescription)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    finishError(code: "browser_render_failed", message: error.localizedDescription)
  }

  private func collectHtml() {
    guard !completed, let webView else { return }
    let script = """
      (() => {
        const resources = new Set();
        try {
          performance.getEntriesByType('resource').forEach(entry => resources.add(entry.name));
        } catch (_) {}
        document.querySelectorAll('video, source, iframe').forEach(node => {
          if (node.src) resources.add(node.src);
          if (node.currentSrc) resources.add(node.currentSrc);
        });
        return {
          html: document.documentElement.outerHTML,
          resources: Array.from(resources).slice(0, 400),
          href: location.href
        };
      })()
      """
    webView.evaluateJavaScript(script) { [weak self] value, error in
      guard let self, !self.completed else { return }
      if let error {
        self.finishError(
          code: "browser_render_javascript",
          message: error.localizedDescription
        )
        return
      }
      let rendered = value as? [String: Any]
      var html = rendered?["html"] as? String ?? ""
      let resources = rendered?["resources"] as? [String] ?? []
      if !resources.isEmpty {
        let sourceTags = resources.map { resource in
          let safe = resource
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "<", with: "%3C")
          return "<source src=\"\(safe)\">"
        }.joined(separator: "\n")
        html += "\n<!-- WKWebView resource URLs -->\n\(sourceTags)"
      }
      let lower = html.lowercased()
      let challengePending = lower.contains("just a moment") ||
        lower.contains("cf-chl-") ||
        lower.contains("checking your browser") ||
        lower.contains("challenge-platform")
      if challengePending && self.deadline.timeIntervalSinceNow > 1.2 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
          self?.collectHtml()
        }
        return
      }
      let renderedUrl = (rendered?["href"] as? String).flatMap { URL(string: $0) }
      self.finish(html: html, finalUrl: renderedUrl ?? webView.url ?? self.url)
    }
  }

  private func finish(html: String, finalUrl: URL) {
    guard !completed, let webView else { return }
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self, !self.completed else { return }
      let host = finalUrl.host?.lowercased() ?? ""
      var cookieMap: [String: String] = [:]
      for cookie in cookies {
        let domain = cookie.domain
          .lowercased()
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == domain || host.hasSuffix(".\(domain)") {
          cookieMap[cookie.name] = cookie.value
        }
      }
      self.completed = true
      self.timeoutWorkItem?.cancel()
      webView.stopLoading()
      webView.navigationDelegate = nil
      webView.removeFromSuperview()
      self.webView = nil
      self.completion([
        "statusCode": self.statusCode,
        "body": html,
        "finalUrl": finalUrl.absoluteString,
        "cookies": cookieMap,
      ], nil)
    }
  }

  private func finishError(code: String, message: String) {
    guard !completed else { return }
    completed = true
    timeoutWorkItem?.cancel()
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView?.removeFromSuperview()
    webView = nil
    completion(nil, FlutterError(code: code, message: message, details: nil))
  }
}

enum PrivacyNativeWipe {
  static func run(completion: @escaping () -> Void) {
    let group = DispatchGroup()

    group.enter()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    WKWebsiteDataStore.default().removeData(
      ofTypes: types,
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      group.leave()
    }

    HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    URLCache.shared.removeAllCachedResponses()
    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)

    wipeSandboxFiles()
    wipeUserDefaults()
    wipeKeychain()

    group.notify(queue: .main) {
      completion()
    }
  }

  private static func wipeSandboxFiles() {
    let fm = FileManager.default
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let targets = [
      home.appendingPathComponent("Library/Cookies"),
      home.appendingPathComponent("Library/WebKit"),
      home.appendingPathComponent("Library/Caches"),
      home.appendingPathComponent("Library/HTTPStorages"),
      home.appendingPathComponent("Library/Application Support"),
      home.appendingPathComponent("tmp"),
      URL(fileURLWithPath: NSTemporaryDirectory()),
      home.appendingPathComponent("Documents"),
    ]
    for url in targets {
      wipeDirectoryContents(url, fileManager: fm)
    }
  }

  private static func wipeDirectoryContents(_ url: URL, fileManager fm: FileManager) {
    guard fm.fileExists(atPath: url.path) else { return }
    guard let items = try? fm.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil,
      options: []
    ) else {
      return
    }
    for item in items {
      try? fm.removeItem(at: item)
    }
  }

  private static func wipeUserDefaults() {
    if let bundleId = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: bundleId)
    }
    for key in UserDefaults.standard.dictionaryRepresentation().keys {
      UserDefaults.standard.removeObject(forKey: key)
    }
    UserDefaults.standard.synchronize()
  }

  private static func wipeKeychain() {
    let classes: [CFString] = [
      kSecClassGenericPassword,
      kSecClassInternetPassword,
      kSecClassCertificate,
      kSecClassKey,
      kSecClassIdentity,
    ]
    for cls in classes {
      SecItemDelete([kSecClass: cls] as CFDictionary)
    }
  }
}
