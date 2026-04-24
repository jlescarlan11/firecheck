// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FireCheck';

  @override
  String get signIn => 'Sign in';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get assignmentProgress => 'Assignment progress';

  @override
  String featuresLabel(int completed, int total) {
    return '$completed of $total features';
  }

  @override
  String jobCountsLabel(int queued, int failed, int dead) {
    return '$queued queued · $failed failed · $dead dead';
  }

  @override
  String get gatherData => 'Gather Data';

  @override
  String get gatherDataSubtitle => 'Resume where you left off';

  @override
  String get getMaps => 'Get Maps';

  @override
  String get getMapsSubtitle => 'Download your assignment';

  @override
  String get uploadData => 'Upload Data';

  @override
  String get uploadDataSubtitle => 'Send completed work';

  @override
  String comingInPhase(String phase) {
    return 'Coming in $phase';
  }
}
