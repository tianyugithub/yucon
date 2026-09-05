package cc.yucon.vault;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import org.json.JSONObject;

public class SiteLoginActivity extends AppCompatActivity {

  public static final String EXTRA_LOGIN_URL = "loginUrl";
  public static final String EXTRA_EMAIL = "email";
  public static final String EXTRA_PASSWORD = "password";
  public static final String EXTRA_ACCESS_TOKEN = "accessToken";
  public static final String EXTRA_REFRESH_TOKEN = "refreshToken";

  private final Handler handler = new Handler(Looper.getMainLooper());
  private WebView webView;
  private String loginUrl = "";
  private String email = "";
  private String password = "";
  private boolean finished = false;
  private boolean primed = false;

  private final Runnable poller =
      new Runnable() {
        @Override
        public void run() {
          if (finished || webView == null) {
            return;
          }
          webView.evaluateJavascript(sessionScript(), value -> {
            JSONObject session = parseSession(value);
            if (session != null) {
              finishWithSession(session);
              return;
            }
            webView.evaluateJavascript(assistScript(), ignored -> {});
          });
          handler.postDelayed(this, 700);
        }
      };

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(R.layout.activity_site_login);

    loginUrl = getIntent().getStringExtra(EXTRA_LOGIN_URL);
    email = safe(getIntent().getStringExtra(EXTRA_EMAIL));
    password = safe(getIntent().getStringExtra(EXTRA_PASSWORD));
    if (loginUrl == null || !(loginUrl.startsWith("https://") || loginUrl.startsWith("http://"))) {
      setResult(Activity.RESULT_CANCELED);
      finish();
      return;
    }

    WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
    getWindow().setStatusBarColor(Color.TRANSPARENT);
    WindowInsetsControllerCompat controller =
        WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
    controller.setAppearanceLightStatusBars(false);

    View root = findViewById(R.id.site_login_root);
    ViewCompat.setOnApplyWindowInsetsListener(
        root,
        (view, insets) -> {
          Insets bars =
              insets.getInsets(
                  WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
          view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
          return WindowInsetsCompat.CONSUMED;
        });

    findViewById(R.id.site_login_cancel).setOnClickListener(v -> cancel());

    webView = findViewById(R.id.site_login_webview);
    CookieManager cookieManager = CookieManager.getInstance();
    cookieManager.setAcceptCookie(true);
    cookieManager.setAcceptThirdPartyCookies(webView, true);

    WebSettings settings = webView.getSettings();
    settings.setJavaScriptEnabled(true);
    settings.setDomStorageEnabled(true);
    settings.setDatabaseEnabled(true);
    settings.setJavaScriptCanOpenWindowsAutomatically(true);
    settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);

    webView.setWebChromeClient(new WebChromeClient());
    webView.setWebViewClient(
        new WebViewClient() {
          @Override
          public void onPageFinished(WebView view, String url) {
            if (!primed) {
              primed = true;
              view.evaluateJavascript(primeScript(), ignored -> {});
            }
            view.evaluateJavascript(assistScript(), ignored -> {});
          }
        });

    webView.loadUrl(loginUrl);
    handler.postDelayed(poller, 800);
  }

  @Override
  public void onBackPressed() {
    if (webView != null && webView.canGoBack()) {
      webView.goBack();
      return;
    }
    cancel();
  }

  @Override
  protected void onDestroy() {
    handler.removeCallbacks(poller);
    if (webView != null) {
      webView.stopLoading();
      ViewGroup parent = (ViewGroup) webView.getParent();
      if (parent != null) {
        parent.removeView(webView);
      }
      webView.destroy();
      webView = null;
    }
    super.onDestroy();
  }

  private void cancel() {
    if (finished) {
      return;
    }
    finished = true;
    setResult(Activity.RESULT_CANCELED);
    finish();
  }

  private void finishWithSession(JSONObject session) {
    if (finished) {
      return;
    }
    String accessToken = session.optString("accessToken", "");
    if (accessToken.isEmpty()) {
      return;
    }
    finished = true;
    handler.removeCallbacks(poller);
    Intent data = new Intent();
    data.putExtra(EXTRA_ACCESS_TOKEN, accessToken);
    data.putExtra(EXTRA_REFRESH_TOKEN, session.optString("refreshToken", ""));
    setResult(Activity.RESULT_OK, data);
    finish();
  }

  private String primeScript() {
    return "(function(){"
        + "var wanted="
        + jsonString(email)
        + ";"
        + "function readUser(){try{return JSON.parse(localStorage.getItem('auth_user')||'null')}catch(e){return null}}"
        + "var token=localStorage.getItem('auth_token');"
        + "var user=readUser();"
        + "var current=user&&user.email?String(user.email):'';"
        + "if(token&&wanted&&current&&current.toLowerCase()!==wanted.toLowerCase()){"
        + "localStorage.removeItem('auth_token');"
        + "localStorage.removeItem('refresh_token');"
        + "localStorage.removeItem('auth_user');"
        + "localStorage.removeItem('token_expires_at');"
        + "location.replace("
        + jsonString(loginUrl)
        + ");"
        + "}"
        + "})();";
  }

  private String sessionScript() {
    return "(function(){"
        + "var wanted="
        + jsonString(email)
        + ";"
        + "var token=localStorage.getItem('auth_token');"
        + "if(!token)return null;"
        + "var user=null;try{user=JSON.parse(localStorage.getItem('auth_user')||'null')}catch(e){}"
        + "var current=user&&user.email?String(user.email):'';"
        + "if(wanted&&current&&current.toLowerCase()!==wanted.toLowerCase())return null;"
        + "return {accessToken:token,refreshToken:localStorage.getItem('refresh_token')||''};"
        + "})()";
  }

  private String assistScript() {
    return "(function(){"
        + "var cred={email:"
        + jsonString(email)
        + ",password:"
        + jsonString(password)
        + "};"
        + "function setValue(el,value){"
        + "if(!el||!value)return;"
        + "var proto=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');"
        + "if(proto&&proto.set){proto.set.call(el,value)}else{el.value=value}"
        + "el.dispatchEvent(new Event('input',{bubbles:true}));"
        + "el.dispatchEvent(new Event('change',{bubbles:true}));"
        + "}"
        + "var emailInput=document.querySelector('input[type=\"email\"],input[name=\"email\"],input[autocomplete=\"email\"]');"
        + "var passwordInput=document.querySelector('input[type=\"password\"]');"
        + "setValue(emailInput,cred.email);"
        + "setValue(passwordInput,cred.password);"
        + "var turnstile=document.querySelector('textarea[name=\"cf-turnstile-response\"],input[name=\"cf-turnstile-response\"]');"
        + "if(turnstile&&turnstile.value&&cred.email&&cred.password){"
        + "var button=document.querySelector('form button[type=\"submit\"],form button');"
        + "if(button&&!button.disabled&&!button.dataset.ycClicked){button.dataset.ycClicked='1';button.click();}"
        + "}"
        + "})();";
  }

  private JSONObject parseSession(String value) {
    if (value == null || "null".equals(value)) {
      return null;
    }
    try {
      return new JSONObject(value);
    } catch (Exception ignored) {
      return null;
    }
  }

  private static String jsonString(String value) {
    return JSONObject.quote(safe(value));
  }

  private static String safe(String value) {
    return value == null ? "" : value;
  }
}
