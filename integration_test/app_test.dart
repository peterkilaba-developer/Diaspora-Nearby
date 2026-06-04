import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:diaspora_nearby/main.dart' as app;

/// Basic integration test demonstrating app launch
///
/// Run with: flutter test integration_test/app_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    testWidgets('app launches successfully', (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      // Verify app launched (adjust based on your actual app)
      // This is a placeholder - update to match your app's initial screen
      expect(find.text('Diaspora Nearby'), findsWidgets);
    });
  });
}
