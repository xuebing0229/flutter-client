enum BuildChannel {
  beta,
  internal,
  release,
}

const String _channelName = String.fromEnvironment(
  'APP_CHANNEL',
  defaultValue: 'release',
);

const BuildChannel buildChannel = switch (_channelName) {
  'beta' => BuildChannel.beta,
  'internal' => BuildChannel.internal,
  _ => BuildChannel.release,
};

const bool isBetaBuild = buildChannel == BuildChannel.beta;
const bool isInternalBuild = buildChannel == BuildChannel.internal;
