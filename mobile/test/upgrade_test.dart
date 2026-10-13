import 'package:dastak/core/models.dart';
import 'package:dastak/core/providers.dart';
import 'package:dastak/core/widgets.dart';
import 'package:dastak/features/addresses/addresses_screen.dart';
import 'package:dastak/features/vendor/vendor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('address composition', () {
    test('composed address round-trips and always meets the server minimum', () {
      final text = composeAddress('H.No 5', 'Sector 3', '', 'Rohtak', '124001');
      expect(text, 'H.No 5, Sector 3, Rohtak - 124001');
      expect(text.trim().length >= 8, isTrue);
      expect(parseAddress(text), {'house': 'H.No 5', 'street': 'Sector 3', 'landmark': '', 'city': 'Rohtak', 'pincode': '124001'});
    });
    test('landmark is preserved and legacy free text is not force-parsed', () {
      final text = composeAddress('12', 'Delhi Road', 'near Tilak Nagar park', 'Rohtak', '124001');
      expect(parseAddress(text)!['landmark'], 'near Tilak Nagar park');
      expect(parseAddress('my home near the park'), isNull);
    });
  });

  group('opening hours', () {
    test('summary lists every weekday and shows overnight slots', () {
      final lines = hoursSummary({
        'weekly': {
          '1': [
            ['18:00', '02:00']
          ]
        }
      });
      expect(lines.length, 7);
      expect(lines.first, 'Mon: 18:00–02:00');
      expect(lines[1], 'Tue: Closed');
    });
    test('unconfigured or foreign-timezone hours never invent an opening time', () {
      expect(nextOpening({}), isNull);
      expect(nextOpening(null), isNull);
      expect(
          nextOpening({
            'timezone': 'Europe/London',
            'weekly': {
              '1': [
                ['09:00', '17:00']
              ]
            }
          }),
          isNull);
    });
    test('a daily schedule always yields a next opening within a week', () {
      final every = {
        'weekly': {
          for (var i = 1; i <= 7; i++)
            '$i': [
              ['09:00', '10:00']
            ]
        }
      };
      expect(nextOpening(every), startsWith('Opens '));
    });
    test('hours editor serialises overnight slots and empty schedules', () {
      final model = HoursModel.from({
        'weekly': {
          '5': [
            ['18:00', '02:00']
          ]
        },
        'holidays': ['2026-10-20']
      });
      final json = model.toJson();
      expect((json['weekly'] as Map)['5'], [
        ['18:00', '02:00']
      ]);
      expect(json['holidays'], ['2026-10-20']);
      expect(json['timezone'], 'Asia/Kolkata');
      expect(HoursModel().toJson(), isEmpty);
    });
  });

  test('rupee entry converts exactly to paise and back', () {
    expect(parsePaise('120'), 12000);
    expect(parsePaise('120.5'), 12050);
    expect(parsePaise('120.50'), 12050);
    expect(parsePaise('0.99'), 99);
    expect(parsePaise('1,250'), 125000);
    expect(parsePaise('12.345'), isNull);
    expect(parsePaise('-5'), isNull);
    expect(parsePaise('abc'), isNull);
    expect(rupeesText(12000), '120');
    expect(rupeesText(12050), '120.50');
    expect(rupeesText(5), '0.05');
    expect(rupeesText(null), '');
  });

  test('CSV export escapes commas, quotes and new lines', () {
    expect(
        csv([
          ['a', 'b,c', 'say "hi"', 'x\ny', null]
        ]),
        'a,"b,c","say ""hi""","x\ny",');
  });

  test('status labels are human readable', () {
    expect(statusLabel('pending_verification'), 'Pending verification');
    expect(statusLabel('out_for_delivery'), 'Out for delivery');
    expect(statusLabel('submitted'), 'Pending verification');
  });

  testWidgets('address form shows inline errors instead of silently failing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)], child: const MaterialApp(home: AddressEditor())));
    await tester.pump();
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(find.text('Please fix the highlighted fields above.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'House / flat / floor no. *'), 'H.No 5');
    await tester.enterText(find.widgetWithText(TextFormField, 'Street, sector or area *'), 'Sector 3');
    await tester.enterText(find.widgetWithText(TextFormField, 'PIN code *'), '124001');
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(find.text('Set the delivery point: tap "Use my current location" or tap the map.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
