import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/gateway/gateway_client.dart';

typedef GatewayUploadReceipt = ({
  String folderPath,
  String folderUrl,
  int count,
  DateTime confirmedAt
});

class GatewayUploadRunner {
  GatewayUploadRunner({required this.client, required this.repo});
  final GatewayClient client;
  final DriveUploadRepository repo;
  bool _running = false;
  Future<void> drain() async {
    if (_running) return;
    _running = true;
    try {
      final owner = client.userId();
      if (owner == null) return;
      await repo.resetStuckUploadingToPending();
      final pending = await repo.getPendingJobs();
      final batches = <String, List<DriveUploadJob>>{};
      for (final j in pending) {
        // Old queues have no trustworthy owner binding. Do not silently adopt.
        if (j.ownerId == null || j.batchId == null) {
          await repo.markDead(
            j.id,
            reason:
                'This older export has no account owner. Export the assignment again.',
          );
          continue;
        }
        if (j.ownerId != owner) continue;
        batches.putIfAbsent(j.batchId!, () => []).add(j);
      }
      for (final group in batches.values) {
        if (client.userId() != owner) return;
        final first = group.first;
        final jobs = (await repo.getJobsForAssignment(first.assignmentId))
            .where((j) => j.batchId == first.batchId && j.ownerId == owner)
            .toList();
        try {
          for (final j in jobs) {
            await repo.markUploading(j.id);
          }
          await _batch(owner, first.batchId!, first.assignmentId, jobs);
          for (final j in jobs) {
            await repo.markCompleted(
              j.id,
              driveFileId: 'gateway:${first.batchId}:${j.id}',
            );
          }
        } catch (e) {
          for (final j in jobs) {
            final attempts = j.retryCount + 1;
            if (e is StorageFailure || e is ValidationFailure || attempts > 8) {
              await repo.markDead(j.id, reason: e.toString());
              continue;
            }
            await repo.markFailed(
              j.id,
              reason: e.toString(),
              retryCount: attempts,
              nextRetryAt: DateTime.now().add(
                Duration(
                  seconds: attempts > 5 ? 900 : 30 * (1 << attempts),
                ),
              ),
            );
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _batch(
    String owner,
    String batch,
    String assignment,
    List<DriveUploadJob> jobs,
  ) async {
    final files = <Map<String, dynamic>>[];
    for (final j in jobs) {
      final file = File(j.filePath);
      if (!file.existsSync()) {
        throw const StorageFailure(
          'An exported file is missing. Export the assignment again.',
        );
      }
      final size = await file.length();
      if (size != j.fileSizeBytes) {
        throw const StorageFailure(
          'An exported file changed. Export the assignment again.',
        );
      }
      files.add({
        'id': j.id,
        'name': j.fileName,
        'size': size,
        'md5': (await md5.bind(file.openRead()).first).toString(),
      });
    }
    final created = await client.json(
      'POST',
      '/v1/assignments/$assignment/uploads',
      owner: owner,
      body: {'id': batch, 'files': files},
    );
    if (created['complete'] == true) return;
    for (final job in jobs) {
      final path = '/v1/uploads/$batch/files/${job.id}';
      var state = await client.json('GET', path, owner: owner);
      final handle = await File(job.filePath).open();
      try {
        var stalls = 0;
        while (state['complete'] != true) {
          final offset = (state['offset'] as num).toInt();
          if (offset < 0 || offset >= job.fileSizeBytes) {
            throw const NetworkFailure('Invalid upload offset.');
          }
          await handle.setPosition(offset);
          final data = await handle.read(8 * 1024 * 1024);
          if (data.isEmpty) {
            throw const StorageFailure('The export is incomplete.');
          }
          final r = await client.send(
            'PUT',
            '$path/chunks',
            owner: owner,
            bytes: data,
            headers: {
              'Content-Type': 'application/octet-stream',
              'Upload-Offset': '$offset',
            },
          );
          state = jsonDecode(
            await r.stream.bytesToString().timeout(const Duration(seconds: 60)),
          ) as Map<String, dynamic>;
          if (state['complete'] != true &&
              (state['offset'] as num).toInt() <= offset) {
            if (++stalls > 2) {
              throw const NetworkFailure(
                'Upload is not advancing. It will retry later.',
              );
            }
          } else {
            stalls = 0;
          }
        }
      } finally {
        await handle.close();
      }
    }
    final completed =
        await client.json('POST', '/v1/uploads/$batch/complete', owner: owner);
    if (completed['complete'] != true) {
      throw const NetworkFailure('Waiting for server confirmation.');
    }
  }

  Future<GatewayUploadReceipt?> receipt(
    String assignment,
    String? owner,
  ) async {
    if (owner == null || client.userId() != owner) return null;
    var jobs = (await repo.getJobsForAssignment(assignment))
        .where((j) => j.ownerId == owner && j.batchId != null)
        .toList();
    if (jobs.isNotEmpty) {
      final latest = jobs.last.batchId;
      jobs = jobs.where((j) => j.batchId == latest).toList();
    }
    if (jobs.isEmpty ||
        jobs.any(
          (j) =>
              j.ownerId != owner ||
              j.batchId == null ||
              j.status != 'completed',
        )) {
      return null;
    }
    final batches = jobs.map((j) => j.batchId).toSet();
    if (batches.length != 1) return null;
    final r =
        await client.json('GET', '/v1/uploads/${batches.single}', owner: owner);
    if (r['complete'] != true) return null;
    return (
      folderPath: r['folderPath'] as String,
      folderUrl: r['folderUrl'] as String,
      count: (r['files'] as List).length,
      confirmedAt: DateTime.parse(r['completedAt'] as String)
    );
  }
}
