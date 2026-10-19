enum BuildChannel {
  beta,
  internal,
  release,
}

const String _channelName = String.fromEnvironment(
  'APP_CHANNEL',
  defaultValue: 'release',
);

const BuildChannel buildChannel = _channelName == 'beta'
    ? BuildChannel.beta
    : _channelName == 'internal'
    ? BuildChannel.internal
    : BuildChannel.release;

const bool isBetaBuild = buildChannel == BuildChannel.beta;
const bool isInternalBuild = buildChannel == BuildChannel.internal;

// Diagnostic lineage only: which test build this Internal release was promoted
// from. This is not shown as the Internal app version.
const int internalSourceBuild = int.fromEnvironment(
  'INTERNAL_SOURCE_BUILD',
  defaultValue: 0,
);

// Independent Internal release sequence. Adventurer News and the updater use
// this monotonic number while the visible version stays e.g. 0.1.4.
const int internalReleaseBuild = int.fromEnvironment(
  'INTERNAL_RELEASE_BUILD',
  defaultValue: 0,
);
