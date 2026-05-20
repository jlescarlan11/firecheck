import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriveUploadAudit {
  const DriveUploadAudit({
    required this.id,
    required this.assignmentId,
    required this.uploadedBy,
    required this.driveFolderPath,
    required this.driveFolderUrl,
    required this.fileCount,
    required this.uploadedAt,
    this.uploaderDisplayName,
  });

  final String id;
  final String assignmentId;
  final String uploadedBy;
  final String driveFolderPath;
  final String driveFolderUrl;
  final int fileCount;
  final DateTime uploadedAt;
  final String? uploaderDisplayName;

  bool get isCurrentUser => false;
}

/// Outcome of [DriveUploadAuditRepository.listForAssignment]. The probe is
/// best-effort — a network/auth failure must not silently masquerade as
/// "no prior uploads," because that would let callers (e.g. the overwrite
/// confirmation dialog) bypass safety checks while offline.
sealed class AuditProbeResult {
  const AuditProbeResult();
}

final class AuditProbeAvailable extends AuditProbeResult {
  const AuditProbeAvailable(this.audits);
  final List<DriveUploadAudit> audits;
}

final class AuditProbeUnavailable extends AuditProbeResult {
  const AuditProbeUnavailable(this.reason);
  final String reason;
}

class DriveUploadAuditRepository {
  DriveUploadAuditRepository(this._client);
  final SupabaseClient _client;

  /// Returns prior Drive uploads for the assignment, newest first, or an
  /// [AuditProbeUnavailable] when the probe couldn't reach Supabase.
  Future<AuditProbeResult> listForAssignment(String assignmentId) async {
    try {
      final rows = await _client
          .from('drive_uploads')
          .select(
            'id,assignment_id,uploaded_by,drive_folder_path,drive_folder_url,'
            'file_count,uploaded_at,enumerators(display_name)',
          )
          .eq('assignment_id', assignmentId)
          .order('uploaded_at', ascending: false);
      return AuditProbeAvailable(
        rows.map(_parseRow).toList(growable: false),
      );
    } on Object catch (e, st) {
      debugPrint(
        '[DriveUploadAudit] probe failed for assignmentId="$assignmentId": $e\n$st',
      );
      return AuditProbeUnavailable(e.toString());
    }
  }

  /// Records a successful Drive upload. Failures are logged but never
  /// raised — the local Drive upload already succeeded, and the audit
  /// row will simply be missing for other users until the next upload.
  Future<void> record({
    required String assignmentId,
    required String uploadedBy,
    required String driveFolderPath,
    required String driveFolderUrl,
    required int fileCount,
  }) async {
    try {
      await _client.from('drive_uploads').insert({
        'assignment_id': assignmentId,
        'uploaded_by': uploadedBy,
        'drive_folder_path': driveFolderPath,
        'drive_folder_url': driveFolderUrl,
        'file_count': fileCount,
      });
    } on Object catch (e, st) {
      debugPrint('[DriveUploadAudit] record failed: $e\n$st');
    }
  }

  DriveUploadAudit _parseRow(Map<String, dynamic> row) {
    final embedded = row['enumerators'];
    String? displayName;
    if (embedded is Map<String, dynamic>) {
      displayName = embedded['display_name'] as String?;
    }
    return DriveUploadAudit(
      id: row['id'] as String,
      assignmentId: row['assignment_id'] as String,
      uploadedBy: row['uploaded_by'] as String,
      driveFolderPath: row['drive_folder_path'] as String? ?? '',
      driveFolderUrl: row['drive_folder_url'] as String? ?? '',
      fileCount: (row['file_count'] as num?)?.toInt() ?? 0,
      uploadedAt: DateTime.parse(row['uploaded_at'] as String).toLocal(),
      uploaderDisplayName: displayName,
    );
  }
}
