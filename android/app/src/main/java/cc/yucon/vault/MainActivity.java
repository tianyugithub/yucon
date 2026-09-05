package cc.yucon.vault;

import android.graphics.Color;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.WebView;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

  private static final int PAGE_BACKGROUND = 0xFFF5F5F5;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    registerPlugin(SiteSessionPlugin.class);
    super.onCreate(savedInstanceState);

    WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
    getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    getWindow().getDecorView().setBackgroundColor(PAGE_BACKGROUND);
    getWindow().setStatusBarColor(Color.TRANSPARENT);
    getWindow().setNavigationBarColor(Color.TRANSPARENT);

    WindowInsetsControllerCompat controller =
        WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
    controller.setAppearanceLightStatusBars(true);
    controller.setAppearanceLightNavigationBars(true);

    WebView webView = getBridge() != null ? getBridge().getWebView() : null;
    if (webView == null) {
      return;
    }

    webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
    webView.setVerticalScrollBarEnabled(false);
    webView.setHorizontalScrollBarEnabled(false);

    ViewCompat.setOnApplyWindowInsetsListener(
        webView,
        (view, windowInsets) -> {
          Insets bars =
              windowInsets.getInsets(
                  WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
          Insets ime = windowInsets.getInsets(WindowInsetsCompat.Type.ime());
          ViewGroup.MarginLayoutParams layoutParams =
              (ViewGroup.MarginLayoutParams) view.getLayoutParams();
          layoutParams.leftMargin = bars.left;
          layoutParams.rightMargin = bars.right;
          layoutParams.topMargin = bars.top;
          layoutParams.bottomMargin = Math.max(bars.bottom, ime.bottom);
          view.setLayoutParams(layoutParams);
          return WindowInsetsCompat.CONSUMED;
        });
    ViewCompat.requestApplyInsets(webView);
  }
}
