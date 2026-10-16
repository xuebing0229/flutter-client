# 给服务器 Agent：部署冒险者公会内测下载站

目标：在现有香港服务器 `license.apixb.top` 上复用当前 Nginx/HTTPS，新增 `/releases/` 静态下载站；不要新建域名，不要改激活 API 数据库或 127.0.0.1:8765 服务。

## 1. 更新服务器上的稀疏仓库

```bash
cd /opt/adventure-license-src
git fetch origin
git sparse-checkout set server/activation_service server/release_site
git checkout build/internal-0.1.4-from-beta-158
```

## 2. 创建专用发布 SSH 密钥

只用于 GitHub Actions 向这台服务器上传内测包，不要复用 root/日常 SSH 密钥。

```bash
install -d -m 0700 /root/adventure-release-ci
ssh-keygen -t ed25519 -N '' -f /root/adventure-release-ci/id_ed25519 -C 'adventure-release-ci'
PUB="$(cat /root/adventure-release-ci/id_ed25519.pub)"
```

## 3. 准备 Nginx 与发布目录

```bash
cd /opt/adventure-license-src/server/release_site
chmod +x prepare_server.sh
RELEASE_DEPLOY_PUBLIC_KEY="$PUB" ./prepare_server.sh
```

必须确认：

```bash
nginx -t
systemctl is-active nginx
curl -fsS https://license.apixb.top/health
getent passwd adventure-release
ls -ld /srv/adventure-releases
```

激活 API `/health` 必须继续正常，8765 必须仍只监听 loopback。

## 4. 把私钥写入 GitHub Actions Secret

如果本机 `gh auth status` 已经能操作 `xuebing0229/flutter-client`：

```bash
gh secret set INTERNAL_RELEASE_SSH_KEY \
  --repo xuebing0229/flutter-client \
  < /root/adventure-release-ci/id_ed25519
```

确认 Secret 写入成功后，删除服务器上的私钥，仅保留公钥授权：

```bash
rm -f /root/adventure-release-ci/id_ed25519
```

如果服务器没有可用的 GitHub 登录，不要擅自登录或修改其它凭据。把“无法写 GitHub Secret”作为唯一未完成项报告，并把私钥文件保留为 0600，等待主人处理。

## 5. 重新触发内测 0.1.4 发布

如果 `gh` 可用，给分支做一次空提交即可触发现有发布工作流：

```bash
cd /opt/adventure-license-src
git checkout build/internal-0.1.4-from-beta-158
git commit --allow-empty -m 'ci: publish internal 0.1.4 to release site'
git push origin build/internal-0.1.4-from-beta-158
```

注意：现有工作流只监听 `pubspec.yaml` 和 `.github/workflows/internal-build.yml` 路径，空提交不会触发。因此更稳妥的方式是直接在 GitHub Actions 中重新运行 “Build and Publish Internal” run 38894726371，或者用已认证的 GitHub CLI：

```bash
gh run rerun 38894726371 --repo xuebing0229/flutter-client
```

## 6. 最终验收

发布完成后必须验证：

```bash
curl -fsS https://license.apixb.top/releases/ >/dev/null
curl -fsS https://license.apixb.top/releases/internal/latest.json
curl -fsS https://license.apixb.top/releases/internal/android-latest.json
curl -fsS https://license.apixb.top/releases/internal/windows-latest.json
curl -fsS https://license.apixb.top/health
```

并确认版本为 `0.1.4`、channel 为 `internal`，Android/Windows 下载 URL 都指向 `license.apixb.top/releases/internal/0.1.4/`。

最终只报告：Nginx 状态、激活 API 状态、发布用户/目录状态、GitHub Secret 是否写入、工作流是否重新发布成功、四个 HTTPS 验收结果。不要打印私钥、管理员密钥、数据库内容或其它秘密。
