package cc.yucon.vault;

import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;
import android.webkit.CookieManager;

import androidx.annotation.NonNull;

import java.util.concurrent.Executor;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
  private static final String CHANNEL = "cc.yucon.vault/proxy";

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    try {
      CookieManager.getInstance().setAcceptCookie(true);
    } catch (Exception ignored) {
      // CookieManager may not be ready on some WebView builds.
    }
    final Executor executor = command -> new Handler(Looper.getMainLooper()).post(command);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
        .setMethodCallHandler(
            (call, result) -> {
              if ("setWebViewProxy".equals(call.method)) {
                final String host = call.argument("host");
                final Integer port = call.argument("port");
                final String schemeArg = call.argument("scheme");
                final Boolean socks = call.argument("socks");
                final String scheme =
                    schemeArg != null && !schemeArg.isEmpty()
                        ? schemeArg
                        : (Boolean.TRUE.equals(socks) ? "socks5" : "http");
                WebViewProxyApi.set(
                    host,
                    port == null ? 0 : port,
                    scheme,
                    executor,
                    result);
              } else if ("clearWebViewProxy".equals(call.method)) {
                WebViewProxyApi.clear(executor, result);
              } else if ("setSecureFlag".equals(call.method)) {
                final Boolean enable = call.argument("enable");
                runOnUiThread(
                    () -> {
                      if (Boolean.TRUE.equals(enable)) {
                        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
                      } else {
                        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
                      }
                      result.success(true);
                    });
              } else if ("configureChromeWebView".equals(call.method)) {
                runOnUiThread(
                    () -> {
                      try {
                        result.success(WebViewChromeApi.apply(MainActivity.this));
                      } catch (Exception error) {
                        result.success(false);
                      }
                    });
              } else if ("enableWebViewCookies".equals(call.method)) {
                runOnUiThread(
                    () -> {
                      try {
                        CookieManager.getInstance().setAcceptCookie(true);
                        result.success(true);
                      } catch (Exception error) {
                        result.success(false);
                      }
                    });
              } else if ("getCookies".equals(call.method)) {
                final String url = call.argument("url");
                if (url == null || url.isEmpty()) {
                  result.success("");
                  return;
                }
                try {
                  final CookieManager manager = CookieManager.getInstance();
                  manager.setAcceptCookie(true);
                  try {
                    manager.flush();
                  } catch (Exception ignored) {
                    // Older WebView builds may not flush synchronously.
                  }
                  final String cookies = manager.getCookie(url);
                  result.success(cookies == null ? "" : cookies);
                } catch (Exception error) {
                  result.success("");
                }
              } else if ("setCookies".equals(call.method)) {
                runOnUiThread(
                    () -> {
                      try {
                        final java.util.List<?> items = call.argument("cookies");
                        final CookieManager manager = CookieManager.getInstance();
                        manager.setAcceptCookie(true);
                        if (items != null) {
                          for (final Object item : items) {
                            if (!(item instanceof java.util.Map)) {
                              continue;
                            }
                            final java.util.Map<?, ?> map = (java.util.Map<?, ?>) item;
                            final String url = stringArg(map, "url");
                            final String name = stringArg(map, "name");
                            final String value = stringArg(map, "value");
                            if (url.isEmpty() || name.isEmpty()) {
                              continue;
                            }
                            if (name.contains(";")
                                || name.contains("\n")
                                || name.contains("\r")
                                || value.contains("\n")
                                || value.contains("\r")) {
                              continue;
                            }
                            final StringBuilder cookie =
                                new StringBuilder(name).append("=").append(value);
                            final String path = stringArg(map, "path");
                            cookie.append("; Path=").append(path.isEmpty() ? "/" : path);
                            final String domain = stringArg(map, "domain");
                            if (!domain.isEmpty() && !name.startsWith("__Host-")) {
                              cookie.append("; Domain=").append(domain);
                            }
                            if (Boolean.TRUE.equals(map.get("secure")) || url.startsWith("https")) {
                              cookie.append("; Secure");
                            }
                            final Object maxAge = map.get("maxAge");
                            if (maxAge instanceof Number) {
                              cookie.append("; Max-Age=").append(((Number) maxAge).intValue());
                            }
                            manager.setCookie(url, cookie.toString());
                          }
                        }
                        try {
                          manager.flush();
                        } catch (Exception ignored) {
                        }
                        result.success(true);
                      } catch (Exception error) {
                        result.success(false);
                      }
                    });
              } else if ("clearSiteWebData".equals(call.method)) {
                final String url = call.argument("url");
                runOnUiThread(
                    () -> SiteWebDataClearer.clear(MainActivity.this, url, result));
              } else {
                result.notImplemented();
              }
            });
  }

  private static String stringArg(java.util.Map<?, ?> map, String key) {
    final Object value = map.get(key);
    return value == null ? "" : String.valueOf(value);
  }
}
