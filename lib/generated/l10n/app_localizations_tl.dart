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

  @override
  String get getMapsTitle => 'Kumuha ng Mapa';

  @override
  String getMapsExplainer(String size, int count) {
    return 'Mag-dadownload tayo ng humigit-kumulang $size ng datos ng mapa at $count na rekord ng gusali. Mas maganda sa wifi.';
  }

  @override
  String get startDownload => 'Simulan ang pag-download';

  @override
  String get cancelLabel => 'Kanselahin';

  @override
  String get tryAgain => 'Subukan muli';

  @override
  String get fetchingFeatures => 'Kinukuha ang mga gusali…';

  @override
  String get downloadingTiles => 'Dinadownload ang mapa…';

  @override
  String get readyLabel => 'Handa nang mangalap';

  @override
  String get openMap => 'Buksan ang mapa';

  @override
  String get backToHome => 'Bumalik sa home';

  @override
  String get noInternetForGetMaps =>
      'Kailangan mo ng internet para mag-download ng mapa.';

  @override
  String get noAssignmentForEnumerator =>
      'Wala ka pang takda. Kausapin ang iyong supervisor.';

  @override
  String get downloadFailed => 'Nabigo ang pag-download ng mapa.';

  @override
  String get mapTitle => 'Mangalap ng Datos';

  @override
  String get gpsPermissionOff => 'Naka-off ang lokasyon — i-tap para buksan';

  @override
  String get gpsWaiting => 'Hinihintay ang GPS…';

  @override
  String get gpsWeak => 'Mahina ang GPS signal';

  @override
  String get offlineBadge => 'offline';

  @override
  String get followMe => 'Sundan';

  @override
  String get newFeaturePlaceholder => '+ Bagong Feature (P3)';

  @override
  String get featureTooFarTitle => 'Masyadong malayo';

  @override
  String featureTooFarBody(int distance) {
    return '${distance}m ang layo mo. Ang patakaran ay ≤50m lamang.';
  }

  @override
  String get continueAnyway => 'Ituloy pa rin';

  @override
  String metersAway(int distance) {
    return '$distance m ang layo';
  }

  @override
  String get phase2FormNote =>
      'Darating ang form sa Phase 2 — ang buong attribution form ay bubukas mula rito.';

  @override
  String get close => 'Isara';

  @override
  String get statusUnfilled => 'Wala pa';

  @override
  String get statusInProgress => 'Ginagawa pa';

  @override
  String get statusComplete => 'Tapos na';

  @override
  String get statusNew => 'Bago';

  @override
  String get featureTypeBuilding => 'Gusali';

  @override
  String get featureTypeRoad => 'Daan';
}
