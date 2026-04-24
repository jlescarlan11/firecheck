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

  @override
  String get submissionDetailTitleBuilding => 'Building';

  @override
  String get submissionDetailTitleRoad => 'Road';

  @override
  String tabStructure(int n) {
    return 'Structure $n';
  }

  @override
  String get tabSoftCapTooltip => 'This polygon already has 5 structures';

  @override
  String savedAgo(int seconds, String connectivity) {
    return '✓ Saved $seconds seconds ago · $connectivity';
  }

  @override
  String savedJustNow(String connectivity) {
    return '✓ Saved just now · $connectivity';
  }

  @override
  String get photosLabel => 'Photos';

  @override
  String get photosRequiredBadge => '0 / 1 required';

  @override
  String get photosCompleteBadge => '1+ ✓';

  @override
  String get addPhoto => '+ Photo';

  @override
  String get deletePhoto => 'Delete photo?';

  @override
  String get deletePhotoConfirm =>
      'This photo will be removed from the device.';

  @override
  String get deleteAction => 'Delete';

  @override
  String get doesNotExistTitle => 'This building does not exist';

  @override
  String get doesNotExistHelper => 'Photo still required to confirm';

  @override
  String get sectionIdentity => 'Identity';

  @override
  String get sectionConstruction => 'Construction';

  @override
  String get sectionCost => 'Cost';

  @override
  String get sectionFireFighting => 'Fire-fighting facilities';

  @override
  String get sectionFireLoad => 'Fire load *';

  @override
  String get fieldCbmsId => 'CBMS ID (optional)';

  @override
  String get fieldBuildingName => 'Building name *';

  @override
  String get fieldRa9514Type => 'Type — RA 9514 *';

  @override
  String get fieldStoreys => 'Storeys *';

  @override
  String get fieldMaterial => 'Wall material *';

  @override
  String get fieldCostExact => 'Exact amount';

  @override
  String get fieldCostRange => 'Estimated range';

  @override
  String get fieldCostExactInput => 'Amount (₱) *';

  @override
  String get fieldCostRangeInput => 'Range *';

  @override
  String get costRangeUnder100k => '<₱100k';

  @override
  String get costRange100to500k => '₱100k – ₱500k';

  @override
  String get costRange500kto1M => '₱500k – ₱1M';

  @override
  String get costRange1to5M => '₱1M – ₱5M';

  @override
  String get costRange5to10M => '₱5M – ₱10M';

  @override
  String get costRangeOver10M => '>₱10M';

  @override
  String get ffExtinguisher => 'Extinguisher';

  @override
  String get ffSprinkler => 'Sprinkler';

  @override
  String get ffHose => 'Hose';

  @override
  String get ffSmokeAlarm => 'Smoke alarm';

  @override
  String get ffNone => 'None';

  @override
  String get fireLoadWoodFurniture => 'Wood furniture';

  @override
  String get fireLoadFabric => 'Fabric';

  @override
  String get fireLoadPaper => 'Paper';

  @override
  String get fireLoadChemicals => 'Chemicals';

  @override
  String get fireLoadCookingGas => 'Cooking gas';

  @override
  String get fireLoadOther => 'Other';

  @override
  String get materialConcrete => 'Concrete';

  @override
  String get materialWood => 'Wood';

  @override
  String get materialMixed => 'Mixed';

  @override
  String get materialLight => 'Light materials';

  @override
  String get materialSteel => 'Steel';

  @override
  String get materialOther => 'Other';

  @override
  String get ra9514GroupA => 'Group A · Residential';

  @override
  String get ra9514GroupB => 'Group B · Residential / Hotel';

  @override
  String get ra9514GroupC => 'Group C · Educational';

  @override
  String get ra9514GroupD => 'Group D · Institutional';

  @override
  String get ra9514GroupE => 'Group E · Business';

  @override
  String get ra9514GroupF => 'Group F · Mercantile';

  @override
  String get ra9514GroupG => 'Group G · Industrial';

  @override
  String get ra9514GroupH => 'Group H · Storage';

  @override
  String get ra9514GroupI => 'Group I · Hazardous';

  @override
  String get ra9514GroupJ => 'Group J · Miscellaneous';

  @override
  String get doneButton => 'Done';

  @override
  String get footerStatusReady => 'All required fields filled · ready';

  @override
  String get footerStatusPhotoRequired => 'Photo required to mark complete';

  @override
  String get footerStatusFieldsMissing => 'Required fields missing';

  @override
  String get overrideTitle => 'Override required';

  @override
  String overrideBody(int distance) {
    return 'You\'re ${distance}m away. Map policy requires ≤50m. Why are you submitting from this distance?';
  }

  @override
  String get overrideReasonHint =>
      'polygon misplaced · couldn\'t approach safely · unable to verify on foot';

  @override
  String get overrideContinue => 'Continue';

  @override
  String get storeysWarningTooTall => 'That\'s very tall — confirm?';

  @override
  String get errorRequiredField => 'Required';

  @override
  String get cameraPermissionSnackbar =>
      'Enable camera permission to take photos';

  @override
  String get savedFailedSnackbar => 'Couldn\'t save. Retrying…';
}
