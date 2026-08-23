import 'package:firecheck/core/forms/form_definition.dart';
import 'package:flutter/material.dart';

class ConstraintHints extends StatelessWidget {
  const ConstraintHints({
    required this.definition,
    required this.fieldPrefix,
    super.key,
  });

  final FormDefinition definition;
  final String fieldPrefix;

  @override
  Widget build(BuildContext context) {
    final constraints = definition.constraints
        .where(
          (constraint) =>
              constraint.field.startsWith(fieldPrefix) &&
              constraint.hint?.trim().isNotEmpty == true,
        )
        .toList(growable: false);
    if (constraints.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'Form requirements',
      child: Container(
        key: Key('$fieldPrefix.constraint-hints'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final constraint in constraints)
              Text('• ${constraint.hint!}',
                  key: Key('${constraint.field}.hint')),
          ],
        ),
      ),
    );
  }
}
