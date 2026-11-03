{{flutter_js}}
{{flutter_build_config}}

const pwaBuildId = '__PWA_BOOT_VERSION__';
const versionQuery = 'v=' + encodeURIComponent(pwaBuildId);
for (const build of _flutter.buildConfig?.builds ?? []) {
  if (typeof build.mainJsPath !== 'string') continue;
  build.mainJsPath += build.mainJsPath.includes('?')
    ? '&' + versionQuery
    : '?' + versionQuery;
}

const userAgent = window.navigator.userAgent || '';
const isAndroid = /Android/i.test(userAgent);

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: isAndroid,
  },
});
