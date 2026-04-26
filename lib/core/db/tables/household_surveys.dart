import 'package:drift/drift.dart';

class HouseholdSurveys extends Table {
  TextColumn get submissionId => text()();
  TextColumn get constructionDetailsJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get kaayusanJson => text().withDefault(const Constant('{}'))();
  TextColumn get koneksyongElektrikalJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get kusinaJson => text().withDefault(const Constant('{}'))();
  TextColumn get daananOLabasanJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get lebelNgKahinaan => text().nullable()();
  TextColumn get safetySuggestions => text().nullable()();
  BoolColumn get homeownerAcknowledged =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {submissionId};
}
