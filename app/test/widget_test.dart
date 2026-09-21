import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:room_booking_app/config/api_config.dart';
import 'package:room_booking_app/main.dart';

void main() {
  // The sign in screen reads remembered-email preferences as soon as it opens,
  // so the plugin needs an in-memory backing store under test.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('app starts on the welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RoomBookingApp());

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'SIGN IN'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'SIGN UP'), findsOneWidget);
  });

  testWidgets('sign in button opens the sign in screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RoomBookingApp());

    await tester.tap(find.widgetWithText(ElevatedButton, 'SIGN IN'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsNothing);
  });

  group('ApiConfig.resolveUrl', () {
    test('prefixes a relative path with the configured base URL', () {
      expect(
        ApiConfig.resolveUrl('/uploads/room.jpg'),
        '${ApiConfig.baseUrl}/uploads/room.jpg',
      );
    });

    test('inserts a separator when the path has no leading slash', () {
      expect(
        ApiConfig.resolveUrl('uploads/room.jpg'),
        '${ApiConfig.baseUrl}/uploads/room.jpg',
      );
    });

    test('passes absolute URLs through untouched', () {
      expect(
        ApiConfig.resolveUrl('https://cdn.example.com/room.jpg'),
        'https://cdn.example.com/room.jpg',
      );
    });

    test('maps an empty path to an empty string', () {
      expect(ApiConfig.resolveUrl(''), '');
    });
  });
}
