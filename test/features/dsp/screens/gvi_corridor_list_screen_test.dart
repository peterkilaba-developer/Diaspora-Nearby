import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/screens/gvi_corridor_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GviCorridorListScreen', () {
    testWidgets(
      'renders home country chambers title and lists 0 GDP corridors',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chamberCorridorsProvider.overrideWith(
                (ref) => Stream.value([
                  {
                    'id': 'chamber_us_tz',
                    'homeCountryCode': 'TZ',
                    'hostCountryCode': 'US',
                    'gdpTotal': 5000,
                    'transactionCount': 12,
                    'memberCount': 25,
                  },
                ]),
              ),
            ],
            child: const MaterialApp(
              home: GviCorridorListScreen(homeCountry: 'Tanzania'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Title should show resolved country name in uppercase
        expect(find.text('TANZANIA Chambers of Commerce'), findsOneWidget);

        // Active corridor US ⇄ TZ with GDP
        expect(find.text('US ⇄ TZ'), findsOneWidget);
        expect(find.text('5K'), findsOneWidget);

        // Corridors with 0 GDP (e.g. KE ⇄ TZ, GB ⇄ TZ, CA ⇄ TZ)
        expect(find.text('0'), findsWidgets);
        expect(find.textContaining('⇄ TZ'), findsWidgets);
      },
    );

    testWidgets('supports search filtering across corridor names and codes', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chamberCorridorsProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: GviCorridorListScreen(homeCountry: 'TZ'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('TANZANIA Chambers of Commerce'), findsOneWidget);

      // Enter search query
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'Kenya');
      await tester.pumpAndSettle();

      expect(find.text('KE ⇄ TZ'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'KE ⇄ TZ'), findsOneWidget);
      // Other non-matching corridors should not be in the list
      expect(find.text('US ⇄ TZ'), findsNothing);
    });
  });
}
