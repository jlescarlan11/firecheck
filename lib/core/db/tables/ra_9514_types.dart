import 'package:drift/drift.dart';

class Ra9514Types extends Table {
  TextColumn get code => text()();
  TextColumn get labelEn => text()();
  TextColumn get labelTl => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}
