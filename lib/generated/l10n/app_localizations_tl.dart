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
  String get doesNotExistTitleRoad => 'Wala ang kalye na ito';

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

  @override
  String get gpsWaitingSnackbar => 'Naghulat og GPS signal…';

  @override
  String get sectionRoadIdentity => 'Pagkakakilanlan ng kalye';

  @override
  String get sectionRoadDimensions => 'Sukat';

  @override
  String get sectionRoadFeatures => 'Mga katangian';

  @override
  String get fieldRoadName => 'Pangalan ng kalye';

  @override
  String get fieldIsBridge => 'Tulay ito';

  @override
  String get fieldWidthMeters => 'Lapad (m)';

  @override
  String get widthMetersUnusual => 'Mukhang malayo masyado ang lapad';

  @override
  String get roadFeatureVendor => 'Mga tindahan';

  @override
  String get roadFeaturePedestrian => 'Para sa naglalakad';

  @override
  String get roadFeatureParking => 'Paradahan';

  @override
  String get roadFeatureOthers => 'Iba pa';

  @override
  String get roadFeatureOthersDescription => 'Ilarawan ang iba pang katangian';

  @override
  String get addModeBannerHint =>
      'Pindutin nang matagal ang mapa upang magdagdag ng gusali o kalye. Pindutin muli ang pill para kanselahin.';

  @override
  String get addModePillActiveLabel => 'Pindutin nang matagal para magdagdag';

  @override
  String get outsideBoundarySnackbar =>
      'Wala sa loob ng iyong nasasakupang lugar';

  @override
  String get pickFeatureTypeTitle => 'Anong nakita mo?';

  @override
  String get pickFeatureTypeBuilding => 'Gusali';

  @override
  String get pickFeatureTypeRoad => 'Kalye';

  @override
  String get featureNotFound => 'Hindi nahanap ang feature';

  @override
  String get olpSectionTitle => 'Survey ng pamilya OLP · Opsyonal';

  @override
  String get olpSectionA => 'Detalye ng konstruksyon (deskriptibo)';

  @override
  String get olpSectionB => 'Kaayusan ng Tahanan';

  @override
  String get olpSectionC => 'Koneksyong Elektrikal';

  @override
  String get olpSectionD => 'Kusina';

  @override
  String get olpSectionE => 'Daanan o Labasan sa Bahay';

  @override
  String get olpDisclaimerVoluntary =>
      'Ang sarbey na ito ay boluntaryo, hindi sapilitan.';

  @override
  String get olpDisclaimerSurveyorRole =>
      'Ang surveyor ay isang gabay, hindi tagapagpatupad.';

  @override
  String get olpDisclaimerNoSelling =>
      'Hindi maaaring magbenta o magrekomenda ng fire extinguisher ang surveyor.';

  @override
  String get olpHomeownerAgreesLabel => 'Pumayag ang nakatira';

  @override
  String get olpScoreLabel => 'Iskor';

  @override
  String olpScoreFraction(Object score, Object max) {
    return '$score / $max';
  }

  @override
  String get olpViewBreakdown => 'Tingnan ang detalye →';

  @override
  String get olpMarkComplete => 'Markahan ang sarbey bilang kompleto';

  @override
  String get olpAcknowledgmentRequiredTooltip =>
      'Kailangan munang pumayag ang nakatira';

  @override
  String get olpResultTitle => 'Resulta ng sarbey';

  @override
  String get olpResultSurveyComplete => 'Kompleto na ang sarbey';

  @override
  String get olpClassLigtas => 'Ligtas ang Iyong Tahanan';

  @override
  String get olpClassMayroong => 'Mayroong Dapat Ipangamba';

  @override
  String get olpClassLabis => 'Labis na Mapanganib';

  @override
  String get olpElementRoof => 'Bubong';

  @override
  String get olpElementCeiling => 'Kisame';

  @override
  String get olpElementRoomPartitions => 'Mga partisyon ng silid';

  @override
  String get olpElementTrusses => 'Mga troso';

  @override
  String get olpElementWindows => 'Mga bintana';

  @override
  String get olpElementCorridorWalls => 'Pader ng pasilyo';

  @override
  String get olpElementColumns => 'Mga haligi';

  @override
  String get olpElementMainDoor => 'Pangunahing pintuan';

  @override
  String get olpElementExteriorWall => 'Panlabas na pader';

  @override
  String get olpElementBeams => 'Mga sako';

  @override
  String get olpMaterialKahoy => 'Kahoy';

  @override
  String get olpMaterialSemento => 'Semento';

  @override
  String get olpMaterialBakal => 'Bakal';

  @override
  String get olpMaterialOthers => 'Iba pa';

  @override
  String get olpMaterialOthersHint => 'Ilarawan ang ibang materyales';

  @override
  String get olpItemB01Statement =>
      'Walang nakatambak na basura sa loob ng bahay';

  @override
  String get olpItemB01Suggestion =>
      'Itapon ang basura sa tamang lalagyan araw-araw';

  @override
  String get olpItemB02Statement =>
      'Walang nakaimbak na malalalim na materyales sa daanan';

  @override
  String get olpItemB02Suggestion =>
      'Ilipat ang mga gamit sa hiwalay na lalagyan upang malinis ang daanan';

  @override
  String get olpItemB03Statement => 'Hindi nakatambak ang mga damit sa kama';

  @override
  String get olpItemB03Suggestion => 'Itago ang damit sa armaryo o cabinet';

  @override
  String get olpItemB04Statement =>
      'Maayos ang pagkakahanay ng mga gamit-pang kusina';

  @override
  String get olpItemB04Suggestion =>
      'Magdagdag ng rack o shelf para sa mga gamit-pang kusina';

  @override
  String get olpItemB05Statement =>
      'May espasyo na hindi nakaharang sa mga pintuan';

  @override
  String get olpItemB05Suggestion =>
      'Ilipat ang mga gamit na nakaharang sa pintuan';

  @override
  String get olpItemB06Statement => 'Hindi nakaipit o nakasara ang mga bintana';

  @override
  String get olpItemB06Suggestion =>
      'Suriin at ayusin ang mga bintana upang madaling buksan';

  @override
  String get olpItemB07Statement =>
      'Walang nakatambak na papel o karton sa loob';

  @override
  String get olpItemB07Suggestion =>
      'I-recycle o itapon ang lumang papel at karton';

  @override
  String get olpItemB08Statement =>
      'Maayos ang pagkakatago ng mga gamit-na-malalim';

  @override
  String get olpItemB08Suggestion => 'Gumamit ng mga aparador o storage box';

  @override
  String get olpItemB09Statement => 'Walang basurang materyal sa silong';

  @override
  String get olpItemB09Suggestion => 'Linisin nang regular ang silong';

  @override
  String get olpItemB10Statement => 'May nakatakdang lalagyan ng basura';

  @override
  String get olpItemB10Suggestion =>
      'Maglagay ng lalagyan ng basura sa labas ng bahay';

  @override
  String get olpItemB11Statement =>
      'Walang nakatambak na karton at gamit sa loob ng kabinet';

  @override
  String get olpItemB11Suggestion => 'Ayusin ang mga gamit sa loob ng kabinet';

  @override
  String get olpItemB12Statement =>
      'May rubber hose ang tubig sa silindrong gas (LPG)';

  @override
  String get olpItemB12Suggestion => 'Bumili ng rubber hose para sa LPG';

  @override
  String get olpItemB13Statement =>
      'Maayos ang pagkakahanda sa pag-iwas sa apoy';

  @override
  String get olpItemB13Suggestion => 'Suriin ang mga panangga laban sa apoy';

  @override
  String get olpItemB14Statement =>
      'Walang nakaimbak na bote ng alkohol o pintura sa silid';

  @override
  String get olpItemB14Suggestion =>
      'Ilipat ang mga nasusunog na likido sa labas ng silid';

  @override
  String get olpItemB15Statement =>
      'May nakapostang plano ng paglabas kung magkasunog';

  @override
  String get olpItemB15Suggestion => 'Gumawa at i-post ang plano ng paglabas';

  @override
  String get olpItemC10Statement => 'May circuit breaker';

  @override
  String get olpItemC10Suggestion =>
      'Magkabit ng circuit breaker sa main electrical line';

  @override
  String get olpItemC11Statement => 'May takip ang electrical panel';

  @override
  String get olpItemC11Suggestion => 'Magkabit ng takip sa electrical panel';

  @override
  String get olpItemC12Statement => 'May takip ang junction boxes';

  @override
  String get olpItemC12Suggestion =>
      'Magkabit ng takip sa lahat ng junction boxes';

  @override
  String get olpItemC13Statement => 'May takip ang outlets';

  @override
  String get olpItemC13Suggestion => 'Magkabit ng takip sa lahat ng outlets';

  @override
  String get olpItemC14Statement => 'May takip ang switches';

  @override
  String get olpItemC14Suggestion => 'Magkabit ng takip sa lahat ng switches';

  @override
  String get olpItemC15Statement => 'Tama ang paggamit ng extension cord';

  @override
  String get olpItemC15Suggestion =>
      'Iwasan ang sobrang load sa extension cord';

  @override
  String get olpItemC16Statement => 'Walang exposed na electrical wires';

  @override
  String get olpItemC16Suggestion => 'Takipan ang lahat ng exposed wires';

  @override
  String get olpItemC17Statement =>
      'Maayos ang kondisyon ng outlets at switches';

  @override
  String get olpItemC17Suggestion => 'Palitan ang sirang outlets at switches';

  @override
  String get olpItemC18Statement => 'Tamang gauge ng wire ang ginagamit';

  @override
  String get olpItemC18Suggestion =>
      'Sumangguni sa elektrisyan para sa tamang gauge';

  @override
  String get olpItemD25Statement => 'Walang water leak sa kusina';

  @override
  String get olpItemD25Suggestion => 'Ayusin ang mga tubo na may leak';

  @override
  String get olpItemD26Statement =>
      'Walang nasusunog na bagay malapit sa kalan';

  @override
  String get olpItemD26Suggestion =>
      'Ilayo ang mga nasusunog na bagay sa kalan';

  @override
  String get olpItemD27Statement => 'Sinusuri nang regular ang gamit-kusina';

  @override
  String get olpItemD27Suggestion =>
      'Magkaroon ng lingguhang pagsusuri sa kalan at LPG';

  @override
  String get olpItemD28Statement => 'Sapat ang bentilasyon para sa usok';

  @override
  String get olpItemD28Suggestion =>
      'Magkabit ng exhaust o magdagdag ng bintana';

  @override
  String get olpItemD29Statement =>
      'Naitatago ang kandila at lighter sa tamang lalagyan';

  @override
  String get olpItemD29Suggestion =>
      'Maglagay ng nakatakdang lalagyan para sa kandila at lighter';

  @override
  String get olpItemE30Statement =>
      'Malinis at hindi nakaharang ang mga pintuan at bintana';

  @override
  String get olpItemE30Suggestion => 'Ilipat ang mga gamit na nakaharang';

  @override
  String get olpItemE31Statement => 'Walang tuyong dahon sa paligid ng bahay';

  @override
  String get olpItemE31Suggestion =>
      'Linisin ang mga tuyong dahon nang regular';

  @override
  String get olpItemE32Statement => 'Madaling makalabas kung magkasunog';

  @override
  String get olpItemE32Suggestion =>
      'Mag-ehersisyo ng paglabas kasama ang pamilya';

  @override
  String get olpItemE33Statement => 'Malapit ang bahay sa daan';

  @override
  String get olpItemE33Suggestion =>
      'Tiyakin na may madaling daan papunta sa pampublikong kalsada';

  @override
  String get olpItemE34Statement => 'Maayos ang panloob na daanan';

  @override
  String get olpItemE34Suggestion => 'Linisin ang mga daanan sa loob ng bahay';

  @override
  String get olpItemE35Statement => 'Sapat ang ilaw sa loob ng bahay';

  @override
  String get olpItemE35Suggestion =>
      'Magkabit ng karagdagang ilaw kung kailangan';

  @override
  String summaryFeatures(int n) {
    return '$n na istruktura';
  }

  @override
  String summaryComplete(int n) {
    return '$n tapos na';
  }

  @override
  String summaryIncomplete(int n) {
    return '$n kulang pa';
  }

  @override
  String summaryNewFeatures(int n) {
    return '$n bagong idinagdag';
  }

  @override
  String summaryPhotosPending(int n) {
    return '$n larawan ang kulang';
  }

  @override
  String failedJobsTitle(int n) {
    return 'Nabigo ($n)';
  }

  @override
  String get retryButton => 'Subukan muli';

  @override
  String get retryAllButton => 'Subukan lahat';

  @override
  String validationBlockersTitle(int n) {
    return 'Kailangang ayusin bago i-upload ($n)';
  }

  @override
  String validationWarningsTitle(int n) {
    return 'Inirerekomenda ($n)';
  }

  @override
  String get goToFeature => 'Pumunta sa feature';

  @override
  String get issuePhotoRequired => 'Kailangan ng kahit isang larawan';

  @override
  String get issueRa9514Required => 'Hindi pa napipili ang uri ng RA 9514';

  @override
  String get issueWidthRequired => 'Ang lapad ay dapat higit sa 0 m';

  @override
  String get issueOlpResidential =>
      'Hindi pa kumpleto ang OLP household survey';

  @override
  String get issueCostAmountMissing =>
      'Napili ang eksaktong halaga pero walang halaga';

  @override
  String get issueFeatureNoSubmission =>
      'Walang natapos na submission para sa feature na ito';

  @override
  String get startUploadButton => 'Simulan ang Pag-upload';

  @override
  String get startUploadDisabledTooltip =>
      'Ayusin muna ang mga problema sa itaas';

  @override
  String uploadProgressLabel(int done, int total) {
    return 'Ina-upload ang $done sa $total items…';
  }

  @override
  String get uploadProgressShowDetails => 'Ipakita ang detalye';

  @override
  String uploadCompleteSuccess(int n) {
    return 'Lahat ng $n items ay naka-upload na.';
  }

  @override
  String uploadCompleteWithFailures(int n) {
    return '$n items ang nabigo. Tingnan ang Failed.';
  }

  @override
  String get reviewTitle => 'Suriin at I-upload';

  @override
  String get submittedBadge => 'Naipasa na ✓';

  @override
  String submittedAt(String date) {
    return 'Naipasa noong $date';
  }

  @override
  String get biometricGateReason => 'Patunayan ang sarili para mag-upload';

  @override
  String get biometricFailedSnackbar => 'Hindi nakumpirma. Subukan muli.';

  @override
  String get assignmentClosedTitle => 'Sarado na ang takda';

  @override
  String get assignmentClosedBody =>
      'Sarado na ang takda na ito sa server. I-tap ang Share para ipadala ang lokal na datos sa supervisor mo.';

  @override
  String get shareBundleAction => 'Ibahagi ang bundle';
}
