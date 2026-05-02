import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/presentation/sections/drive_upload_confirmation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final successState = DriveUploadSuccess(
    folderPath: 'FieldData/enum-1/2026-05-02/',
    folderUrl: 'https://drive.google.com/drive/folders/abc123',
    referenceId: 'ASN-AABBCCDD',
    confirmedAt: DateTime(2026, 5, 2, 20, 42),
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders nothing when Idle', (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: const DriveUploadIdle()),
    ));
    expect(find.text('Submitted to Google Drive'), findsNothing);
    expect(find.text('Upload Failed'), findsNothing);
  });

  testWidgets('renders nothing when InProgress', (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: const DriveUploadInProgress(0.5)),
    ));
    expect(find.text('Submitted to Google Drive'), findsNothing);
  });

  testWidgets('success state renders path, reference ID, and timestamp',
      (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: successState),
    ));

    expect(find.text('Submitted to Google Drive'), findsOneWidget);
    expect(find.text('FieldData/enum-1/2026-05-02/'), findsOneWidget);
    expect(find.text('ASN-AABBCCDD'), findsOneWidget);
    expect(find.text('Open in Google Drive →'), findsOneWidget);
    expect(find.text('May 2 · 8:42 PM'), findsOneWidget);
  });

  testWidgets('Copy button copies full Drive URL to clipboard', (tester) async {
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        log.add(call);
        return null;
      },
    );

    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: successState),
    ));

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(
      log.any((c) =>
          c.method == 'Clipboard.setData' &&
          (c.arguments as Map)['text'] ==
              'https://drive.google.com/drive/folders/abc123'),
      isTrue,
    );
  });

  testWidgets('failure state renders error message and retry button',
      (tester) async {
    bool retryCalled = false;
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(
        state: const DriveUploadFailure(
          message: 'Could not reach Google Drive.',
          canRetry: true,
        ),
        onRetry: () => retryCalled = true,
      ),
    ));

    expect(find.text('Upload Failed'), findsOneWidget);
    expect(find.text('Could not reach Google Drive.'), findsOneWidget);
    expect(find.text('Retry Upload'), findsOneWidget);
    expect(find.text('Submitted to Google Drive'), findsNothing);

    await tester.tap(find.text('Retry Upload'));
    expect(retryCalled, isTrue);
  });

  testWidgets('auth failure shows Re-authenticate button instead of Retry',
      (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(
        state: const DriveUploadFailure(
          message: 'Google Drive authentication expired.',
          canRetry: false,
        ),
      ),
    ));

    expect(find.text('Re-authenticate'), findsOneWidget);
    expect(find.text('Retry Upload'), findsNothing);
  });
}
