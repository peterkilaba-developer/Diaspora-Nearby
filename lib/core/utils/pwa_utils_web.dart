import 'dart:js' as js;

Future<bool> promptInstall() async {
  try {
    final result = await js.context.callMethod('presentPWAInstall');
    return result == true;
  } catch (e) {
    return false;
  }
}
