package cc.yucon.vault;

import android.app.Activity;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.webkit.CookieManagerCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.MethodChannel;

final class SiteWebDataClearer {
  private static final String WIPE_JS =
      "(function(){"
          + "try{localStorage.clear();}catch(e){}"
          + "try{sessionStorage.clear();}catch(e){}"
          + "try{"
          + "if(indexedDB&&indexedDB.databases){"
          + "indexedDB.databases().then(function(dbs){"
          + "if(!dbs)return;"
          + "for(var i=0;i<dbs.length;i++){"
          + "if(dbs[i]&&dbs[i].name)indexedDB.deleteDatabase(dbs[i].name);"
          + "}"
          + "});"
          + "}"
          + "}catch(e){}"
          + "try{"
          + "navigator.serviceWorker.getRegistrations().then(function(rs){"
          + "for(var i=0;i<rs.length;i++){rs[i].unregister();}"
          + "});"
          + "}catch(e){}"
          + "try{"
          + "caches.keys().then(function(keys){"
          + "for(var i=0;i<keys.length;i++){caches.delete(keys[i]);}"
          + "});"
          + "}catch(e){}"
          + "return 1;"
          + "})();";

  private static final String[] PATHS = {
    "/",
    "/login",
    "/sign-in",
    "/signin",
    "/register",
    "/dashboard",
    "/console",
    "/panel",
    "/admin",
    "/app",
    "/api",
    "/api/",
    "/api/v1",
    "/api/v1/",
    "/api/user",
    "/api/user/",
    "/api/user/auth",
    "/api/user/auth/",
    "/auth",
    "/oauth",
  };

  private SiteWebDataClearer() {}

  static void clear(Activity activity, String url, MethodChannel.Result result) {
    final Handler handler = new Handler(Looper.getMainLooper());
    final AtomicBoolean done = new AtomicBoolean(false);
    final Runnable finish =
        () -> {
          if (!done.compareAndSet(false, true)) {
            return;
          }
          try {
            CookieManager.getInstance().flush();
          } catch (Exception ignored) {
          }
          result.success(true);
        };
    handler.postDelayed(finish, 4000);
    if (url == null || url.trim().isEmpty()) {
      finish.run();
      return;
    }
    final Uri uri = Uri.parse(url.trim());
    final String host = uri.getHost();
    if (host == null || host.isEmpty()) {
      finish.run();
      return;
    }
    String scheme = uri.getScheme();
    if (scheme == null || scheme.isEmpty()) {
      scheme = "https";
    }
    final String origin = originOf(scheme, host, uri.getPort());
    final CookieManager manager = CookieManager.getInstance();
    manager.setAcceptCookie(true);
    for (final String candidate : cookieUrls(origin, host, scheme)) {
      expireCookiesForUrl(manager, candidate, host);
    }
    try {
      manager.flush();
    } catch (Exception ignored) {
    }
    deleteMatchingOrigins(
        host,
        origin,
        scheme,
        () -> wipeInHiddenWebView(activity, origin, finish, handler));
  }

  private static String originOf(String scheme, String host, int port) {
    String origin = scheme + "://" + host;
    if (port > 0 && port != 80 && port != 443) {
      origin += ":" + port;
    }
    return origin;
  }

  private static List<String> cookieUrls(String origin, String host, String scheme) {
    final Set<String> urls = new LinkedHashSet<>();
    for (final String path : PATHS) {
      urls.add(origin + path);
    }
    if ("https".equalsIgnoreCase(scheme)) {
      urls.add("http://" + host + "/");
      urls.add("http://" + host + "/login");
    }
    if (host.startsWith("www.")) {
      final String apex = host.substring(4);
      urls.add(scheme + "://" + apex + "/");
      urls.add(scheme + "://" + apex + "/login");
    } else if (host.indexOf('.') > 0) {
      urls.add(scheme + "://www." + host + "/");
      urls.add(scheme + "://www." + host + "/login");
    }
    return new ArrayList<>(urls);
  }

  private static void expireCookiesForUrl(CookieManager manager, String url, String siteHost) {
    final List<String> records = cookieRecords(manager, url);
    if (records.isEmpty()) {
      return;
    }
    for (final String record : records) {
      expireCookieRecord(manager, url, record, siteHost);
    }
  }

