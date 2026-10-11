import 'package:flutter_app/core/sync/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restore rolls workspace back when applying imported data fails', () async {
    var rolledBack = false;
    var committed = false;

    await expectLater(
      runWorkspaceRestoreTransaction(
        applyWorkspace: () async {
          throw StateError('apply failed');
        },
        commitSyncHistory: () async {
          committed = true;
        },
        rollbackWorkspace: () async {
          rolledBack = true;
        },
      ),
      throwsStateError,
    );

    expect(committed, isFalse);
    expect(rolledBack, isTrue);
  });

  test('restore rolls workspace back when sync-history commit fails', () async {
    var workspace = 'old';

    await expectLater(
      runWorkspaceRestoreTransaction(
        applyWorkspace: () async {
          workspace = 'imported';
        },
        commitSyncHistory: () async {
          throw StateError('commit failed');
        },
        rollbackWorkspace: () async {
          workspace = 'old';
        },
      ),
      throwsStateError,
    );

    expect(workspace, 'old');
  });

  test('successful restore never runs rollback', () async {
    var workspace = 'old';
    var rolledBack = false;

    await runWorkspaceRestoreTransaction(
      applyWorkspace: () async {
        workspace = 'imported';
      },
      commitSyncHistory: () async {},
      rollbackWorkspace: () async {
        rolledBack = true;
        workspace = 'old';
      },
    );

    expect(workspace, 'imported');
    expect(rolledBack, isFalse);
  });
}
