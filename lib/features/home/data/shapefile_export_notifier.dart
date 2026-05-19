import 'package:firecheck/core/sync/shapefile/export/shapefile_export_validator.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class ShapefileExportNotifier extends StateNotifier<ExportState> {
  ShapefileExportNotifier({
    required String assignmentId,
    required ShapefileExporter exporter,
    required ShapefileExportValidator validator,
  })  : _assignmentId = assignmentId,
        _exporter = exporter,
        _validator = validator,
        super(const ExportIdle());

  final String _assignmentId;
  final ShapefileExporter _exporter;
  final ShapefileExportValidator _validator;

  Future<void> export() async {
    if (state is ExportValidating || state is ExportExporting) return;

    state = const ExportValidating();
    final result = await _validator.validate(_assignmentId);

    if (!mounted) return;
    if (!result.isValid) {
      state = ExportValidationFailed(result.errors);
      return;
    }

    state = const ExportExporting();
    final failure = await _exporter.export(assignmentId: _assignmentId);

    if (!mounted) return;
    if (failure != null) {
      state = ExportFailed(failure);
      state = const ExportIdle();
      return;
    }

    state = const ExportDone();
    state = const ExportIdle();
  }
}

final shapefileExportNotifierProvider =
    StateNotifierProvider<ShapefileExportNotifier, ExportState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final assignmentAsync = ref.watch(currentAssignmentProvider);
  final assignmentId = assignmentAsync.value?.id ?? '';

  return ShapefileExportNotifier(
    assignmentId: assignmentId,
    exporter: ShapefileExporter(
      db: db,
      shareFile: (path) async {
        await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      },
    ),
    validator: ShapefileExportValidator(db: db),
  );
});
