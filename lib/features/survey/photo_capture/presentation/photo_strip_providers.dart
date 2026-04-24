import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final photosForSubmissionProvider = StreamProvider.autoDispose
    .family<List<Photo>, String>((ref, submissionId) {
  return ref.watch(photoRepositoryProvider).watchForSubmission(submissionId);
});
