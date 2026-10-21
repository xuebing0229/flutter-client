# 冒险者公会 Cloudflare 同步中转

这个 Worker 同时承担两件事：

1. 托管 `build/web` 里的 PWA 静态资源。
2. 在 `/sync` 提供 Durable Object WebSocket 中转。

## 数据边界

- 排单、成品、设置、参考图等应用数据在客户端使用 AES-GCM 加密后才发送。
- Worker 不保存业务消息，不使用 Durable Object storage。
- 两端必须同时在线；离线设备不会收到排队消息。
- Worker 只根据不可读的 room id / inbox id 把当前 WebSocket 消息转给在线设备。
- 和任何联网服务一样，Cloudflare 在网络层仍可能处理 IP、连接时间等必要连接元数据；这里的“不落盘”仅指冒险者公会自己的业务同步正文和消息队列。

## PWA

PWA 与 Worker 同域部署时，不需要给 Web 端配置额外地址。浏览器默认连接当前站点的：

```
wss://当前域名/sync
```

## Android / Windows

原生端默认连接已经部署的 PWA 域名：

```
https://guild.apixb.top/sync
```

如需临时切换测试环境，也可以覆盖：

```
--dart-define=PUBLIC_SYNC_RELAY_URL=https://其他-PWA-域名/sync
```

HTTP/HTTPS 会在客户端自动转换成 WS/WSS。

## 部署

先在仓库根目录生成 PWA：

```bash
flutter build web --release --no-web-resources-cdn
python3 tool/finalize_pwa.py build/web
```

再部署 Worker：

```bash
npx wrangler deploy --config cloudflare/sync-worker/wrangler.jsonc
```

首次部署会创建 SQLite-backed Durable Object namespace，但当前代码不会向其中写入业务数据。WebSocket 使用 Hibernation API，空闲连接不会要求 Durable Object 一直驻留执行。
