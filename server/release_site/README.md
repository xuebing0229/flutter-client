# 内测下载站部署说明

这个目录只负责把“冒险者公会”内测版放到现有的 `license.apixb.top` 上，不新增域名，也不改激活 API。

## 一次性服务器准备

1. 生成一对专门用于 GitHub Actions 发布的 SSH 密钥，不要复用 root 登录密钥。
2. 把公钥交给服务器脚本，把私钥保存到 GitHub 仓库 Secret：
   `INTERNAL_RELEASE_SSH_KEY`。
3. 在香港服务器执行：

```bash
cd /opt/adventure-license-src/server/release_site
chmod +x prepare_server.sh
RELEASE_DEPLOY_PUBLIC_KEY='ssh-ed25519 AAAA...' ./prepare_server.sh
```

脚本会：

- 继续复用 `license.apixb.top` 的 HTTPS / Nginx；
- 增加 `/releases/` 静态目录；
- 创建受限用途的 `adventure-release` 用户；
- 创建 `/srv/adventure-releases`；
- 不修改激活服务的数据库和 127.0.0.1:8765 API。

## GitHub Secret

在 `xuebing0229/flutter-client` 添加：

- `INTERNAL_RELEASE_SSH_KEY`：上面那对发布密钥的私钥。

发布工作流固定连接：

- Host: `license.apixb.top`
- User: `adventure-release`
- Path: `/srv/adventure-releases`

## 验收

```bash
nginx -t
curl -I https://license.apixb.top/releases/
curl -fsS https://license.apixb.top/health
```

网页首次部署前 `/releases/` 返回 404 是正常的；第一次成功发布内测版后会出现下载页。
