import 'dart:io';

void main() {
  final file = File('C:\\Projects\\DiasporaNearby\\lib\\features\\organization\\screens\\organization_management_screen.dart');
  String content = file.readAsStringSync();
  content = content.replaceAll('â€¢', '•');
  file.writeAsStringSync(content);
}
