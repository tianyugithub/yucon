package cc.yucon.vault;

import androidx.webkit.ProxyConfig;
import androidx.webkit.ProxyController;
import androidx.webkit.WebViewFeature;

import java.util.concurrent.Executor;

import io.flutter.plugin.common.MethodChannel;

final class WebViewProxyApi {
  private WebViewProxyApi() {}

  static boolean supported() {
    return WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
  }

  static void set(String host, int port, String scheme, Executor executor, MethodChannel.Result result) {
    if (!supported() || host == null || host.isEmpty() || port <= 0) {
      result.success(false);
      return;
    }
    final String normalized = scheme == null ? "http" : scheme.toLowerCase();
    final String rule;
    if (normalized.startsWith("socks")) {
      rule = "socks://" + host + ":" + port;
    } else {
      // HTTP and HTTPS both use an HTTP CONNECT proxy. WebView's https:// rule is
      // TLS-to-proxy and would break common mixed ports such as Clash 7890.
      rule = "http://" + host + ":" + port;
    }
    final ProxyConfig config = new ProxyConfig.Builder().addProxyRule(rule).build();
    ProxyController.getInstance().setProxyOverride(config, executor, () -> result.success(true));
  }

  static void clear(Executor executor, MethodChannel.Result result) {
    if (!supported()) {
      result.success(false);
      return;
    }
    ProxyController.getInstance().clearProxyOverride(executor, () -> result.success(true));
  }
}
