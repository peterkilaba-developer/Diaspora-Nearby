import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Example widget test demonstrating best practices
/// 
/// This is a template - actual widget tests should be created
/// for specific widgets in your app.

void main() {
  group('Widget Testing Example', () {
    testWidgets('Simple widget displays correctly', (tester) async {
      // Build the widget
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Text('Hello Test'),
            ),
          ),
        ),
      );

      // Verify the widget
      expect(find.text('Hello Test'), findsOneWidget);
    });

    testWidgets('Button tap triggers action', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () => tapCount++,
                child: const Text('Tap Me'),
              ),
            ),
          ),
        ),
      );

      // Find and tap the button
      await tester.tap(find.text('Tap Me'));
      await tester.pump();

      // Verify action occurred
      expect(tapCount, equals(1));
    });

    testWidgets('List displays items correctly', (tester) async {
      final items = ['Item 1', 'Item 2', 'Item 3'];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) => Text(items[index]),
              ),
            ),
          ),
        ),
      );

      // Verify items are displayed
      for (final item in items) {
        expect(find.text(item), findsOneWidget);
      }
    });
  });

  group('Widget Test Helpers', () {
    /// Helper to create a testable widget wrapped with providers
    Widget createTestWidget(Widget child) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: child,
          ),
        ),
      );
    }

    testWidgets('Helper creates proper widget tree', (tester) async {
      await tester.pumpWidget(
        createTestWidget(const Text('Test Widget')),
      );

      expect(find.text('Test Widget'), findsOneWidget);
    });
  });
}
