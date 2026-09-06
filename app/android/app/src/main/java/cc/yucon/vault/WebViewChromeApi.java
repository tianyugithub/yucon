package cc.yucon.vault;

import android.app.Activity;
import android.os.Build;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;

import androidx.webkit.UserAgentMetadata;
import androidx.webkit.WebSettingsCompat;
import androidx.webkit.WebViewFeature;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class WebViewChromeApi {
  private static final Pattern CHROME_VERSION = Pattern.compile("Chrome/([\\d.]+)");

  private WebViewChromeApi() {}

  static boolean apply(Activity activity) {
    try {
      CookieManager.getInstance().setAcceptCookie(true);
    } catch (Exception ignored) {
    }
    final View root = activity.findViewById(android.R.id.content);
    return root != null && applyView(root);
  }

  private static boolean applyView(View view) {
    boolean found = false;
    if (view instanceof WebView) {
      configure((WebView) view);
      found = true;
    }
    if (view instanceof ViewGroup) {
      final ViewGroup group = (ViewGroup) view;
      for (int i = 0; i < group.getChildCount(); i++) {
        found |= applyView(group.getChildAt(i));
      }
    }
    return found;
  }

  private static void configure(WebView webView) {
    try {
      CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);
    } catch (Exception ignored) {
    }
    final WebSettings settings = webView.getSettings();
    settings.setJavaScriptEnabled(true);
    settings.setDomStorageEnabled(true);
    settings.setDatabaseEnabled(true);
    settings.setJavaScriptCanOpenWindowsAutomatically(true);
    settings.setSupportMultipleWindows(false);
    try {
      webView.onResume();
    } catch (Exception ignored) {
    }
    try {
      webView.resumeTimers();
    } catch (Exception ignored) {
    }

    String ua = settings.getUserAgentString();
    if (ua == null) {
      ua = "";
    }
    ua = ua.replaceAll(";\\s*wv", "").replace("Version/4.0 ", "").replaceAll("\\s{2,}", " ").trim();
    if (!ua.contains("Mozilla/5.0") || !ua.contains("AppleWebKit/")) {
      ua =
          "Mozilla/5.0 (Linux; Android "
              + Build.VERSION.RELEASE
              + "; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36";
    }
    settings.setUserAgentString(ua);
    applyChromeClientHints(settings, ua);
  }

  private static void applyChromeClientHints(WebSettings settings, String ua) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) {
      return;
    }
    String chromeVersion = "131.0.0.0";
    final Matcher matcher = CHROME_VERSION.matcher(ua);
    if (matcher.find()) {
      chromeVersion = matcher.group(1);
    }
    final String major = chromeVersion.split("\\.")[0];
    final List<UserAgentMetadata.BrandVersion> brands = new ArrayList<>();
    brands.add(
        new UserAgentMetadata.BrandVersion.Builder()
            .setBrand("Not A(Brand")
            .setMajorVersion("99")
            .setFullVersion("99.0.0.0")
            .build());
    brands.add(
        new UserAgentMetadata.BrandVersion.Builder()
            .setBrand("Chromium")
            .setMajorVersion(major)
            .setFullVersion(chromeVersion)
            .build());
    brands.add(
        new UserAgentMetadata.BrandVersion.Builder()
            .setBrand("Google Chrome")
            .setMajorVersion(major)
            .setFullVersion(chromeVersion)
            .build());
    final UserAgentMetadata metadata =
        new UserAgentMetadata.Builder()
            .setBrandVersionList(brands)
            .setFullVersion(chromeVersion)
            .setPlatform("Android")
            .setPlatformVersion(Build.VERSION.RELEASE)
            .setArchitecture("arm")
            .setModel("Mobile")
            .setMobile(true)
            .setWow64(false)
            .build();
    WebSettingsCompat.setUserAgentMetadata(settings, metadata);
  }
}
