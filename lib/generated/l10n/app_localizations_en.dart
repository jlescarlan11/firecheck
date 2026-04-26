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
  String get doesNotExistTitleRoad => 'This road does not exist';

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

  @override
  String get gpsWaitingSnackbar => 'Waiting for GPS fix…';

  @override
  String get sectionRoadIdentity => 'Road identity';

  @override
  String get sectionRoadDimensions => 'Dimensions';

  @override
  String get sectionRoadFeatures => 'Features';

  @override
  String get fieldRoadName => 'Road name';

  @override
  String get fieldIsBridge => 'This is a bridge';

  @override
  String get fieldWidthMeters => 'Width (m)';

  @override
  String get widthMetersUnusual => 'Width over 30 m looks unusual';

  @override
  String get roadFeatureVendor => 'Vendor stalls';

  @override
  String get roadFeaturePedestrian => 'Pedestrian';

  @override
  String get roadFeatureParking => 'Parking';

  @override
  String get roadFeatureOthers => 'Others';

  @override
  String get roadFeatureOthersDescription => 'Describe other features';

  @override
  String get addModeBannerHint =>
      'Long-press the map to add a building or road. Tap the pill again to cancel.';

  @override
  String get addModePillActiveLabel => 'Tap & hold to drop pin';

  @override
  String get outsideBoundarySnackbar =>
      'Long-press is outside your assignment area';

  @override
  String get pickFeatureTypeTitle => 'What did you find?';

  @override
  String get pickFeatureTypeBuilding => 'Building';

  @override
  String get pickFeatureTypeRoad => 'Road';

  @override
  String get featureNotFound => 'Feature not found';

  @override
  String get olpSectionTitle => 'OLP household survey · Optional';

  @override
  String get olpSectionA => 'Construction details (descriptive)';

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
      'This survey is voluntary, not mandatory.';

  @override
  String get olpDisclaimerSurveyorRole =>
      'The surveyor is a guide, not an enforcer.';

  @override
  String get olpDisclaimerNoSelling =>
      'The surveyor cannot sell or recommend fire extinguishers.';

  @override
  String get olpHomeownerAgreesLabel => 'Homeowner agrees';

  @override
  String get olpScoreLabel => 'Score';

  @override
  String olpScoreFraction(Object score, Object max) {
    return '$score / $max';
  }

  @override
  String get olpViewBreakdown => 'View breakdown →';

  @override
  String get olpMarkComplete => 'Mark survey complete';

  @override
  String get olpAcknowledgmentRequiredTooltip => 'Homeowner must agree first';

  @override
  String get olpResultTitle => 'Survey result';

  @override
  String get olpResultSurveyComplete => 'Survey complete';

  @override
  String get olpClassLigtas => 'Ligtas ang Iyong Tahanan';

  @override
  String get olpClassMayroong => 'Mayroong Dapat Ipangamba';

  @override
  String get olpClassLabis => 'Labis na Mapanganib';

  @override
  String get olpElementRoof => 'Roof';

  @override
  String get olpElementCeiling => 'Ceiling';

  @override
  String get olpElementRoomPartitions => 'Room partitions';

  @override
  String get olpElementTrusses => 'Trusses';

  @override
  String get olpElementWindows => 'Windows';

  @override
  String get olpElementCorridorWalls => 'Corridor walls';

  @override
  String get olpElementColumns => 'Columns';

  @override
  String get olpElementMainDoor => 'Main door';

  @override
  String get olpElementExteriorWall => 'Exterior wall';

  @override
  String get olpElementBeams => 'Beams';

  @override
  String get olpMaterialKahoy => 'Wood';

  @override
  String get olpMaterialSemento => 'Concrete';

  @override
  String get olpMaterialBakal => 'Steel';

  @override
  String get olpMaterialOthers => 'Other';

  @override
  String get olpMaterialOthersHint => 'Specify other material';

  @override
  String get olpItemB01Statement => 'No accumulated trash inside the home';

  @override
  String get olpItemB01Suggestion => 'Dispose of trash in proper bins daily';

  @override
  String get olpItemB02Statement => 'No deep-stored materials in walkways';

  @override
  String get olpItemB02Suggestion =>
      'Move items to separate storage to keep walkways clear';

  @override
  String get olpItemB03Statement => 'Clothes are not piled on the bed';

  @override
  String get olpItemB03Suggestion => 'Store clothes in a closet or cabinet';

  @override
  String get olpItemB04Statement => 'Kitchen items are arranged properly';

  @override
  String get olpItemB04Suggestion => 'Add a rack or shelf for kitchen utensils';

  @override
  String get olpItemB05Statement => 'Doorways are not blocked';

  @override
  String get olpItemB05Suggestion => 'Move items blocking doorways';

  @override
  String get olpItemB06Statement => 'Windows are not stuck or sealed shut';

  @override
  String get olpItemB06Suggestion =>
      'Inspect and repair windows so they open easily';

  @override
  String get olpItemB07Statement => 'No piles of paper or cardboard inside';

  @override
  String get olpItemB07Suggestion =>
      'Recycle or dispose of old paper and cardboard';

  @override
  String get olpItemB08Statement => 'Long-stored items are properly stored';

  @override
  String get olpItemB08Suggestion => 'Use cabinets or storage boxes';

  @override
  String get olpItemB09Statement => 'No trash material under the house';

  @override
  String get olpItemB09Suggestion => 'Clean under the house regularly';

  @override
  String get olpItemB10Statement => 'There is a designated trash container';

  @override
  String get olpItemB10Suggestion =>
      'Place a trash container outside the house';

  @override
  String get olpItemB11Statement =>
      'No cardboard or items piled inside cabinets';

  @override
  String get olpItemB11Suggestion => 'Organize items inside cabinets';

  @override
  String get olpItemB12Statement => 'The LPG tank has a rubber hose';

  @override
  String get olpItemB12Suggestion => 'Buy a rubber hose for the LPG tank';

  @override
  String get olpItemB13Statement => 'Fire prevention is properly prepared';

  @override
  String get olpItemB13Suggestion => 'Check fire prevention measures';

  @override
  String get olpItemB14Statement =>
      'No bottles of alcohol or paint stored in the room';

  @override
  String get olpItemB14Suggestion => 'Move flammable liquids out of the room';

  @override
  String get olpItemB15Statement =>
      'There is a posted evacuation plan in case of fire';

  @override
  String get olpItemB15Suggestion => 'Create and post an evacuation plan';

  @override
  String get olpItemC10Statement => 'There is a circuit breaker';

  @override
  String get olpItemC10Suggestion =>
      'Install a circuit breaker on the main electrical line';

  @override
  String get olpItemC11Statement => 'The electrical panel has a cover';

  @override
  String get olpItemC11Suggestion => 'Install a cover on the electrical panel';

  @override
  String get olpItemC12Statement => 'Junction boxes have covers';

  @override
  String get olpItemC12Suggestion => 'Install covers on all junction boxes';

  @override
  String get olpItemC13Statement => 'Outlets have covers';

  @override
  String get olpItemC13Suggestion => 'Install covers on all outlets';

  @override
  String get olpItemC14Statement => 'Switches have covers';

  @override
  String get olpItemC14Suggestion => 'Install covers on all switches';

  @override
  String get olpItemC15Statement => 'Extension cords are used properly';

  @override
  String get olpItemC15Suggestion => 'Avoid overloading extension cords';

  @override
  String get olpItemC16Statement => 'No exposed electrical wires';

  @override
  String get olpItemC16Suggestion => 'Cover all exposed wires';

  @override
  String get olpItemC17Statement =>
      'Outlets and switches are in good condition';

  @override
  String get olpItemC17Suggestion => 'Replace damaged outlets and switches';

  @override
  String get olpItemC18Statement => 'Correct wire gauge is used';

  @override
  String get olpItemC18Suggestion =>
      'Consult an electrician for the correct gauge';

  @override
  String get olpItemD25Statement => 'No water leaks in the kitchen';

  @override
  String get olpItemD25Suggestion => 'Repair leaking pipes';

  @override
  String get olpItemD26Statement => 'No flammable items near the stove';

  @override
  String get olpItemD26Suggestion => 'Move flammable items away from the stove';

  @override
  String get olpItemD27Statement => 'Kitchen equipment is regularly inspected';

  @override
  String get olpItemD27Suggestion => 'Conduct weekly checks of stove and LPG';

  @override
  String get olpItemD28Statement => 'Sufficient smoke ventilation';

  @override
  String get olpItemD28Suggestion => 'Install an exhaust or add a window';

  @override
  String get olpItemD29Statement =>
      'Candles and lighters stored in proper containers';

  @override
  String get olpItemD29Suggestion =>
      'Designate containers for candles and lighters';

  @override
  String get olpItemE30Statement =>
      'Doorways and windows are clear and unblocked';

  @override
  String get olpItemE30Suggestion => 'Move items that are blocking';

  @override
  String get olpItemE31Statement => 'No dry leaves around the house';

  @override
  String get olpItemE31Suggestion => 'Clear dry leaves regularly';

  @override
  String get olpItemE32Statement => 'Easy escape during fire';

  @override
  String get olpItemE32Suggestion => 'Practice evacuation with family';

  @override
  String get olpItemE33Statement => 'The house is close to a road';

  @override
  String get olpItemE33Suggestion => 'Ensure easy access to a public road';

  @override
  String get olpItemE34Statement => 'Interior pathways are well-kept';

  @override
  String get olpItemE34Suggestion => 'Clean interior pathways';

  @override
  String get olpItemE35Statement => 'Adequate interior lighting';

  @override
  String get olpItemE35Suggestion => 'Install additional lighting if needed';
}
