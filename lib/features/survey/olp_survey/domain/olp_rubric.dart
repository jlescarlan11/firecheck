enum OlpSection { b, c, d, e }

class OlpRubricItem {
  const OlpRubricItem({
    required this.code,
    required this.section,
    required this.statementKey,
    required this.suggestionKey,
  });
  final String code;
  final OlpSection section;
  final String statementKey;
  final String suggestionKey;
}

class OlpRubric {
  // PRD risk #2: 12/23 boundary unverified — verify against printed
  // CFPP Rev.00 (07.27.23) form before pilot.
  static const ligtasThreshold = 24;
  static const mayroongThreshold = 12;

  static const items = <OlpRubricItem>[
    // Section B — 15 draft items (PRD risk #1: verify before pilot)
    OlpRubricItem(code: 'B-01', section: OlpSection.b, statementKey: 'olpItemB01Statement', suggestionKey: 'olpItemB01Suggestion'),
    OlpRubricItem(code: 'B-02', section: OlpSection.b, statementKey: 'olpItemB02Statement', suggestionKey: 'olpItemB02Suggestion'),
    OlpRubricItem(code: 'B-03', section: OlpSection.b, statementKey: 'olpItemB03Statement', suggestionKey: 'olpItemB03Suggestion'),
    OlpRubricItem(code: 'B-04', section: OlpSection.b, statementKey: 'olpItemB04Statement', suggestionKey: 'olpItemB04Suggestion'),
    OlpRubricItem(code: 'B-05', section: OlpSection.b, statementKey: 'olpItemB05Statement', suggestionKey: 'olpItemB05Suggestion'),
    OlpRubricItem(code: 'B-06', section: OlpSection.b, statementKey: 'olpItemB06Statement', suggestionKey: 'olpItemB06Suggestion'),
    OlpRubricItem(code: 'B-07', section: OlpSection.b, statementKey: 'olpItemB07Statement', suggestionKey: 'olpItemB07Suggestion'),
    OlpRubricItem(code: 'B-08', section: OlpSection.b, statementKey: 'olpItemB08Statement', suggestionKey: 'olpItemB08Suggestion'),
    OlpRubricItem(code: 'B-09', section: OlpSection.b, statementKey: 'olpItemB09Statement', suggestionKey: 'olpItemB09Suggestion'),
    OlpRubricItem(code: 'B-10', section: OlpSection.b, statementKey: 'olpItemB10Statement', suggestionKey: 'olpItemB10Suggestion'),
    OlpRubricItem(code: 'B-11', section: OlpSection.b, statementKey: 'olpItemB11Statement', suggestionKey: 'olpItemB11Suggestion'),
    OlpRubricItem(code: 'B-12', section: OlpSection.b, statementKey: 'olpItemB12Statement', suggestionKey: 'olpItemB12Suggestion'),
    OlpRubricItem(code: 'B-13', section: OlpSection.b, statementKey: 'olpItemB13Statement', suggestionKey: 'olpItemB13Suggestion'),
    OlpRubricItem(code: 'B-14', section: OlpSection.b, statementKey: 'olpItemB14Statement', suggestionKey: 'olpItemB14Suggestion'),
    OlpRubricItem(code: 'B-15', section: OlpSection.b, statementKey: 'olpItemB15Statement', suggestionKey: 'olpItemB15Suggestion'),
    // Section C — 9 items (codes 10–18 per PRD §4)
    OlpRubricItem(code: 'C-10', section: OlpSection.c, statementKey: 'olpItemC10Statement', suggestionKey: 'olpItemC10Suggestion'),
    OlpRubricItem(code: 'C-11', section: OlpSection.c, statementKey: 'olpItemC11Statement', suggestionKey: 'olpItemC11Suggestion'),
    OlpRubricItem(code: 'C-12', section: OlpSection.c, statementKey: 'olpItemC12Statement', suggestionKey: 'olpItemC12Suggestion'),
    OlpRubricItem(code: 'C-13', section: OlpSection.c, statementKey: 'olpItemC13Statement', suggestionKey: 'olpItemC13Suggestion'),
    OlpRubricItem(code: 'C-14', section: OlpSection.c, statementKey: 'olpItemC14Statement', suggestionKey: 'olpItemC14Suggestion'),
    OlpRubricItem(code: 'C-15', section: OlpSection.c, statementKey: 'olpItemC15Statement', suggestionKey: 'olpItemC15Suggestion'),
    OlpRubricItem(code: 'C-16', section: OlpSection.c, statementKey: 'olpItemC16Statement', suggestionKey: 'olpItemC16Suggestion'),
    OlpRubricItem(code: 'C-17', section: OlpSection.c, statementKey: 'olpItemC17Statement', suggestionKey: 'olpItemC17Suggestion'),
    OlpRubricItem(code: 'C-18', section: OlpSection.c, statementKey: 'olpItemC18Statement', suggestionKey: 'olpItemC18Suggestion'),
    // Section D — 5 items (codes 25–29)
    OlpRubricItem(code: 'D-25', section: OlpSection.d, statementKey: 'olpItemD25Statement', suggestionKey: 'olpItemD25Suggestion'),
    OlpRubricItem(code: 'D-26', section: OlpSection.d, statementKey: 'olpItemD26Statement', suggestionKey: 'olpItemD26Suggestion'),
    OlpRubricItem(code: 'D-27', section: OlpSection.d, statementKey: 'olpItemD27Statement', suggestionKey: 'olpItemD27Suggestion'),
    OlpRubricItem(code: 'D-28', section: OlpSection.d, statementKey: 'olpItemD28Statement', suggestionKey: 'olpItemD28Suggestion'),
    OlpRubricItem(code: 'D-29', section: OlpSection.d, statementKey: 'olpItemD29Statement', suggestionKey: 'olpItemD29Suggestion'),
    // Section E — 6 items (codes 30–35)
    OlpRubricItem(code: 'E-30', section: OlpSection.e, statementKey: 'olpItemE30Statement', suggestionKey: 'olpItemE30Suggestion'),
    OlpRubricItem(code: 'E-31', section: OlpSection.e, statementKey: 'olpItemE31Statement', suggestionKey: 'olpItemE31Suggestion'),
    OlpRubricItem(code: 'E-32', section: OlpSection.e, statementKey: 'olpItemE32Statement', suggestionKey: 'olpItemE32Suggestion'),
    OlpRubricItem(code: 'E-33', section: OlpSection.e, statementKey: 'olpItemE33Statement', suggestionKey: 'olpItemE33Suggestion'),
    OlpRubricItem(code: 'E-34', section: OlpSection.e, statementKey: 'olpItemE34Statement', suggestionKey: 'olpItemE34Suggestion'),
    OlpRubricItem(code: 'E-35', section: OlpSection.e, statementKey: 'olpItemE35Statement', suggestionKey: 'olpItemE35Suggestion'),
  ];

  static const constructionElements = <String>[
    'roof', 'ceiling', 'roomPartitions', 'trusses', 'windows',
    'corridorWalls', 'columns', 'mainDoor', 'exteriorWall', 'beams',
  ];

  static const materials = <String>['kahoy', 'semento', 'bakal', 'others'];
}
