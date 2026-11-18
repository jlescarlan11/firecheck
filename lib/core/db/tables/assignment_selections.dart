import 'package:drift/drift.dart';
import 'assignments.dart';

class AssignmentSelections extends Table {
  TextColumn get userId => text()();
  TextColumn get assignmentId => text().references(Assignments, #id)();
  DateTimeColumn get selectedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {userId};
}
