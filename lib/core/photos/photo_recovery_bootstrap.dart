import 'dart:async';

import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/core/router/app_router.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Performs Android ImagePicker lost-data recovery once per process start.
/// Recovery is deliberately below MaterialApp so navigation can restore the
/// exact survey form after the photo row has been durably inserted.
class PhotoRecoveryBootstrap extends ConsumerStatefulWidget {
  const PhotoRecoveryBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PhotoRecoveryBootstrap> createState() =>
      _PhotoRecoveryBootstrapState();
}

class _PhotoRecoveryBootstrapState
    extends ConsumerState<PhotoRecoveryBootstrap> {
  @override
  void initState() {
    super.initState();
    unawaited(_recover());
  }

  Future<void> _recover() async {
    try {
      final pending = await ref
          .read(photoCaptureControllerProvider)
          .recoverPendingCapture();
      if (pending == null || !mounted) return;
      final session = await ref.read(supabaseAuthStateProvider.future);
      if (session == null || !mounted) return;
      final featureId = Uri.encodeComponent(pending.featureId);
      final submissionId = Uri.encodeQueryComponent(pending.submissionId);
      ref.read(appRouterProvider).go(
            '/feature/$featureId?submissionId=$submissionId',
          );
    } on Object {
      // Recovery must never prevent app startup. Capture/processing errors are
      // surfaced on the next explicit camera attempt.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
