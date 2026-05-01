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
  const RuleFatal({required this.ruleName, required this.userMessage});
  // ruleName goes to Supabase log — never displayed to the enumerator
  final String ruleName;
  // userMessage is the plain-English string shown in the error view
  final String userMessage;
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
