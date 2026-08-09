/// The functional `dart:io` LAN sync transport now lives in the core package
/// (`openminis_core` → `src/sync/sync_peer.dart`) so it can be shared by the
/// Flutter app and the standalone web server. This file re-exports it for the
/// Flutter UI layer that referenced it here.
library;

export 'package:openminis_core/openminis.dart'
    show LanSyncTransport, SyncBatch, SyncTransport;
