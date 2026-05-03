// test/core/auth/current_user_provider_test.dart
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSession extends Mock implements Session {}
class _MockUser extends Mock implements User {}

void main() {
  test('returns userId when session exists', () async {
    final user = _MockUser();
    final session = _MockSession();
    when(() => session.user).thenReturn(user);
    when(() => user.id).thenReturn('u-123');

    final container = ProviderContainer(
      overrides: [
        supabaseAuthStateProvider.overrideWith(
          (ref) => Stream.value(session),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(supabaseAuthStateProvider, (_, __) {});

    // Allow the stream to emit
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserIdProvider), 'u-123');
  });

  test('returns null when no session', () async {
    final container = ProviderContainer(
      overrides: [
        supabaseAuthStateProvider.overrideWith(
          (ref) => Stream.value(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(supabaseAuthStateProvider, (_, __) {});

    // Allow the stream to emit
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserIdProvider), isNull);
  });
}
