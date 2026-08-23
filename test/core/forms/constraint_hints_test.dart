import 'package:firecheck/core/forms/constraint_hints.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows only hints for the requested feature type',
      (tester) async {
    const definition = FormDefinition(
      version: 'v2',
      name: 'Rules',
      constraints: [
        FormConstraint(field: 'building.storeys', hint: 'Use whole floors'),
        FormConstraint(field: 'road.widthMeters', hint: 'Measure curb to curb'),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ConstraintHints(
          definition: definition,
          fieldPrefix: 'building.',
        ),
      ),
    );
    expect(find.text('• Use whole floors'), findsOneWidget);
    expect(find.text('• Measure curb to curb'), findsNothing);
  });
}
