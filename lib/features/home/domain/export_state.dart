// lib/features/home/domain/export_state.dart
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';

sealed class ExportState {
  const ExportState();
}

class ExportIdle extends ExportState {
  const ExportIdle();
}

class ExportExporting extends ExportState {
  const ExportExporting();
}

class ExportDone extends ExportState {
  const ExportDone();
}

class ExportFailed extends ExportState {
  const ExportFailed(this.failure);
  final ExportFailure failure;
}