  private static List<String> cookieRecords(CookieManager manager, String url) {
    if (WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)) {
      try {
        return CookieManagerCompat.getCookieInfo(manager, url);
      } catch (Exception ignored) {
      }
    }
    final String header = manager.getCookie(url);
    if (header == null || header.isEmpty()) {
      return Collections.emptyList();
    }
    return Arrays.asList(header.split(";"));
  }

  private static void expireCookieRecord(
      CookieManager manager, String url, String record, String siteHost) {
    final String[] parts = record.split(";");
    if (parts.length == 0) {
      return;
    }
    final String[] nameValue = parts[0].split("=", 2);
    final String name = nameValue[0].trim();
    if (name.isEmpty() || name.contains("\n") || name.contains("\r")) {
      return;
    }
    String path = "/";
    String domain = "";
    boolean secure = url.startsWith("https");
    boolean httpOnly = false;
    for (int i = 1; i < parts.length; i++) {
      final String[] pair = parts[i].split("=", 2);
      final String key = pair[0].trim();
      final String value = pair.length > 1 ? pair[1].trim() : "";
      if (key.equalsIgnoreCase("Path") && !value.isEmpty()) {
        path = value;
      } else if (key.equalsIgnoreCase("Domain")) {
        domain = value;
      } else if (key.equalsIgnoreCase("Secure")) {
        secure = true;
      } else if (key.equalsIgnoreCase("HttpOnly")) {
        httpOnly = true;
      }
    }
    final Set<String> paths = new LinkedHashSet<>();
    paths.add(path);
    paths.add("/");
    paths.addAll(pathPrefixes(url));
    final Set<String> domains = new LinkedHashSet<>();
    domains.add("");
    if (!name.startsWith("__Host-")) {
      if (!domain.isEmpty()) {
        domains.add(domain);
      }
      domains.add(siteHost);
      domains.add("." + siteHost);
      final int dot = siteHost.indexOf('.');
      if (dot > 0 && siteHost.substring(dot + 1).contains(".")) {
        domains.add(siteHost.substring(dot));
      }
    }
    for (final String cookiePath : paths) {
      for (final String cookieDomain : domains) {
        final StringBuilder cookie = new StringBuilder(name);
        cookie.append("=; Max-Age=-1; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=");
        cookie.append(cookiePath.isEmpty() ? "/" : cookiePath);
        if (!cookieDomain.isEmpty()) {
          cookie.append("; Domain=").append(cookieDomain);
        }
        if (secure) {
          cookie.append("; Secure");
        }
        if (httpOnly) {
          cookie.append("; HttpOnly");
        }
        manager.setCookie(url, cookie.toString());
      }
    }
  }

  private static List<String> pathPrefixes(String url) {
    final String path = Uri.parse(url).getPath();
    if (path == null || path.isEmpty() || "/".equals(path)) {
      return Collections.singletonList("/");
    }
    final List<String> prefixes = new ArrayList<>();
    prefixes.add("/");
    final String[] segments = path.split("/");
    final StringBuilder current = new StringBuilder();
    for (final String segment : segments) {
      if (segment.isEmpty()) {
        continue;
      }
      current.append('/').append(segment);
      prefixes.add(current.toString());
      prefixes.add(current + "/");
    }
    return prefixes;
  }

  @SuppressWarnings({"rawtypes", "unchecked"})
  private static void deleteMatchingOrigins(
      String host, String origin, String scheme, Runnable next) {
    final WebStorage storage = WebStorage.getInstance();
    final ValueCallback<Map> callback =
        map -> {
          try {
            if (map != null) {
              for (final Object key : map.keySet()) {
                final String stored = String.valueOf(key);
                final String storedHost = Uri.parse(stored).getHost();
                if (storedHost != null && looksLikeSameSiteHost(storedHost, host)) {
                  storage.deleteOrigin(stored);
                }
              }
            }
          } catch (Exception ignored) {
          }
          try {
            storage.deleteOrigin(origin);
          } catch (Exception ignored) {
          }
          if ("https".equalsIgnoreCase(scheme)) {
            try {
              storage.deleteOrigin("http://" + host);
            } catch (Exception ignored) {
            }
          }
          next.run();
        };
    try {
      storage.getOrigins(callback);
    } catch (Exception ignored) {
      try {
        storage.deleteOrigin(origin);
      } catch (Exception ignored2) {
      }
      next.run();
    }
  }

  private static void wipeInHiddenWebView(
      Activity activity, String origin, Runnable finish, Handler handler) {
    if (activity == null || activity.isFinishing()) {
      finish.run();
      return;
    }
    final WebView webView;
    try {
      webView = new WebView(activity);
    } catch (Exception ignored) {
      finish.run();
      return;
    }
    try {
      CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);
    } catch (Exception ignored) {
    }
    final WebSettings settings = webView.getSettings();
    settings.setJavaScriptEnabled(true);
    settings.setDomStorageEnabled(true);
    settings.setDatabaseEnabled(true);
    if (WebViewFeature.isFeatureSupported("DOCUMENT_START_SCRIPT")
        || WebViewFeature.isFeatureSupported("DOCUMENT_START_JAVASCRIPT")) {
      try {
        WebViewCompat.addDocumentStartJavaScript(
            webView, WIPE_JS, Collections.singleton("*"));
      } catch (Exception ignored) {
      }
    }
    final AtomicBoolean wiped = new AtomicBoolean(false);
    final Runnable destroyAndFinish =
        () -> {
          if (!wiped.compareAndSet(false, true)) {
            return;
          }
          try {
            webView.stopLoading();
            webView.loadUrl("about:blank");
            webView.destroy();
          } catch (Exception ignored) {
          }
          finish.run();
        };
    webView.setWebViewClient(
        new WebViewClient() {
          @Override
          public void onPageFinished(WebView view, String url) {
            try {
              view.evaluateJavascript(WIPE_JS, value -> handler.postDelayed(destroyAndFinish, 400));
            } catch (Exception ignored) {
              destroyAndFinish.run();
            }
          }

          @Override
          public void onReceivedError(
              WebView view, int errorCode, String description, String failingUrl) {
            destroyAndFinish.run();
          }
        });
    handler.postDelayed(destroyAndFinish, 2500);
    try {
      webView.loadUrl(origin + "/");
    } catch (Exception ignored) {
      destroyAndFinish.run();
    }
  }

  static boolean looksLikeSameSiteHost(String candidate, String siteHost) {
    final String a = bareHost(candidate);
    final String b = bareHost(siteHost);
    if (a.isEmpty() || b.isEmpty()) {
      return false;
    }
    if (a.equals(b)) {
      return true;
    }
    if (a.endsWith("." + b) && b.contains(".")) {
      return true;
    }
    return b.endsWith("." + a) && a.contains(".");
  }

  private static String bareHost(String host) {
    String value = host == null ? "" : host.trim().toLowerCase();
    if (value.startsWith(".")) {
      value = value.substring(1);
    }
    return value;
  }
}
