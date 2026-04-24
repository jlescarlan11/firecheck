import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/data/progress_repository.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(ref.watch(appDatabaseProvider));
});

final progressProvider = StreamProvider<ProgressSnapshot>((ref) {
  return ref.watch(progressRepositoryProvider).watchProgress();
});
