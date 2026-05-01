import 'package:flutter/foundation.dart';

sealed class RuleOutcome {
  const RuleOutcome();
}

@immutable
class RulePassed extends RuleOutcome {
  const RulePassed();
}

@immutable
class RuleFatal extends RuleOutcome {
  const RuleFatal({
    required this.ruleName,
    required this.userMessage,
    this.computedChecksum,
  });
  // ruleName goes to Supabase log — never displayed to the enumerator
  final String ruleName;
  // userMessage is the plain-English string shown in the error view
  final String userMessage;
  // populated by R1 so the Supabase row carries the computed MD5 for triage
  final String? computedChecksum;
}

@immutable
class RuleWarning extends RuleOutcome {
  const RuleWarning({required this.userMessage});
  final String userMessage;
}

// ignore: one_member_abstracts
abstract class ShapefileValidationRule {
  const ShapefileValidationRule();
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  );
}
