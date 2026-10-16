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

// Feature/changelog lineage for Internal builds. This is not the app version
// and is never exposed as user-facing version metadata.
const int internalSourceBuild = int.fromEnvironment(
  'INTERNAL_SOURCE_BUILD',
  defaultValue: 0,
);

// Independent Internal release sequence used by Adventurer News. Keep source
// build lineage separate: e.g. Internal 0.1.3 may be promoted from Beta 156.
const int internalReleaseBuild = int.fromEnvironment(
  'INTERNAL_RELEASE_BUILD',
  defaultValue: 0,
);
