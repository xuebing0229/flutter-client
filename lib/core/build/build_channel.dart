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
