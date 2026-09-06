import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "cc.yucon.vault/proxy",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSecureFlag":
        result(true)
      case "setWebViewProxy", "clearWebViewProxy":
        result(nil)
      case "enableWebViewCookies", "configureChromeWebView":
        result(true)
      case "getCookies":
        let urlString = (call.arguments as? [String: Any])?["url"] as? String ?? ""
        Self.readCookies(urlString: urlString, result: result)
      case "setCookies":
        let items = (call.arguments as? [String: Any])?["cookies"] as? [[String: Any]] ?? []
        Self.writeCookies(items: items, result: result)
      case "clearSiteWebData":
        let urlString = (call.arguments as? [String: Any])?["url"] as? String ?? ""
        Self.clearSiteWebData(urlString: urlString, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func cookieMatches(_ cookie: HTTPCookie, url: URL) -> Bool {
    guard let host = url.host?.lowercased() else {
      return false
    }
    var domain = cookie.domain.lowercased()
    if domain.hasPrefix(".") {
      domain.removeFirst()
    }
    return host == domain || host.hasSuffix("." + domain)
  }

  private static func readCookies(urlString: String, result: @escaping FlutterResult) {
    guard let url = URL(string: urlString), url.host != nil else {
      result("")
      return
    }
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      let header = cookies
        .filter { cookieMatches($0, url: url) }
        .map { "\($0.name)=\($0.value)" }
        .joined(separator: "; ")
      result(header)
    }
  }

  private static func writeCookies(items: [[String: Any]], result: @escaping FlutterResult) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    let group = DispatchGroup()
    for item in items {
      let name = item["name"] as? String ?? ""
      let value = item["value"] as? String ?? ""
      let urlString = item["url"] as? String ?? ""
      if name.isEmpty || urlString.isEmpty {
        continue
      }
      let pathValue = item["path"] as? String
      var props: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .path: (pathValue?.isEmpty == false ? pathValue : nil) ?? "/",
      ]
      let hostOnly = name.hasPrefix("__Host-")
      let domain = item["domain"] as? String ?? ""
      if hostOnly {
        props[.originURL] = urlString
        props[.path] = "/"
      } else if !domain.isEmpty {
        props[.domain] = domain
      } else if let host = URL(string: urlString)?.host {
        props[.domain] = host
      }
      if hostOnly || (item["secure"] as? Bool) == true || urlString.hasPrefix("https") {
        props[.secure] = "TRUE"
      }
      if let maxAge = item["maxAge"] as? NSNumber {
        props[.maximumAge] = "\(maxAge.intValue)"
      }
      var cookie = HTTPCookie(properties: props)
      if cookie == nil, hostOnly, let host = URL(string: urlString)?.host {
        props[.domain] = host
        cookie = HTTPCookie(properties: props)
      }
      guard let cookie = cookie else {
        continue
      }
      group.enter()
      store.setCookie(cookie) {
        group.leave()
      }
    }
    group.notify(queue: .main) {
      result(true)
    }
  }

  private static func looksLikeSameSiteHost(_ candidate: String, siteHost: String) -> Bool {
    func bare(_ value: String) -> String {
      var host = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      if host.hasPrefix(".") {
        host.removeFirst()
      }
      return host
    }
    let a = bare(candidate)
    let b = bare(siteHost)
    if a.isEmpty || b.isEmpty {
      return false
    }
    if a == b {
      return true
    }
    if a.hasSuffix("." + b) && b.contains(".") {
      return true
    }
    return b.hasSuffix("." + a) && a.contains(".")
  }

  private static func clearSiteWebData(urlString: String, result: @escaping FlutterResult) {
    guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
      result(false)
      return
    }
    let store = WKWebsiteDataStore.default()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    store.fetchDataRecords(ofTypes: types) { records in
      let matched = records.filter { looksLikeSameSiteHost($0.displayName, siteHost: host) }
      store.removeData(ofTypes: types, for: matched) {
        store.httpCookieStore.getAllCookies { cookies in
          let group = DispatchGroup()
          for cookie in cookies where looksLikeSameSiteHost(cookie.domain, siteHost: host) {
            group.enter()
            store.httpCookieStore.delete(cookie) {
              group.leave()
            }
          }
          group.notify(queue: .main) {
            result(true)
          }
        }
      }
    }
  }
}
