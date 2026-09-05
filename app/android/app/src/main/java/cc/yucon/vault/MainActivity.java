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
              } else {
                result.notImplemented();
              }
            });
  }
}
