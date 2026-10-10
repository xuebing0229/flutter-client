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
- GET /v1/licenses
- POST /v1/licenses/import
- POST /v1/licenses/reserve
- POST /v1/licenses/{accountId}/commit
- PATCH /v1/licenses/{accountId}/note
- POST /v1/licenses/{accountId}/sold
- DELETE /v1/licenses/{accountId}
- POST /v1/activate

## 给部署 Agent

仓库内已经提供 `DEPLOY_AGENT.md`，包含稀疏拉取、部署、安全边界、验收命令和最终报告要求。
