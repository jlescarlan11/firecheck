import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tl')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'FireCheck'**
  String get appTitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @assignmentProgress.
  ///
  /// In en, this message translates to:
  /// **'Assignment progress'**
  String get assignmentProgress;

  /// No description provided for @featuresLabel.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} features'**
  String featuresLabel(int completed, int total);

  /// No description provided for @jobCountsLabel.
  ///
  /// In en, this message translates to:
  /// **'{queued} queued · {failed} failed · {dead} dead'**
  String jobCountsLabel(int queued, int failed, int dead);

  /// No description provided for @gatherData.
  ///
  /// In en, this message translates to:
  /// **'Gather Data'**
  String get gatherData;

  /// No description provided for @gatherDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Resume where you left off'**
  String get gatherDataSubtitle;

  /// No description provided for @getMaps.
  ///
  /// In en, this message translates to:
  /// **'Get Maps'**
  String get getMaps;

  /// No description provided for @getMapsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download your assignment'**
  String get getMapsSubtitle;

  /// No description provided for @uploadData.
  ///
  /// In en, this message translates to:
  /// **'Upload Data'**
  String get uploadData;

  /// No description provided for @uploadDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send completed work'**
  String get uploadDataSubtitle;

  /// No description provided for @comingInPhase.
  ///
  /// In en, this message translates to:
  /// **'Coming in {phase}'**
  String comingInPhase(String phase);

  /// No description provided for @getMapsTitle.
  ///
  /// In en, this message translates to:
  /// **'Get Maps'**
  String get getMapsTitle;

  /// No description provided for @getMapsExplainer.
  ///
  /// In en, this message translates to:
  /// **'We\'ll download about {size} of map data and {count} building records. Works best on wifi.'**
  String getMapsExplainer(String size, int count);

  /// No description provided for @startDownload.
  ///
  /// In en, this message translates to:
  /// **'Start download'**
  String get startDownload;

  /// No description provided for @cancelLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLabel;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @fetchingFeatures.
  ///
  /// In en, this message translates to:
  /// **'Fetching buildings…'**
  String get fetchingFeatures;

  /// No description provided for @downloadingTiles.
  ///
  /// In en, this message translates to:
  /// **'Downloading map tiles…'**
  String get downloadingTiles;

  /// No description provided for @readyLabel.
  ///
  /// In en, this message translates to:
  /// **'Ready to gather data'**
  String get readyLabel;

  /// No description provided for @openMap.
  ///
  /// In en, this message translates to:
  /// **'Open map'**
  String get openMap;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @noInternetForGetMaps.
  ///
  /// In en, this message translates to:
  /// **'You need internet to download maps.'**
  String get noInternetForGetMaps;

  /// No description provided for @noAssignmentForEnumerator.
  ///
  /// In en, this message translates to:
  /// **'No assignments assigned to you yet. Contact your supervisor.'**
  String get noAssignmentForEnumerator;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Map download failed.'**
  String get downloadFailed;

  /// No description provided for @mapTitle.
  ///
  /// In en, this message translates to:
  /// **'Gather Data'**
  String get mapTitle;

  /// No description provided for @gpsPermissionOff.
  ///
  /// In en, this message translates to:
  /// **'Location off — tap to enable'**
  String get gpsPermissionOff;

  /// No description provided for @gpsWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS…'**
  String get gpsWaiting;

  /// No description provided for @gpsWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak GPS signal'**
  String get gpsWeak;

  /// No description provided for @offlineBadge.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get offlineBadge;

  /// No description provided for @followMe.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get followMe;

  /// No description provided for @newFeaturePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'+ New Feature (P3)'**
  String get newFeaturePlaceholder;

  /// No description provided for @featureTooFarTitle.
  ///
  /// In en, this message translates to:
  /// **'Feature too far'**
  String get featureTooFarTitle;

  /// No description provided for @featureTooFarBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re {distance}m away. Map policy requires ≤50m.'**
  String featureTooFarBody(int distance);

  /// No description provided for @continueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get continueAnyway;

  /// No description provided for @metersAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} m away'**
  String metersAway(int distance);

  /// No description provided for @phase2FormNote.
  ///
  /// In en, this message translates to:
  /// **'Form coming in Phase 2 — the full attribution form will open from this sheet.'**
  String get phase2FormNote;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @statusUnfilled.
  ///
  /// In en, this message translates to:
  /// **'Unfilled'**
  String get statusUnfilled;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get statusInProgress;

  /// No description provided for @statusComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get statusComplete;

  /// No description provided for @statusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get statusNew;

  /// No description provided for @featureTypeBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get featureTypeBuilding;

  /// No description provided for @featureTypeRoad.
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get featureTypeRoad;

  /// No description provided for @submissionDetailTitleBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get submissionDetailTitleBuilding;

  /// No description provided for @submissionDetailTitleRoad.
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get submissionDetailTitleRoad;

  /// No description provided for @tabStructure.
  ///
  /// In en, this message translates to:
  /// **'Structure {n}'**
  String tabStructure(int n);

  /// No description provided for @tabSoftCapTooltip.
  ///
  /// In en, this message translates to:
  /// **'This polygon already has 5 structures'**
  String get tabSoftCapTooltip;

  /// No description provided for @savedAgo.
  ///
  /// In en, this message translates to:
  /// **'✓ Saved {seconds} seconds ago · {connectivity}'**
  String savedAgo(int seconds, String connectivity);

  /// No description provided for @savedJustNow.
  ///
  /// In en, this message translates to:
  /// **'✓ Saved just now · {connectivity}'**
  String savedJustNow(String connectivity);

  /// No description provided for @photosLabel.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photosLabel;

  /// No description provided for @photosRequiredBadge.
  ///
  /// In en, this message translates to:
  /// **'0 / 1 required'**
  String get photosRequiredBadge;

  /// No description provided for @photosCompleteBadge.
  ///
  /// In en, this message translates to:
  /// **'1+ ✓'**
  String get photosCompleteBadge;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'+ Photo'**
  String get addPhoto;

  /// No description provided for @deletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get deletePhoto;

  /// No description provided for @deletePhotoConfirm.
  ///
  /// In en, this message translates to:
  /// **'This photo will be removed from the device.'**
  String get deletePhotoConfirm;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @doesNotExistTitle.
  ///
  /// In en, this message translates to:
  /// **'This building does not exist'**
  String get doesNotExistTitle;

  /// No description provided for @doesNotExistTitleRoad.
  ///
  /// In en, this message translates to:
  /// **'This road does not exist'**
  String get doesNotExistTitleRoad;

  /// No description provided for @doesNotExistHelper.
  ///
  /// In en, this message translates to:
  /// **'Photo still required to confirm'**
  String get doesNotExistHelper;

  /// No description provided for @sectionIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get sectionIdentity;

  /// No description provided for @sectionConstruction.
  ///
  /// In en, this message translates to:
  /// **'Construction'**
  String get sectionConstruction;

  /// No description provided for @sectionCost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get sectionCost;

  /// No description provided for @sectionFireFighting.
  ///
  /// In en, this message translates to:
  /// **'Fire-fighting facilities'**
  String get sectionFireFighting;

  /// No description provided for @sectionFireLoad.
  ///
  /// In en, this message translates to:
  /// **'Fire load *'**
  String get sectionFireLoad;

  /// No description provided for @fieldCbmsId.
  ///
  /// In en, this message translates to:
  /// **'CBMS ID (optional)'**
  String get fieldCbmsId;

  /// No description provided for @fieldBuildingName.
  ///
  /// In en, this message translates to:
  /// **'Building name *'**
  String get fieldBuildingName;

  /// No description provided for @fieldRa9514Type.
  ///
  /// In en, this message translates to:
  /// **'Type — RA 9514 *'**
  String get fieldRa9514Type;

  /// No description provided for @fieldStoreys.
  ///
  /// In en, this message translates to:
  /// **'Storeys *'**
  String get fieldStoreys;

  /// No description provided for @fieldMaterial.
  ///
  /// In en, this message translates to:
  /// **'Wall material *'**
  String get fieldMaterial;

  /// No description provided for @fieldCostExact.
  ///
  /// In en, this message translates to:
  /// **'Exact amount'**
  String get fieldCostExact;

  /// No description provided for @fieldCostRange.
  ///
  /// In en, this message translates to:
  /// **'Estimated range'**
  String get fieldCostRange;

  /// No description provided for @fieldCostExactInput.
  ///
  /// In en, this message translates to:
  /// **'Amount (₱) *'**
  String get fieldCostExactInput;

  /// No description provided for @fieldCostRangeInput.
  ///
  /// In en, this message translates to:
  /// **'Range *'**
  String get fieldCostRangeInput;

  /// No description provided for @costRangeUnder100k.
  ///
  /// In en, this message translates to:
  /// **'<₱100k'**
  String get costRangeUnder100k;

  /// No description provided for @costRange100to500k.
  ///
  /// In en, this message translates to:
  /// **'₱100k – ₱500k'**
  String get costRange100to500k;

  /// No description provided for @costRange500kto1M.
  ///
  /// In en, this message translates to:
  /// **'₱500k – ₱1M'**
  String get costRange500kto1M;

  /// No description provided for @costRange1to5M.
  ///
  /// In en, this message translates to:
  /// **'₱1M – ₱5M'**
  String get costRange1to5M;

  /// No description provided for @costRange5to10M.
  ///
  /// In en, this message translates to:
  /// **'₱5M – ₱10M'**
  String get costRange5to10M;

  /// No description provided for @costRangeOver10M.
  ///
  /// In en, this message translates to:
  /// **'>₱10M'**
  String get costRangeOver10M;

  /// No description provided for @ffExtinguisher.
  ///
  /// In en, this message translates to:
  /// **'Extinguisher'**
  String get ffExtinguisher;

  /// No description provided for @ffSprinkler.
  ///
  /// In en, this message translates to:
  /// **'Sprinkler'**
  String get ffSprinkler;

  /// No description provided for @ffHose.
  ///
  /// In en, this message translates to:
  /// **'Hose'**
  String get ffHose;

  /// No description provided for @ffSmokeAlarm.
  ///
  /// In en, this message translates to:
  /// **'Smoke alarm'**
  String get ffSmokeAlarm;

  /// No description provided for @ffNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get ffNone;

  /// No description provided for @fireLoadWoodFurniture.
  ///
  /// In en, this message translates to:
  /// **'Wood furniture'**
  String get fireLoadWoodFurniture;

  /// No description provided for @fireLoadFabric.
  ///
  /// In en, this message translates to:
  /// **'Fabric'**
  String get fireLoadFabric;

  /// No description provided for @fireLoadPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get fireLoadPaper;

  /// No description provided for @fireLoadChemicals.
  ///
  /// In en, this message translates to:
  /// **'Chemicals'**
  String get fireLoadChemicals;

  /// No description provided for @fireLoadCookingGas.
  ///
  /// In en, this message translates to:
  /// **'Cooking gas'**
  String get fireLoadCookingGas;

  /// No description provided for @fireLoadOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get fireLoadOther;

  /// No description provided for @materialConcrete.
  ///
  /// In en, this message translates to:
  /// **'Concrete'**
  String get materialConcrete;

  /// No description provided for @materialWood.
  ///
  /// In en, this message translates to:
  /// **'Wood'**
  String get materialWood;

  /// No description provided for @materialMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get materialMixed;

  /// No description provided for @materialLight.
  ///
  /// In en, this message translates to:
  /// **'Light materials'**
  String get materialLight;

  /// No description provided for @materialSteel.
  ///
  /// In en, this message translates to:
  /// **'Steel'**
  String get materialSteel;

  /// No description provided for @materialOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get materialOther;

  /// No description provided for @ra9514GroupA.
  ///
  /// In en, this message translates to:
  /// **'Group A · Residential'**
  String get ra9514GroupA;

  /// No description provided for @ra9514GroupB.
  ///
  /// In en, this message translates to:
  /// **'Group B · Residential / Hotel'**
  String get ra9514GroupB;

  /// No description provided for @ra9514GroupC.
  ///
  /// In en, this message translates to:
  /// **'Group C · Educational'**
  String get ra9514GroupC;

  /// No description provided for @ra9514GroupD.
  ///
  /// In en, this message translates to:
  /// **'Group D · Institutional'**
  String get ra9514GroupD;

  /// No description provided for @ra9514GroupE.
  ///
  /// In en, this message translates to:
  /// **'Group E · Business'**
  String get ra9514GroupE;

  /// No description provided for @ra9514GroupF.
  ///
  /// In en, this message translates to:
  /// **'Group F · Mercantile'**
  String get ra9514GroupF;

  /// No description provided for @ra9514GroupG.
  ///
  /// In en, this message translates to:
  /// **'Group G · Industrial'**
  String get ra9514GroupG;

  /// No description provided for @ra9514GroupH.
  ///
  /// In en, this message translates to:
  /// **'Group H · Storage'**
  String get ra9514GroupH;

  /// No description provided for @ra9514GroupI.
  ///
  /// In en, this message translates to:
  /// **'Group I · Hazardous'**
  String get ra9514GroupI;

  /// No description provided for @ra9514GroupJ.
  ///
  /// In en, this message translates to:
  /// **'Group J · Miscellaneous'**
  String get ra9514GroupJ;

  /// No description provided for @doneButton.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneButton;

  /// No description provided for @footerStatusReady.
  ///
  /// In en, this message translates to:
  /// **'All required fields filled · ready'**
  String get footerStatusReady;

  /// No description provided for @footerStatusPhotoRequired.
  ///
  /// In en, this message translates to:
  /// **'Photo required to mark complete'**
  String get footerStatusPhotoRequired;

  /// No description provided for @footerStatusFieldsMissing.
  ///
  /// In en, this message translates to:
  /// **'Required fields missing'**
  String get footerStatusFieldsMissing;

  /// No description provided for @overrideTitle.
  ///
  /// In en, this message translates to:
  /// **'Override required'**
  String get overrideTitle;

  /// No description provided for @overrideBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re {distance}m away. Map policy requires ≤50m. Why are you submitting from this distance?'**
  String overrideBody(int distance);

  /// No description provided for @overrideReasonHint.
  ///
  /// In en, this message translates to:
  /// **'polygon misplaced · couldn\'t approach safely · unable to verify on foot'**
  String get overrideReasonHint;

  /// No description provided for @overrideContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get overrideContinue;

  /// No description provided for @storeysWarningTooTall.
  ///
  /// In en, this message translates to:
  /// **'That\'s very tall — confirm?'**
  String get storeysWarningTooTall;

  /// No description provided for @errorRequiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get errorRequiredField;

  /// No description provided for @cameraPermissionSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Enable camera permission to take photos'**
  String get cameraPermissionSnackbar;

  /// No description provided for @savedFailedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Retrying…'**
  String get savedFailedSnackbar;

  /// No description provided for @gpsWaitingSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS fix…'**
  String get gpsWaitingSnackbar;

  /// No description provided for @sectionRoadIdentity.
  ///
  /// In en, this message translates to:
  /// **'Road identity'**
  String get sectionRoadIdentity;

  /// No description provided for @sectionRoadDimensions.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get sectionRoadDimensions;

  /// No description provided for @sectionRoadFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get sectionRoadFeatures;

  /// No description provided for @fieldRoadName.
  ///
  /// In en, this message translates to:
  /// **'Road name'**
  String get fieldRoadName;

  /// No description provided for @fieldIsBridge.
  ///
  /// In en, this message translates to:
  /// **'This is a bridge'**
  String get fieldIsBridge;

  /// No description provided for @fieldWidthMeters.
  ///
  /// In en, this message translates to:
  /// **'Width (m)'**
  String get fieldWidthMeters;

  /// No description provided for @widthMetersUnusual.
  ///
  /// In en, this message translates to:
  /// **'Width over 30 m looks unusual'**
  String get widthMetersUnusual;

  /// No description provided for @roadFeatureVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendor stalls'**
  String get roadFeatureVendor;

  /// No description provided for @roadFeaturePedestrian.
  ///
  /// In en, this message translates to:
  /// **'Pedestrian'**
  String get roadFeaturePedestrian;

  /// No description provided for @roadFeatureParking.
  ///
  /// In en, this message translates to:
  /// **'Parking'**
  String get roadFeatureParking;

  /// No description provided for @roadFeatureOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get roadFeatureOthers;

  /// No description provided for @roadFeatureOthersDescription.
  ///
  /// In en, this message translates to:
  /// **'Describe other features'**
  String get roadFeatureOthersDescription;

  /// No description provided for @addModeBannerHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press the map to add a building or road. Tap the pill again to cancel.'**
  String get addModeBannerHint;

  /// No description provided for @addModePillActiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Tap & hold to drop pin'**
  String get addModePillActiveLabel;

  /// No description provided for @outsideBoundarySnackbar.
  ///
  /// In en, this message translates to:
  /// **'Long-press is outside your assignment area'**
  String get outsideBoundarySnackbar;

  /// No description provided for @pickFeatureTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'What did you find?'**
  String get pickFeatureTypeTitle;

  /// No description provided for @pickFeatureTypeBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get pickFeatureTypeBuilding;

  /// No description provided for @pickFeatureTypeRoad.
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get pickFeatureTypeRoad;

  /// No description provided for @featureNotFound.
  ///
  /// In en, this message translates to:
  /// **'Feature not found'**
  String get featureNotFound;

  /// No description provided for @olpSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'OLP household survey · Optional'**
  String get olpSectionTitle;

  /// No description provided for @olpSectionA.
  ///
  /// In en, this message translates to:
  /// **'Construction details (descriptive)'**
  String get olpSectionA;

  /// No description provided for @olpSectionB.
  ///
  /// In en, this message translates to:
  /// **'Kaayusan ng Tahanan'**
  String get olpSectionB;

  /// No description provided for @olpSectionC.
  ///
  /// In en, this message translates to:
  /// **'Koneksyong Elektrikal'**
  String get olpSectionC;

  /// No description provided for @olpSectionD.
  ///
  /// In en, this message translates to:
  /// **'Kusina'**
  String get olpSectionD;

  /// No description provided for @olpSectionE.
  ///
  /// In en, this message translates to:
  /// **'Daanan o Labasan sa Bahay'**
  String get olpSectionE;

  /// No description provided for @olpDisclaimerVoluntary.
  ///
  /// In en, this message translates to:
  /// **'This survey is voluntary, not mandatory.'**
  String get olpDisclaimerVoluntary;

  /// No description provided for @olpDisclaimerSurveyorRole.
  ///
  /// In en, this message translates to:
  /// **'The surveyor is a guide, not an enforcer.'**
  String get olpDisclaimerSurveyorRole;

  /// No description provided for @olpDisclaimerNoSelling.
  ///
  /// In en, this message translates to:
  /// **'The surveyor cannot sell or recommend fire extinguishers.'**
  String get olpDisclaimerNoSelling;

  /// No description provided for @olpHomeownerAgreesLabel.
  ///
  /// In en, this message translates to:
  /// **'Homeowner agrees'**
  String get olpHomeownerAgreesLabel;

  /// No description provided for @olpScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get olpScoreLabel;

  /// No description provided for @olpScoreFraction.
  ///
  /// In en, this message translates to:
  /// **'{score} / {max}'**
  String olpScoreFraction(Object score, Object max);

  /// No description provided for @olpViewBreakdown.
  ///
  /// In en, this message translates to:
  /// **'View breakdown →'**
  String get olpViewBreakdown;

  /// No description provided for @olpMarkComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark survey complete'**
  String get olpMarkComplete;

  /// No description provided for @olpAcknowledgmentRequiredTooltip.
  ///
  /// In en, this message translates to:
  /// **'Homeowner must agree first'**
  String get olpAcknowledgmentRequiredTooltip;

  /// No description provided for @olpResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Survey result'**
  String get olpResultTitle;

  /// No description provided for @olpResultSurveyComplete.
  ///
  /// In en, this message translates to:
  /// **'Survey complete'**
  String get olpResultSurveyComplete;

  /// No description provided for @olpClassLigtas.
  ///
  /// In en, this message translates to:
  /// **'Ligtas ang Iyong Tahanan'**
  String get olpClassLigtas;

  /// No description provided for @olpClassMayroong.
  ///
  /// In en, this message translates to:
  /// **'Mayroong Dapat Ipangamba'**
  String get olpClassMayroong;

  /// No description provided for @olpClassLabis.
  ///
  /// In en, this message translates to:
  /// **'Labis na Mapanganib'**
  String get olpClassLabis;

  /// No description provided for @olpElementRoof.
  ///
  /// In en, this message translates to:
  /// **'Roof'**
  String get olpElementRoof;

  /// No description provided for @olpElementCeiling.
  ///
  /// In en, this message translates to:
  /// **'Ceiling'**
  String get olpElementCeiling;

  /// No description provided for @olpElementRoomPartitions.
  ///
  /// In en, this message translates to:
  /// **'Room partitions'**
  String get olpElementRoomPartitions;

  /// No description provided for @olpElementTrusses.
  ///
  /// In en, this message translates to:
  /// **'Trusses'**
  String get olpElementTrusses;

  /// No description provided for @olpElementWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get olpElementWindows;

  /// No description provided for @olpElementCorridorWalls.
  ///
  /// In en, this message translates to:
  /// **'Corridor walls'**
  String get olpElementCorridorWalls;

  /// No description provided for @olpElementColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get olpElementColumns;

  /// No description provided for @olpElementMainDoor.
  ///
  /// In en, this message translates to:
  /// **'Main door'**
  String get olpElementMainDoor;

  /// No description provided for @olpElementExteriorWall.
  ///
  /// In en, this message translates to:
  /// **'Exterior wall'**
  String get olpElementExteriorWall;

  /// No description provided for @olpElementBeams.
  ///
  /// In en, this message translates to:
  /// **'Beams'**
  String get olpElementBeams;

  /// No description provided for @olpMaterialKahoy.
  ///
  /// In en, this message translates to:
  /// **'Wood'**
  String get olpMaterialKahoy;

  /// No description provided for @olpMaterialSemento.
  ///
  /// In en, this message translates to:
  /// **'Concrete'**
  String get olpMaterialSemento;

  /// No description provided for @olpMaterialBakal.
  ///
  /// In en, this message translates to:
  /// **'Steel'**
  String get olpMaterialBakal;

  /// No description provided for @olpMaterialOthers.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get olpMaterialOthers;

  /// No description provided for @olpMaterialOthersHint.
  ///
  /// In en, this message translates to:
  /// **'Specify other material'**
  String get olpMaterialOthersHint;

  /// No description provided for @olpItemB01Statement.
  ///
  /// In en, this message translates to:
  /// **'No accumulated trash inside the home'**
  String get olpItemB01Statement;

  /// No description provided for @olpItemB01Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Dispose of trash in proper bins daily'**
  String get olpItemB01Suggestion;

  /// No description provided for @olpItemB02Statement.
  ///
  /// In en, this message translates to:
  /// **'No deep-stored materials in walkways'**
  String get olpItemB02Statement;

  /// No description provided for @olpItemB02Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Move items to separate storage to keep walkways clear'**
  String get olpItemB02Suggestion;

  /// No description provided for @olpItemB03Statement.
  ///
  /// In en, this message translates to:
  /// **'Clothes are not piled on the bed'**
  String get olpItemB03Statement;

  /// No description provided for @olpItemB03Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Store clothes in a closet or cabinet'**
  String get olpItemB03Suggestion;

  /// No description provided for @olpItemB04Statement.
  ///
  /// In en, this message translates to:
  /// **'Kitchen items are arranged properly'**
  String get olpItemB04Statement;

  /// No description provided for @olpItemB04Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Add a rack or shelf for kitchen utensils'**
  String get olpItemB04Suggestion;

  /// No description provided for @olpItemB05Statement.
  ///
  /// In en, this message translates to:
  /// **'Doorways are not blocked'**
  String get olpItemB05Statement;

  /// No description provided for @olpItemB05Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Move items blocking doorways'**
  String get olpItemB05Suggestion;

  /// No description provided for @olpItemB06Statement.
  ///
  /// In en, this message translates to:
  /// **'Windows are not stuck or sealed shut'**
  String get olpItemB06Statement;

  /// No description provided for @olpItemB06Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Inspect and repair windows so they open easily'**
  String get olpItemB06Suggestion;

  /// No description provided for @olpItemB07Statement.
  ///
  /// In en, this message translates to:
  /// **'No piles of paper or cardboard inside'**
  String get olpItemB07Statement;

  /// No description provided for @olpItemB07Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Recycle or dispose of old paper and cardboard'**
  String get olpItemB07Suggestion;

  /// No description provided for @olpItemB08Statement.
  ///
  /// In en, this message translates to:
  /// **'Long-stored items are properly stored'**
  String get olpItemB08Statement;

  /// No description provided for @olpItemB08Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Use cabinets or storage boxes'**
  String get olpItemB08Suggestion;

  /// No description provided for @olpItemB09Statement.
  ///
  /// In en, this message translates to:
  /// **'No trash material under the house'**
  String get olpItemB09Statement;

  /// No description provided for @olpItemB09Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Clean under the house regularly'**
  String get olpItemB09Suggestion;

  /// No description provided for @olpItemB10Statement.
  ///
  /// In en, this message translates to:
  /// **'There is a designated trash container'**
  String get olpItemB10Statement;

  /// No description provided for @olpItemB10Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Place a trash container outside the house'**
  String get olpItemB10Suggestion;

  /// No description provided for @olpItemB11Statement.
  ///
  /// In en, this message translates to:
  /// **'No cardboard or items piled inside cabinets'**
  String get olpItemB11Statement;

  /// No description provided for @olpItemB11Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Organize items inside cabinets'**
  String get olpItemB11Suggestion;

  /// No description provided for @olpItemB12Statement.
  ///
  /// In en, this message translates to:
  /// **'The LPG tank has a rubber hose'**
  String get olpItemB12Statement;

  /// No description provided for @olpItemB12Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Buy a rubber hose for the LPG tank'**
  String get olpItemB12Suggestion;

  /// No description provided for @olpItemB13Statement.
  ///
  /// In en, this message translates to:
  /// **'Fire prevention is properly prepared'**
  String get olpItemB13Statement;

  /// No description provided for @olpItemB13Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Check fire prevention measures'**
  String get olpItemB13Suggestion;

  /// No description provided for @olpItemB14Statement.
  ///
  /// In en, this message translates to:
  /// **'No bottles of alcohol or paint stored in the room'**
  String get olpItemB14Statement;

  /// No description provided for @olpItemB14Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Move flammable liquids out of the room'**
  String get olpItemB14Suggestion;

  /// No description provided for @olpItemB15Statement.
  ///
  /// In en, this message translates to:
  /// **'There is a posted evacuation plan in case of fire'**
  String get olpItemB15Statement;

  /// No description provided for @olpItemB15Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Create and post an evacuation plan'**
  String get olpItemB15Suggestion;

  /// No description provided for @olpItemC10Statement.
  ///
  /// In en, this message translates to:
  /// **'There is a circuit breaker'**
  String get olpItemC10Statement;

  /// No description provided for @olpItemC10Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install a circuit breaker on the main electrical line'**
  String get olpItemC10Suggestion;

  /// No description provided for @olpItemC11Statement.
  ///
  /// In en, this message translates to:
  /// **'The electrical panel has a cover'**
  String get olpItemC11Statement;

  /// No description provided for @olpItemC11Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install a cover on the electrical panel'**
  String get olpItemC11Suggestion;

  /// No description provided for @olpItemC12Statement.
  ///
  /// In en, this message translates to:
  /// **'Junction boxes have covers'**
  String get olpItemC12Statement;

  /// No description provided for @olpItemC12Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install covers on all junction boxes'**
  String get olpItemC12Suggestion;

  /// No description provided for @olpItemC13Statement.
  ///
  /// In en, this message translates to:
  /// **'Outlets have covers'**
  String get olpItemC13Statement;

  /// No description provided for @olpItemC13Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install covers on all outlets'**
  String get olpItemC13Suggestion;

  /// No description provided for @olpItemC14Statement.
  ///
  /// In en, this message translates to:
  /// **'Switches have covers'**
  String get olpItemC14Statement;

  /// No description provided for @olpItemC14Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install covers on all switches'**
  String get olpItemC14Suggestion;

  /// No description provided for @olpItemC15Statement.
  ///
  /// In en, this message translates to:
  /// **'Extension cords are used properly'**
  String get olpItemC15Statement;

  /// No description provided for @olpItemC15Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Avoid overloading extension cords'**
  String get olpItemC15Suggestion;

  /// No description provided for @olpItemC16Statement.
  ///
  /// In en, this message translates to:
  /// **'No exposed electrical wires'**
  String get olpItemC16Statement;

  /// No description provided for @olpItemC16Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Cover all exposed wires'**
  String get olpItemC16Suggestion;

  /// No description provided for @olpItemC17Statement.
  ///
  /// In en, this message translates to:
  /// **'Outlets and switches are in good condition'**
  String get olpItemC17Statement;

  /// No description provided for @olpItemC17Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Replace damaged outlets and switches'**
  String get olpItemC17Suggestion;

  /// No description provided for @olpItemC18Statement.
  ///
  /// In en, this message translates to:
  /// **'Correct wire gauge is used'**
  String get olpItemC18Statement;

  /// No description provided for @olpItemC18Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Consult an electrician for the correct gauge'**
  String get olpItemC18Suggestion;

  /// No description provided for @olpItemD25Statement.
  ///
  /// In en, this message translates to:
  /// **'No water leaks in the kitchen'**
  String get olpItemD25Statement;

  /// No description provided for @olpItemD25Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Repair leaking pipes'**
  String get olpItemD25Suggestion;

  /// No description provided for @olpItemD26Statement.
  ///
  /// In en, this message translates to:
  /// **'No flammable items near the stove'**
  String get olpItemD26Statement;

  /// No description provided for @olpItemD26Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Move flammable items away from the stove'**
  String get olpItemD26Suggestion;

  /// No description provided for @olpItemD27Statement.
  ///
  /// In en, this message translates to:
  /// **'Kitchen equipment is regularly inspected'**
  String get olpItemD27Statement;

  /// No description provided for @olpItemD27Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Conduct weekly checks of stove and LPG'**
  String get olpItemD27Suggestion;

  /// No description provided for @olpItemD28Statement.
  ///
  /// In en, this message translates to:
  /// **'Sufficient smoke ventilation'**
  String get olpItemD28Statement;

  /// No description provided for @olpItemD28Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install an exhaust or add a window'**
  String get olpItemD28Suggestion;

  /// No description provided for @olpItemD29Statement.
  ///
  /// In en, this message translates to:
  /// **'Candles and lighters stored in proper containers'**
  String get olpItemD29Statement;

  /// No description provided for @olpItemD29Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Designate containers for candles and lighters'**
  String get olpItemD29Suggestion;

  /// No description provided for @olpItemE30Statement.
  ///
  /// In en, this message translates to:
  /// **'Doorways and windows are clear and unblocked'**
  String get olpItemE30Statement;

  /// No description provided for @olpItemE30Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Move items that are blocking'**
  String get olpItemE30Suggestion;

  /// No description provided for @olpItemE31Statement.
  ///
  /// In en, this message translates to:
  /// **'No dry leaves around the house'**
  String get olpItemE31Statement;

  /// No description provided for @olpItemE31Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Clear dry leaves regularly'**
  String get olpItemE31Suggestion;

  /// No description provided for @olpItemE32Statement.
  ///
  /// In en, this message translates to:
  /// **'Easy escape during fire'**
  String get olpItemE32Statement;

  /// No description provided for @olpItemE32Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Practice evacuation with family'**
  String get olpItemE32Suggestion;

  /// No description provided for @olpItemE33Statement.
  ///
  /// In en, this message translates to:
  /// **'The house is close to a road'**
  String get olpItemE33Statement;

  /// No description provided for @olpItemE33Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Ensure easy access to a public road'**
  String get olpItemE33Suggestion;

  /// No description provided for @olpItemE34Statement.
  ///
  /// In en, this message translates to:
  /// **'Interior pathways are well-kept'**
  String get olpItemE34Statement;

  /// No description provided for @olpItemE34Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Clean interior pathways'**
  String get olpItemE34Suggestion;

  /// No description provided for @olpItemE35Statement.
  ///
  /// In en, this message translates to:
  /// **'Adequate interior lighting'**
  String get olpItemE35Statement;

  /// No description provided for @olpItemE35Suggestion.
  ///
  /// In en, this message translates to:
  /// **'Install additional lighting if needed'**
  String get olpItemE35Suggestion;

  /// No description provided for @summaryFeatures.
  ///
  /// In en, this message translates to:
  /// **'{n} features'**
  String summaryFeatures(int n);

  /// No description provided for @summaryComplete.
  ///
  /// In en, this message translates to:
  /// **'{n} complete'**
  String summaryComplete(int n);

  /// No description provided for @summaryIncomplete.
  ///
  /// In en, this message translates to:
  /// **'{n} incomplete'**
  String summaryIncomplete(int n);

  /// No description provided for @summaryNewFeatures.
  ///
  /// In en, this message translates to:
  /// **'{n} new features added'**
  String summaryNewFeatures(int n);

  /// No description provided for @summaryPhotosPending.
  ///
  /// In en, this message translates to:
  /// **'{n} photos pending'**
  String summaryPhotosPending(int n);

  /// No description provided for @failedJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed ({n})'**
  String failedJobsTitle(int n);

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @retryAllButton.
  ///
  /// In en, this message translates to:
  /// **'Retry all'**
  String get retryAllButton;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tl':
      return AppLocalizationsTl();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
