import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Surfaces user-action events for usage tracking. Default production
/// impl is [NoopAnalyticsService]; debug builds use [ConsoleAnalyticsService]
/// for visibility while developing. Test code can override the provider with
/// [RecordingAnalyticsService] to assert on emitted events.
// ignore: one_member_abstracts
abstract class AnalyticsService {
  void track(String event, {Map<String, Object?>? properties});
}

class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  void track(String event, {Map<String, Object?>? properties}) {}
}

class ConsoleAnalyticsService implements AnalyticsService {
  const ConsoleAnalyticsService();

  @override
  void track(String event, {Map<String, Object?>? properties}) {
    final hasProps = properties != null && properties.isNotEmpty;
    final suffix = hasProps ? ' ${jsonEncode(properties)}' : '';
    debugPrint('[analytics] $event$suffix');
  }
}

class RecordingAnalyticsService implements AnalyticsService {
  final List<({String event, Map<String, Object?>? properties})> events = [];

  @override
  void track(String event, {Map<String, Object?>? properties}) {
    events.add((event: event, properties: properties));
  }
}
