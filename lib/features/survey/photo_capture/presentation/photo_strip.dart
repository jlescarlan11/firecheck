import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PhotoStrip extends ConsumerWidget {
  const PhotoStrip({required this.submissionId, super.key});
  final String submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final photosAsync = ref.watch(photosForSubmissionProvider(submissionId));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          photosAsync.when(
            loading: () => Text(l.photosLabel),
            error: (e, _) => Text(l.photosLabel),
            data: (photos) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l.photosLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (photos.isEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC53030),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l.photosRequiredBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Text(
                    l.photosCompleteBadge,
                    style: const TextStyle(
                      color: Color(0xFF276749),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: photosAsync.when(
              loading: () => const SizedBox(),
              error: (e, _) => const SizedBox(),
              data: (photos) => ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  if (i == photos.length) {
                    return _AddPhotoChip(submissionId: submissionId);
                  }
                  return _Thumbnail(photo: photos[i]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoChip extends ConsumerWidget {
  const _AddPhotoChip({required this.submissionId});
  final String submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return GestureDetector(
      key: const Key('photo-strip.add'),
      onTap: () async {
        try {
          await ref
              .read(photoCaptureControllerProvider)
              .capture(submissionId: submissionId);
        } on Object {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.cameraPermissionSnackbar)),
            );
          }
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0x103B82F6),
          border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            l.addPhoto,
            style: const TextStyle(
              color: Color(0xFF3B82F6),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.photo});
  final Photo photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return GestureDetector(
      key: Key('photo-strip.thumb.${photo.id}'),
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.deletePhoto),
            content: Text(l.deletePhotoConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.deleteAction),
              ),
            ],
          ),
        );
        if (ok ?? false) {
          await ref.read(photoRepositoryProvider).delete(photo.id);
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          borderRadius: BorderRadius.circular(6),
          image: DecorationImage(
            image: FileImage(File(photo.localPath)),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      ),
    );
  }
}
