package id.flutter.flutter_background_service;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) return;
        String action = intent.getAction();
        if (action.equals(Intent.ACTION_MY_PACKAGE_REPLACED)
                || action.equals(Intent.ACTION_BOOT_COMPLETED)
                || action.equals("android.intent.action.QUICKBOOT_POWERON")) {
            // Disabled on Android: spinning up a secondary FlutterEngine in the
            // same process as AudioServiceFragmentActivity causes plugin channel
            // and engine lifecycle contention. Clear any legacy persisted flags.
            final Config config = new Config(context);
            config.setAutoStartOnBoot(false);
            config.setManuallyStopped(true);
            WatchdogReceiver.remove(context);
        }
    }
}
