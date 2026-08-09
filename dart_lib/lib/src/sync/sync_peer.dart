import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_manifest.dart';
import 'sync_message.dart';

/// A batch of sync data pushed or pulled between two peers.
///
/// Carries the full sessions + messages a device needs to apply. Both LAN and
/// hub transports serialize this into JSON and exchange it (over HTTP/WS).
class SyncBatch {
  final String senderDeviceId;
  final SyncManifest manifest;
  final List<SyncMessage> messages;
  final Map<String, Map<String, dynamic>> sessions; // id -> session snapshot

  const SyncBatch({
    required this.senderDeviceId,
    required this.manifest,
    this.messages = const [],
    this.sessions = const {},
  });

  Map<String, dynamic> toJson() => {
        'senderDeviceId': senderDeviceId,
        'manifest': manifest.toJson(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'sessions': sessions,
      };

  factory SyncBatch.fromJson(Map<String, dynamic> j) => SyncBatch(
        senderDeviceId: j['senderDeviceId'] as String? ?? 'unknown',
        manifest: SyncManifest.fromJson(
            (j['manifest'] as Map?)?.cast<String, dynamic>() ?? {}),
        messages: (j['messages'] as List? ?? [])
            .map((m) => SyncMessage.fromJson((m as Map).cast<String, dynamic>()))
            .toList(),
        sessions:
            (j['sessions'] as Map?)?.cast<String, Map<String, dynamic>>() ?? {},
      );
}

/// Transport-level sync protocol. A host platform (Windows/Android Flutter app)
/// provides an implementation bound to its network stack; the [SyncEngine]
/// above stays transport-agnostic and testable.
abstract class SyncTransport {
  /// Bind/advertise this device as a sync peer. Returns the local peer id.
  Future<void> start();

  /// Pull the peer's current manifest (to compute missing changes).
  Future<SyncManifest> fetchManifest();

  /// Pull a batch of messages for sessions whose revisions the remote high-waters
  /// [highwater] don't cover, starting after [cursor] per session.
  Future<SyncBatch> pull(Map<String, int> highwater, {String? cursor});

  /// Push our snapshot + changes to the peer.
  Future<void> push(SyncBatch batch);

  Stream<SyncBatch> get onIncoming;

  Future<void> stop();
}

/// A real LAN/relay sync transport built on `dart:io` (works on both Windows,
/// Android and the web server). Speaks the OpenMinis sync batch protocol over
/// plain JSON HTTP and can also serve an inbound endpoint so a peer can push
/// to us.
///
/// Endpoints (relative to baseUrl):
///   GET  /manifest   -> SyncManifest of the peer
///   POST /pull       -> body {highwater, cursor}; returns SyncBatch
///   POST /push       -> body SyncBatch; returns {applied: n}
class LanSyncTransport implements SyncTransport {
  final String baseUrl;
  final String deviceId;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  final _incoming = StreamController<SyncBatch>.broadcast();

  // Local inbound server receiving pushes from the peer (set via serve()).
  HttpServer? _server;

  LanSyncTransport({required this.baseUrl, required this.deviceId});

  @override
  Stream<SyncBatch> get onIncoming => _incoming.stream;

  @override
  Future<void> start() async {}

  /// Optionally bind a local HTTP server so a peer can push batches to us.
  Future<void> serve({int port = 8742}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((req) async {
      if (req.method == 'POST' && req.uri.path == '/push') {
        final body = await utf8.decoder.bind(req).join();
        try {
          final batch = SyncBatch.fromJson(
              (jsonDecode(body) as Map).cast<String, dynamic>());
          _incoming.add(batch);
          req.response.statusCode = HttpStatus.ok;
          req.response.write(jsonEncode({'applied': 1}));
        } catch (e) {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write(jsonEncode({'error': '$e'}));
        }
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    });
  }

  Future<HttpClientResponse> _get(String path) async {
    return (await _client.getUrl(Uri.parse('$baseUrl$path'))).close();
  }

  Future<HttpClientResponse> _post(
      String path, Map<String, dynamic> body) async {
    final req = await _client.postUrl(Uri.parse('$baseUrl$path'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    return req.close();
  }

  static Future<Map<String, dynamic>> _readJson(
      HttpClientResponse resp) async {
    final body = await utf8.decoder.bind(resp).join();
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  @override
  Future<SyncManifest> fetchManifest() async {
    final resp = await _get('/manifest');
    if (resp.statusCode != 200) throw HttpException('manifest ${resp.statusCode}');
    return SyncManifest.fromJson(await _readJson(resp));
  }

  @override
  Future<SyncBatch> pull(Map<String, int> highwater, {String? cursor}) async {
    final resp =
        await _post('/pull', {'highwater': highwater, 'cursor': cursor ?? deviceId});
    if (resp.statusCode != 200) throw HttpException('pull ${resp.statusCode}');
    return SyncBatch.fromJson(await _readJson(resp));
  }

  @override
  Future<void> push(SyncBatch batch) async {
    final resp = await _post('/push', batch.toJson());
    if (resp.statusCode != 200) throw HttpException('push ${resp.statusCode}');
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await _incoming.close();
    _client.close(force: true);
  }
}
