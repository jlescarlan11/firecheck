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

  @override
  String get getMapsTitle => 'Get Maps';

  @override
  String getMapsExplainer(String size, int count) {
    return 'We\'ll download about $size of map data and $count building records. Works best on wifi.';
  }

  @override
  String get startDownload => 'Start download';

  @override
  String get cancelLabel => 'Cancel';

  @override
  String get tryAgain => 'Try again';

  @override
  String get fetchingFeatures => 'Fetching buildings…';

  @override
  String get downloadingTiles => 'Downloading map tiles…';

  @override
  String get readyLabel => 'Ready to gather data';

  @override
  String get openMap => 'Open map';

  @override
  String get backToHome => 'Back to home';

  @override
  String get noInternetForGetMaps => 'You need internet to download maps.';

  @override
  String get noAssignmentForEnumerator =>
      'No assignments assigned to you yet. Contact your supervisor.';

  @override
  String get downloadFailed => 'Map download failed.';

  @override
  String get mapTitle => 'Gather Data';

  @override
  String get gpsPermissionOff => 'Location off — tap to enable';

  @override
  String get gpsWaiting => 'Waiting for GPS…';

  @override
  String get gpsWeak => 'Weak GPS signal';

  @override
  String get offlineBadge => 'offline';

  @override
  String get followMe => 'Follow';

  @override
  String get newFeaturePlaceholder => '+ New Feature (P3)';

  @override
  String get featureTooFarTitle => 'Feature too far';

  @override
  String featureTooFarBody(int distance) {
    return 'You\'re ${distance}m away. Map policy requires ≤50m.';
  }

  @override
  String get continueAnyway => 'Continue anyway';

  @override
  String metersAway(int distance) {
    return '$distance m away';
  }

  @override
  String get phase2FormNote =>
      'Form coming in Phase 2 — the full attribution form will open from this sheet.';

  @override
  String get close => 'Close';

  @override
  String get statusUnfilled => 'Unfilled';

  @override
  String get statusInProgress => 'In progress';

  @override
  String get statusComplete => 'Complete';

  @override
  String get statusNew => 'New';

  @override
  String get featureTypeBuilding => 'Building';

  @override
  String get featureTypeRoad => 'Road';
}
