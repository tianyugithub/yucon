package cc.yucon.vault;

import android.content.Intent;
import androidx.activity.result.ActivityResult;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "SiteSession")
public class SiteSessionPlugin extends Plugin {

  @PluginMethod
  public void capture(PluginCall call) {
    String loginUrl = call.getString("loginUrl", "");
    if (loginUrl == null || loginUrl.trim().isEmpty()) {
      call.reject("请填写站点地址");
      return;
    }
    Intent intent = new Intent(getContext(), SiteLoginActivity.class);
    intent.putExtra(SiteLoginActivity.EXTRA_LOGIN_URL, loginUrl.trim());
    intent.putExtra(SiteLoginActivity.EXTRA_EMAIL, call.getString("email", ""));
    intent.putExtra(SiteLoginActivity.EXTRA_PASSWORD, call.getString("password", ""));
    startActivityForResult(call, intent, "onLoginResult");
  }

  @ActivityCallback
  private void onLoginResult(PluginCall call, ActivityResult result) {
    if (call == null) {
      return;
    }
    if (result.getResultCode() != android.app.Activity.RESULT_OK || result.getData() == null) {
      call.reject("已取消站点登录");
      return;
    }
    String accessToken = result.getData().getStringExtra(SiteLoginActivity.EXTRA_ACCESS_TOKEN);
    if (accessToken == null || accessToken.trim().isEmpty()) {
      call.reject("未能从站点获取登录令牌");
      return;
    }
    JSObject payload = new JSObject();
    payload.put("accessToken", accessToken.trim());
    payload.put("refreshToken", result.getData().getStringExtra(SiteLoginActivity.EXTRA_REFRESH_TOKEN));
    call.resolve(payload);
  }
}
