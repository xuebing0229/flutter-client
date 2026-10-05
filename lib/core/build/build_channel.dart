enum BuildChannel {
  beta,
  release,
}

const String _channelName = String.fromEnvironment(
  'APP_CHANNEL',
  defaultValue: 'release',
);

const BuildChannel buildChannel =
    _channelName == 'beta' ? BuildChannel.beta : BuildChannel.release;

const bool isBetaBuild = buildChannel == BuildChannel.beta;
