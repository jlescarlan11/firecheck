import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/gateway/gateway_client.dart';
import 'package:firecheck/core/gateway/gateway_upload_runner.dart';
import 'package:firecheck/core/supabase/supabase_client_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Uri? configuredGatewayUri() {
  final value = dotenv.env['FIRECHECK_GATEWAY_URL']?.trim();
  return value == null || value.isEmpty ? null : Uri.parse(value);
}

final gatewayClientProvider = Provider<GatewayClient?>((ref) {
  final uri = configuredGatewayUri();
  if (uri == null) return null;
  final client = GatewayClient.supabase(uri, ref.watch(supabaseClientProvider));
  ref.onDispose(client.close);
  return client;
});
final gatewayUploadRunnerProvider = Provider<GatewayUploadRunner?>((ref) {
  final client = ref.watch(gatewayClientProvider);
  if (client == null) return null;
  return GatewayUploadRunner(
    client: client,
    repo: ref.watch(driveUploadRepoProvider),
  );
});
