{{flutter_js}}
{{flutter_build_config}}

const userAgent = window.navigator.userAgent || '';
const isAndroid = /Android/i.test(userAgent);

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: isAndroid,
  },
});
