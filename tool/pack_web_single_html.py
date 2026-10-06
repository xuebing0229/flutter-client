#!/usr/bin/env python3
"""Pack a Flutter Web build into one self-contained offline HTML file.

The generated file does not use a service worker or network-hosted CanvasKit.
It embeds:
- the Dart2JS application,
- the Flutter loader,
- full CanvasKit + its WASM,
- Flutter runtime assets/fonts/shaders.

This is intentionally tailored to the project's portable iOS/browser build.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import mimetypes
import re
from pathlib import Path


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def script_safe(source: str) -> str:
    # Inline classic scripts must never accidentally terminate their script tag.
    return re.sub(r"</script", r"<\\/script", source, flags=re.IGNORECASE)


def read_build_config(bootstrap: str) -> dict:
    match = re.search(
        r"_flutter\.buildConfig\s*=\s*(\{.*?\});\s*\n",
        bootstrap,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit("Could not locate _flutter.buildConfig in flutter_bootstrap.js")
    config = json.loads(match.group(1))
    builds = config.get("builds")
    if not isinstance(builds, list):
        raise SystemExit("Flutter build config does not contain a builds list")

    dart2js_canvas = next(
        (
            dict(item)
            for item in builds
            if isinstance(item, dict)
            and item.get("compileTarget") == "dart2js"
            and item.get("renderer") == "canvaskit"
        ),
        None,
    )
    if dart2js_canvas is None:
        raise SystemExit("Expected a Dart2JS + CanvasKit web build")

    # mainJsPath is replaced at runtime with a Blob URL containing the embedded
    # main.dart.js. Keeping just the compatible build also prevents the loader
    # from selecting another renderer that would require external files.
    dart2js_canvas["mainJsPath"] = "__EMBEDDED_MAIN__"
    return {
        "engineRevision": config.get("engineRevision"),
        "builds": [dart2js_canvas],
    }


def collect_runtime_assets(root: Path) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    assets_root = root / "assets"
    if not assets_root.is_dir():
        raise SystemExit("Flutter assets directory is missing")

    for path in sorted(assets_root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        result[rel] = {"mime": mime, "b64": b64(path)}

    version = root / "version.json"
    if version.is_file():
        result["version.json"] = {
            "mime": "application/json",
            "b64": b64(version),
        }
    return result


def build_single_html(root: Path) -> str:
    required = [
        root / "flutter.js",
        root / "flutter_bootstrap.js",
        root / "main.dart.js",
        root / "canvaskit" / "canvaskit.js",
        root / "canvaskit" / "canvaskit.wasm",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing Flutter build files: " + ", ".join(missing))

    flutter_js = script_safe((root / "flutter.js").read_text(encoding="utf-8"))
    bootstrap = (root / "flutter_bootstrap.js").read_text(encoding="utf-8")
    build_config = read_build_config(bootstrap)

    canvaskit_js = (root / "canvaskit" / "canvaskit.js").read_text(
        encoding="utf-8"
    )
    # The generated CanvasKit bundle is an ES module only because of import.meta
    # and its final export. We initialize it ourselves as an inline classic
    # script, supplying embedded WASM through instantiateWasm.
    canvaskit_js = canvaskit_js.replace("import.meta.url", "location.href")
    canvaskit_js = canvaskit_js.replace(
        "export default CanvasKitInit;",
        "window.CanvasKitInit = CanvasKitInit;",
    )
    canvaskit_js = script_safe(canvaskit_js)

    runtime_assets = collect_runtime_assets(root)
    assets_json = json.dumps(
        runtime_assets,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    config_json = json.dumps(
        build_config,
        ensure_ascii=False,
        separators=(",", ":"),
    )

    main_b64 = b64(root / "main.dart.js")
    canvaskit_wasm_b64 = b64(root / "canvaskit" / "canvaskit.wasm")

    icon = root / "app-icon.png"
    icon_link = ""
    apple_icon_link = ""
    if icon.is_file():
        icon_data = b64(icon)
        data_uri = f"data:image/png;base64,{icon_data}"
        icon_link = f'<link rel="icon" type="image/png" href="{data_uri}">'
        apple_icon_link = f'<link rel="apple-touch-icon" href="{data_uri}">'

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="X-UA-Compatible" content="IE=Edge">
  <meta name="description" content="冒险者公会离线版 - 画师排单与成品管理">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <meta name="theme-color" content="#ffffff">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="default">
  <meta name="apple-mobile-web-app-title" content="冒险者公会">
  {icon_link}
  {apple_icon_link}
  <title>冒险者公会</title>
  <style>
    html, body {{
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #ffffff;
    }}
    #portable-boot {{
      position: fixed;
      inset: 0;
      z-index: 2147483647;
      display: flex;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
      padding: 24px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #333333;
      background: #ffffff;
      text-align: center;
      line-height: 1.55;
    }}
  </style>
</head>
<body>
  <div id="portable-boot">正在打开冒险者公会…</div>

  <script>
    const __PORTABLE_ASSETS = {assets_json};

    function __portableBase64Bytes(source) {{
      const binary = atob(source);
      const result = new Uint8Array(binary.length);
      for (let index = 0; index < binary.length; index++) {{
        result[index] = binary.charCodeAt(index);
      }}
      return result;
    }}

    // Flutter normally fetches fonts, manifests and shaders from neighboring
    // files. A portable HTML has no neighbors, so serve those requests from
    // the bytes embedded above. Unrecognized requests still use native fetch.
    const __portableNativeFetch = window.fetch.bind(window);
    window.fetch = function(input, init) {{
      const raw = typeof input === "string"
        ? input
        : ((input && input.url) || String(input));
      try {{
        const url = new URL(raw, window.location.href);
        const path = decodeURIComponent(url.pathname).replace(/^\\/+/, "");
        for (const [key, value] of Object.entries(__PORTABLE_ASSETS)) {{
          if (
            path === key ||
            path.endsWith("/" + key) ||
            url.href.endsWith(key)
          ) {{
            return Promise.resolve(
              new Response(__portableBase64Bytes(value.b64), {{
                status: 200,
                headers: {{ "Content-Type": value.mime }},
              }})
            );
          }}
        }}
      }} catch (_) {{}}
      return __portableNativeFetch(input, init);
    }};
  </script>

  <script>
{canvaskit_js}
  </script>

  <script>
{flutter_js}
  </script>

  <script>
    (async function() {{
      const boot = document.getElementById("portable-boot");
      try {{
        const canvasKitWasm = __portableBase64Bytes(
          "{canvaskit_wasm_b64}"
        );

        window.flutterCanvasKit = await window.CanvasKitInit({{
          instantiateWasm: function(imports, receiveInstance) {{
            WebAssembly.instantiate(canvasKitWasm, imports).then(function(result) {{
              receiveInstance(result.instance, result.module);
            }});
            return {{}};
          }},
        }});

        const mainBytes = __portableBase64Bytes("{main_b64}");
        const mainUrl = URL.createObjectURL(
          new Blob([mainBytes], {{ type: "application/javascript" }})
        );

        window._flutter = window._flutter || {{}};
        const buildConfig = {config_json};
        buildConfig.builds[0].mainJsPath = mainUrl;
        window._flutter.buildConfig = buildConfig;

        if (boot) boot.remove();

        await window._flutter.loader.load({{
          config: {{
            renderer: "canvaskit",
            canvasKitVariant: "full",
          }},
        }});
      }} catch (error) {{
        console.error(error);
        if (boot) {{
          boot.textContent =
            "打开失败。请换用 Safari / Chrome 再试；如果仍然失败，请保留这个 HTML 文件并联系提供者。\\n\\n" +
            String(error);
          boot.style.whiteSpace = "pre-wrap";
        }}
      }}
    }})();
  </script>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("build_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    root = args.build_dir.resolve()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    document = build_single_html(root)
    output.write_text(document, encoding="utf-8")

    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"Packed portable HTML: {output} ({size_mb:.1f} MiB)")


if __name__ == "__main__":
    main()
