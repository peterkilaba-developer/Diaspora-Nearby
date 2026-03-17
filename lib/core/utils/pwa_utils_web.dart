import 'dart:js_interop';

@JS('presentPWAInstall')
external JSAny? _presentPWAInstall();

Future<bool> promptInstall() async {
  try {
    final result = _presentPWAInstall();
    return result.dartify() == true;
  } catch (e) {
    return false;
  }
}
