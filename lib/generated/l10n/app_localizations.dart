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
