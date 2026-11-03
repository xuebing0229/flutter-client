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
const engineConfig = {
  canvasKitForceCpuOnly: isAndroid,
  verboseBuildSelection: true,
};

window.adventurersGuildBootStage?.('加载 Flutter 入口脚本…');

Promise.resolve(
  _flutter.loader.load({
    onEntrypointLoaded: async function(engineInitializer) {
      try {
        window.adventurersGuildBootStage?.('初始化 Flutter 引擎…');
        const appRunner = await engineInitializer.initializeEngine(engineConfig);
        window.adventurersGuildBootStage?.('启动 Dart 应用…');
        await appRunner.runApp();
        window.adventurersGuildBootStage?.('应用已启动，等待首帧…');
      } catch (error) {
        window.adventurersGuildBootFailure?.('Flutter 引擎或应用启动失败', error);
        throw error;
      }
    },
  }),
).catch((error) => {
  window.adventurersGuildBootFailure?.('Flutter 入口加载失败', error);
});
