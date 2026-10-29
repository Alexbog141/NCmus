import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NCmus smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('NCmus Audio Engine'),
        ),
      ),
    );
    expect(find.text('NCmus Audio Engine'), findsOneWidget);
  });
}
