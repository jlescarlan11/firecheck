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

  @override
  String get submissionDetailTitleBuilding => 'Gusali';

  @override
  String get submissionDetailTitleRoad => 'Daan';

  @override
  String tabStructure(int n) {
    return 'Istruktura $n';
  }

  @override
  String get tabSoftCapTooltip => 'May 5 nang istruktura ang polygon na ito';

  @override
  String savedAgo(int seconds, String connectivity) {
    return '✓ Naka-save ${seconds}s ang nakalipas · $connectivity';
  }

  @override
  String savedJustNow(String connectivity) {
    return '✓ Naka-save kanina · $connectivity';
  }

  @override
  String get photosLabel => 'Mga larawan';

  @override
  String get photosRequiredBadge => '0 / 1 kailangan';

  @override
  String get photosCompleteBadge => '1+ ✓';

  @override
  String get addPhoto => '+ Larawan';

  @override
  String get deletePhoto => 'Burahin ang larawan?';

  @override
  String get deletePhotoConfirm => 'Maaalis ito sa device.';

  @override
  String get deleteAction => 'Burahin';

  @override
  String get doesNotExistTitle => 'Hindi umiiral ang gusaling ito';

  @override
  String get doesNotExistHelper => 'Kailangan pa rin ng larawan';

  @override
  String get sectionIdentity => 'Pagkakakilanlan';

  @override
  String get sectionConstruction => 'Konstruksyon';

  @override
  String get sectionCost => 'Halaga';

  @override
  String get sectionFireFighting => 'Kagamitang panlaban sa sunog';

  @override
  String get sectionFireLoad => 'Madaling masunog *';

  @override
  String get fieldCbmsId => 'CBMS ID (opsyonal)';

  @override
  String get fieldBuildingName => 'Pangalan ng gusali *';

  @override
  String get fieldRa9514Type => 'Uri — RA 9514 *';

  @override
  String get fieldStoreys => 'Bilang ng palapag *';

  @override
  String get fieldMaterial => 'Materyal ng dingding *';

  @override
  String get fieldCostExact => 'Eksaktong halaga';

  @override
  String get fieldCostRange => 'Tinatayang halaga';

  @override
  String get fieldCostExactInput => 'Halaga (₱) *';

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
  String get ffExtinguisher => 'Pang-apula';

  @override
  String get ffSprinkler => 'Sprinkler';

  @override
  String get ffHose => 'Hose';

  @override
  String get ffSmokeAlarm => 'Smoke alarm';

  @override
  String get ffNone => 'Wala';

  @override
  String get fireLoadWoodFurniture => 'Kahoy na muwebles';

  @override
  String get fireLoadFabric => 'Tela';

  @override
  String get fireLoadPaper => 'Papel';

  @override
  String get fireLoadChemicals => 'Kemikal';

  @override
  String get fireLoadCookingGas => 'Gas pangluto';

  @override
  String get fireLoadOther => 'Iba pa';

  @override
  String get materialConcrete => 'Konkreto';

  @override
  String get materialWood => 'Kahoy';

  @override
  String get materialMixed => 'Pinaghalo';

  @override
  String get materialLight => 'Magagaang materyales';

  @override
  String get materialSteel => 'Bakal';

  @override
  String get materialOther => 'Iba pa';

  @override
  String get ra9514GroupA => 'Grupo A · Tirahan';

  @override
  String get ra9514GroupB => 'Grupo B · Tirahan / Hotel';

  @override
  String get ra9514GroupC => 'Grupo C · Paaralan';

  @override
  String get ra9514GroupD => 'Grupo D · Pampubliko';

  @override
  String get ra9514GroupE => 'Grupo E · Negosyo';

  @override
  String get ra9514GroupF => 'Grupo F · Komersyal';

  @override
  String get ra9514GroupG => 'Grupo G · Industriya';

  @override
  String get ra9514GroupH => 'Grupo H · Imbakan';

  @override
  String get ra9514GroupI => 'Grupo I · Mapanganib';

  @override
  String get ra9514GroupJ => 'Grupo J · Iba pa';

  @override
  String get doneButton => 'Tapos';

  @override
  String get footerStatusReady => 'Lahat ng kailangan ay napunan · handa';

  @override
  String get footerStatusPhotoRequired => 'Kailangan ng larawan';

  @override
  String get footerStatusFieldsMissing => 'May kulang na impormasyon';

  @override
  String get overrideTitle => 'Kailangan ng paliwanag';

  @override
  String overrideBody(int distance) {
    return '${distance}m ang layo mo. Ang patakaran ay ≤50m. Bakit ka mag-su-submit mula sa layong ito?';
  }

  @override
  String get overrideReasonHint =>
      'maling lugar ng polygon · hindi ligtas lumapit · hindi ma-verify nang lakad';

  @override
  String get overrideContinue => 'Ituloy';

  @override
  String get storeysWarningTooTall => 'Sobrang taas — kumpirmahin?';

  @override
  String get errorRequiredField => 'Kailangan';

  @override
  String get cameraPermissionSnackbar =>
      'Buksan ang permiso sa kamera para makakuha ng larawan';

  @override
  String get savedFailedSnackbar => 'Hindi nai-save. Susubukan ulit…';
}
