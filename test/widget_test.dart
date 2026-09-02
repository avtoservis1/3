import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:avtoservis/main.dart';

void main() {
  testWidgets('app builds the material app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
