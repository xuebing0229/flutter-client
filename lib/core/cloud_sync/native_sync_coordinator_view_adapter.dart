import '../sync/sync_coordinator.dart';
import '../sync/sync_coordinator_view.dart';

/// Presentation-only adapter for the native coordinator.
///
/// The native SyncCoordinator remains the byte-for-byte Beta 182 source.
/// Shared PWA/native widgets consume this tiny view instead of requiring any
/// interface or relay changes inside the Syncthing-backed coordinator itself.
class NativeSyncCoordinatorViewAdapter implements SyncCoordinatorView {
  const NativeSyncCoordinatorViewAdapter(this.coordinator);

  final SyncCoordinator coordinator;

  @override
  Set<String> get conflictedOrderIds => coordinator.conflictedOrderIds;

  @override
  Set<String> get conflictedProductIds => coordinator.conflictedProductIds;

  @override
  Future<void> flushNow() => coordinator.flushNow();

  @override
  void addListener(void Function() listener) => coordinator.addListener(listener);

  @override
  void removeListener(void Function() listener) =>
      coordinator.removeListener(listener);
}
