# Testing Guide

## Overview

This guide explains our testing strategy and how to write effective tests for the Diaspora Nearby app.

## Testing Philosophy

- **Write tests for critical business logic** - Focus on services, repositories, and core algorithms
- **Test public interfaces** - Don't test private implementation details
- **Keep tests simple and readable** - Tests are documentation
- **Use mocks for external dependencies** - Isolate what you're testing

## Running Tests

### All Tests
```bash
flutter test
```

### Specific Test File
```bash
flutter test test/features/dsp/services/points_service_test.dart
```

### Integration Tests
```bash
flutter test integration_test/app_test.dart
```

### With Coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## Test Structure

### Directory Organization
```
test/
├── utils/                    # Shared test utilities
│   ├── mock_providers.dart   # Riverpod provider mocks
│   ├── test_data.dart        # Test data generators
│   └── firebase_mocks.dart   # Firebase service mocks
├── features/
│   ├── dsp/
│   │   ├── services/         # Unit tests for services
│   │   └── widgets/          # Widget tests
│   ├── community/
│   └── ...
integration_test/             # End-to-end tests
```

## Unit Tests

Test individual functions and classes in isolation.

### Example: Testing a Service

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import '../../utils/test_data.dart';

void main() {
  group('PointsService', () {
    late MockPointsService service;

    setUp(() {
      service = MockPointsService();
    });

    test('awardPoints creates point record', () async {
      // Arrange
      const userId = TestData.userId1;
      
      when(service.awardPoints(
        userId: userId,
        activityType: 'message_sent',
        points: 1,
      )).thenAnswer((_) async => {});

      // Act
      await service.awardPoints(
        userId: userId,
        activityType: 'message_sent',
        points: 1,
      );

      // Assert
      verify(service.awardPoints(
        userId: userId,
        activityType: 'message_sent',
        points: 1,
      )).called(1);
    });
  });
}
```

### Best Practices

✅ **DO:**
- Use descriptive test names
- Follow Arrange-Act-Assert pattern
- Test one thing per test
- Use test data generators from `test_data.dart`

❌ **DON'T:**
- Make tests depend on other tests
- Use real Firebase in unit tests
- Test implementation details
- Write flaky tests

## Widget Tests

Test UI components and user interactions.

### Example: Testing a Widget

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('Button displays and responds to tap', (tester) async {
    int tapCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ElevatedButton(
            onPressed: () => tapCount++,
            child: const Text('Tap Me'),
          ),
        ),
      ),
    );

    // Verify button exists
    expect(find.text('Tap Me'), findsOneWidget);

    // Tap button
    await tester.tap(find.text('Tap Me'));
    await tester.pump();

    // Verify action occurred
    expect(tapCount, equals(1));
  });
}
```

### Common Finders

```dart
find.text('Hello')           // Find by text
find.byType(ElevatedButton)  // Find by widget type
find.byKey(Key('my-key'))    // Find by key
find.byIcon(Icons.star)      // Find by icon
```

### Common Actions

```dart
await tester.tap(finder)           // Tap a widget
await tester.enterText(finder, 'text')  // Enter text
await tester.drag(finder, Offset(...))  // Drag
await tester.pump()                // Rebuild once
await tester.pumpAndSettle()       // Wait for animations
```

## Integration Tests

Test complete user flows end-to-end.

### Example: Testing a Flow

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:diaspora_nearby/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Complete auth flow', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Navigate through auth flow
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    // ... test the flow
  });
}
```

## Mocking

### Using Test Utilities

```dart
import '../../utils/mock_providers.dart';
import '../../utils/test_data.dart';

// Create test container with mocks
final container = createTestContainer(
  authRepository: mockAuthRepository,
  pointsService: mockPointsService,
);

// Use test data
final profile = TestData.createProfile(
  displayName: 'Test User',
);
```

### Mocking Firebase

For Firebase services, use the mocks in `test/utils/firebase_mocks.dart`:

```dart
import '../../utils/firebase_mocks.dart';

// Mock Firestore
final mockFirestore = MockFirebaseFirestore();

// Mock Auth
final mockAuth = MockFirebaseAuth();
```

## CI/CD Integration

Tests run automatically in CI pipeline (see `.github/workflows/ci.yml`):

- ✅ All tests must pass before PR merge
- ✅ Code coverage is tracked
- ✅ Formatting is checked

## Coverage Goals

- **Services**: 80%+ coverage
- **Repositories**: 70%+ coverage
- **Widgets**: 60%+ coverage
- **Overall**: 70%+ coverage

## Tips for Writing Good Tests

### 1. Test Behavior, Not Implementation
```dart
// ❌ Bad - tests internal implementation
test('uses correct variable name', () {
  expect(service.internalCounter, equals(5));
});

// ✅ Good - tests observable behavior
test('increments counter correctly', () {
  expect(service.getCount(), equals(5));
});
```

### 2. Use Descriptive Names
```dart
// ❌ Bad
test('test1', () { ... });

// ✅ Good
test('awardPoints increases user balance by correct amount', () { ... });
```

### 3. Keep Tests Focused
```dart
// ❌ Bad - tests multiple things
test('profile works', () {
  expect(profile.name, equals('John'));
  expect(profile.email, equals('john@example.com'));
  expect(profile.isVerified, isTrue);
});

// ✅ Good - one assertion per test
test('profile has correct name', () {
  expect(profile.name, equals('John'));
});
```

## Resources

- [Flutter Testing Guide](https://docs.flutter.dev/testing)
- [Mockito Documentation](https://pub.dev/packages/mockito)
- [Integration Testing](https://docs.flutter.dev/testing/integration-tests)

## Getting Help

If you have questions about testing:
- Check existing tests for examples
- Review this guide
- Ask in team chat
