/// Thin re-export so callers can import message handling in one place.
library;

/// The substantive message store lives in `persistence_adapter.dart` and the
/// facade in `chat_store.dart`.
export 'persistence_adapter.dart';
export 'chat_store.dart' show ChatStore;
