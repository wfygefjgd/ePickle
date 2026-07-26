import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?
  private var browserHttpChannel: FlutterMethodChannel?

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
    browserChannel.setMethodCallHandler { call, result in
      guard call.method == "get",
            let arguments = call.arguments as? [String: Any],
            let rawUrl = arguments["url"] as? String,
            let url = URL(string: rawUrl) else {
        result(FlutterMethodNotImplemented)
        return
      }

      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let timeoutMs = arguments["timeoutMs"] as? Int ?? 10000
      request.timeoutInterval = max(1, Double(timeoutMs) / 1000.0)
      if let headers = arguments["headers"] as? [String: String] {
        for (name, value) in headers {
          request.setValue(value, forHTTPHeaderField: name)
        }
      }

      URLSession.shared.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
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
      }.resume()
    }
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
