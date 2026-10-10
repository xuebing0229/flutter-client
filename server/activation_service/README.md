# 冒险者公会激活服务

这是一个独立、可迁移的小型授权服务。它不是账号后端，也不承载用户业务数据。

它只负责：

- 多个发码器管理员共享同一份激活码账本
- 服务器原子分配全局编号和 accountId
- 记录谁生成、谁售出、是否已经核销
- 保证同一枚激活码只能成功进行一次首次注册

不会上传或保存账号名、登录密码、头像、排单、成品、图片附件或 P2P 同步内容。

已经注册的冒险者公会账号，登录、离线使用、备份和设备同步都不依赖这个服务。未来即使关闭服务器，也只会停止新账号注册。

## 数据库

默认使用 SQLite：/var/lib/adventure-license/license.db

主要表：licenses（激活码与核销状态）、admins（管理员身份，服务器只保存 token 摘要）、audit_log（操作日志）。

激活码和 accountId 都有唯一约束。首次核销使用 SQLite 写事务，避免两台设备同时提交同一码时双双成功。

## 发码流程

Ed25519 私钥仍只保留在发码器设备安全存储中，不上传服务器。

1. POST /v1/licenses/reserve：服务器原子分配全局编号和 accountId。
2. 发码器在本机用既有 Ed25519 私钥签出 AW2 激活码。
3. POST /v1/licenses/{accountId}/commit：服务器用内置公钥验签并登记完整激活码。

旧版离线发码历史在首次连接时通过 POST /v1/licenses/import 迁移，服务器会重新验签并尽量保持原编号。

## 买家首次注册

买家 App 本地先验签，然后只向 POST /v1/activate 提交 activationCode 和 claimId。

未核销时服务器记录 redeemed_at 和 claimId；同一 claimId 重试视为同一次注册；其他 claimId 再使用同一码则返回 already_redeemed。

App 只有在服务器核销成功后才创建本地账号。创建完成后，普通登录、使用和同步不再查询激活服务器。

## 管理员

部署时生成长随机 LICENSE_ADMIN_SETUP_KEY。每台发码器首次加入时输入管理昵称和接入密钥，服务器返回独立管理员 token。

token 原文保存在发码器 Android Keystore 加密存储中，服务器只保存 SHA-256 摘要。

## Debian / Ubuntu 一键部署

准备好指向服务器的域名后，在本目录运行：

`chmod +x deploy.sh && LICENSE_DOMAIN=license.example.com CERTBOT_EMAIL=you@example.com ./deploy.sh`

`deploy.sh` 会完成依赖安装、systemd 服务、Nginx、Let's Encrypt HTTPS、SQLite 初始化、每日备份和首次健康检查。

如果只是先安装本地 API、不配域名，可以单独运行 `install.sh`。

API 默认只监听 127.0.0.1:8765，由 Nginx 对外提供 HTTPS。

每日 SQLite 快照默认保存在 `/var/backups/adventure-license`，保留 14 天；对应 systemd timer 为 `adventure-license-backup.timer`。

## 域名与构建

将一个域名或子域名 A 记录指向服务器 IP，按 nginx.conf.example 配置 Nginx，再使用 Certbot 申请证书。

正式 App 和发码器必须使用 HTTPS。三个构建工作流都已经读取 GitHub Secret ACTIVATION_API_BASE_URL，例如：https://license.example.com

## 迁移 / 停运

迁移只需要 SQLite 数据库、/etc/adventure-license/service.env 和同一套服务代码，不绑定任何云厂商。

如果彻底停止运营而不迁移，已有账号仍然正常使用；只是不能再创建新账号。

## 主要接口

- GET /health
- POST /v1/admin/register
- GET /v1/admin/me
- PATCH /v1/admin/me
- GET /v1/licenses?limit=500&beforeId=12345（管理员鉴权；稳定按全局编号倒序分页，返回 nextBeforeId；不再只显示最近 500 条）
- POST /v1/licenses/import
- POST /v1/licenses/reserve
- POST /v1/licenses/{accountId}/commit
- PATCH /v1/licenses/{accountId}/note
- POST /v1/licenses/{accountId}/sold
- DELETE /v1/licenses/{accountId}
- POST /v1/activate

## 给部署 Agent

仓库内已经提供 `DEPLOY_AGENT.md`，包含稀疏拉取、部署、安全边界、验收命令和最终报告要求。


## 发码器完整历史分页上线顺序

需要先更新 **license.apixb.top** 运行的本项目激活服务代码，再发布包含分页客户端的新版发码器。

`GET /v1/licenses?limit=500` 最多返回 500 条，响应示例为：

```json
{"ok":true,"licenses":[{"serial":"001205","accountId":"..."}],"nextBeforeId":706}
```

其中 `licenses` 中的每一项在真实接口里包含完整授权记录字段；示例只展示识别分页必需的字段。`nextBeforeId` 等于本页最后一项的全局整数 ID，仅当还有较老的记录时才返回整数；没有下一页则为 `null`。下次发送 `beforeId=<nextBeforeId>`，这样在拉取过程中即使产生新激活码，也不会导致 OFFSET 错位或重复。删除/作废的记录按旧规则不出现在查询结果中，数据库序号始终不重用。

新发码器会连续请求所有页面，收到完整结果后才替换本机历史缓存；网络中断、游标异常或重复记录均不会把旧缓存替换成部分结果。**如果旧服务器返回整整 500 条却不包含分页字段，客户端将拒绝当作完整历史保存，并要求先升级服务器。** 少于 500 条的旧服务响应仍兼容。

注意：此仓库代码、单元测试及 GitHub Actions 通过不代表服务器已经完成线上部署。需要在服务实际更新后使用已授权管理员测试超过 500 条记录的完整查询。


## 激活与管理员注册限流

`deploy.sh` 会把限流区域写入 Nginx 的 `/etc/nginx/conf.d/adventure-license-rates.conf`（HTTP 上下文），并且仅在两条敏感路径启用按客户端真实连接 IP 的防滥用限制：

- `POST /v1/admin/register`：基础速率每分钟 3 次，每个 IP 容许瞬时突发 3 次。
- `POST /v1/activate`：基础速率每分钟 30 次，容许瞬时突发 15 次，兼顾移动运营商共享 IP 与用户断线重试。
- 超额返回 HTTP 429。新版发码器与冒险者公会注册页会把普通 Nginx HTML 429 正确识别为「请求过于频繁，请稍后重试」，不会显示 JSON 解析异常。

其它 HTTPS API 路径不受这两项专用频率限制（仍受正常认证、输入校验、SQLite 原子事务保护）。如有多级反代，只允许信任自己管理的最前置反代的真实 IP 头；默认直接使用 `$binary_remote_addr`，不直接信任用户提交的 X-Forwarded-For。

手工部署请一并安装 `nginx.rate-limits.conf.example` 与 `nginx.conf.example`，否则 `limit_req` 会因缺少 `zone` 而导致 Nginx 检查失败。升级前备份现有配置并运行 `nginx -t`，再 reload。**代码在独立审计分支通过测试不意味着线上 Nginx 已经应用这些限制。** 需要在 `license.apixb.top` 的真实部署中确认 429、合法注册、管理员接入与共享 IP 误限情况。
