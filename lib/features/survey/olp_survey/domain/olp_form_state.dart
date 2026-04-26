import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';

class OlpFormState {
  const OlpFormState({
    required this.submissionId,
    this.checkedCodes = const {},
    this.constructionDetails = const {},
    this.homeownerAcknowledged = false,
    this.completedAt,
  });

  final String submissionId;
  final Set<String> checkedCodes;
  final Map<String, ConstructionDetail> constructionDetails;
  final bool homeownerAcknowledged;
  final DateTime? completedAt;

  OlpFormState copyWith({
    Set<String>? checkedCodes,
    Map<String, ConstructionDetail>? constructionDetails,
    bool? homeownerAcknowledged,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return OlpFormState(
      submissionId: submissionId,
      checkedCodes: checkedCodes ?? this.checkedCodes,
      constructionDetails: constructionDetails ?? this.constructionDetails,
      homeownerAcknowledged:
          homeownerAcknowledged ?? this.homeownerAcknowledged,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}
