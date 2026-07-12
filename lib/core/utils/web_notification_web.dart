import 'package:web/web.dart' as web;

/// Show a browser notification on web using the Notification API.
void showWebNotification(
  String title,
  String body, {
  String? tag,
  String? icon,
}) {
  try {
    final options = web.NotificationOptions(
      body: body,
      icon: icon ?? '/icons/Icon-192.png',
      tag: tag ?? 'fcm-${DateTime.now().millisecondsSinceEpoch}',
    );
    web.Notification(title, options);
  } catch (e) {
    // ignore — permission may not be granted
  }
}
