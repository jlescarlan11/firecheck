// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tagalog (`tl`).
class AppLocalizationsTl extends AppLocalizations {
  AppLocalizationsTl([String locale = 'tl']) : super(locale);

  @override
  String get appTitle => 'FireCheck';

  @override
  String get signIn => 'Mag-sign in';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get assignmentProgress => 'Progreso ng takda';

  @override
  String featuresLabel(int completed, int total) {
    return '$completed sa $total na istruktura';
  }

  @override
  String jobCountsLabel(int queued, int failed, int dead) {
    return '$queued nakapila · $failed nabigo · $dead patay';
  }

  @override
  String get gatherData => 'Mangalap ng Datos';

  @override
  String get gatherDataSubtitle => 'Ituloy kung saan ka huling tumigil';

  @override
  String get getMaps => 'Kumuha ng Mapa';

  @override
  String get getMapsSubtitle => 'I-download ang iyong takda';

  @override
  String get uploadData => 'I-upload ang Datos';

  @override
  String get uploadDataSubtitle => 'Ipadala ang tapos na gawa';

  @override
  String comingInPhase(String phase) {
    return 'Darating sa $phase';
  }
}
