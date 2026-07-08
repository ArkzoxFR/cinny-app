import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cinny_app/main.dart';

void main() {
  testWidgets('CinnyApp affiche un indicateur de chargement au démarrage',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CinnyApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
