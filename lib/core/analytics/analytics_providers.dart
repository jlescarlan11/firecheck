import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return kDebugMode
      ? const ConsoleAnalyticsService()
      : const NoopAnalyticsService();
});
