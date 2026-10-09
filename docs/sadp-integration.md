# SADP 接入指南

本文说明如何把 Redmine 接到 [SADP](https://cnb.cool/xindu.site/sadp) 统一登录，
以及联调与排障时最常踩的坑。SADP 是标准 OIDC Provider，插件走标准授权码模式，
无任何服务端特化代码。

## 一、在 SADP 注册客户端

1. 登录 SADP 管理后台（`/admin`）；
2. 「系统管理」新增系统，**系统名要记住**——插件靠它决定是否授予管理员；
3. 进入「OIDC 应用」→「新增接入应用」，从门户系统下拉选择刚建的系统，
   系统名与回调地址会自动带入；
4. 把回调地址改成 Redmine 的实际地址：

   ```
   https://redmine.example.com/oidc/callback
   ```

   必须**逐字节一致**（协议、主机、端口、路径、结尾斜杠），否则授权阶段报
   `invalid_redirect_uri`；
5. 授权范围勾选 `openid profile email`；
6. 授权模式勾选 `authorization_code` 与 `refresh_token`；
7. 保存后复制 `client_id` 与 `client_secret`（密钥只展示一次）。

## 二、填写插件配置

管理 → OIDC 单点登录：

| 字段 | 值 |
|---|---|
| 启用 OIDC 单点登录 | 勾选 |
| Issuer | SADP 的对外地址，**不带端点路径**，例如 `https://sso.example.com` |
| 客户端标识 | 上一步的 `client_id` |
| 客户端密钥 | 上一步的 `client_secret` |
| 授权范围 | `openid profile email` |
| 服务端管理员组 | 填第 1 步的系统名（希望 SADP 管理员在 Redmine 里也是管理员时） |

保存后点「测试连接」，应当看到 `连接正常 ... (N keys)`。若报 issuer 不匹配，
说明插件配的地址与 SADP 认定的地址不一致。

## 三、Issuer 与内网地址（最常见的坑）

SADP 支持按请求地址动态推导 issuer。两种部署方式：

**多入口（推荐）**：SADP 的 `SADP_ISSUER` 留空，
`SADP_ALLOW_MULTIPLE_ISSUERS=true`（默认）。此时插件的 Issuer 填
**你实际访问 SADP 的那个地址**，例如内网用 `http://10.0.0.5:8080`，
插件就填 `http://10.0.0.5:8080`。

**固定唯一入口**：SADP 配 `SADP_ISSUER=https://sso.example.com` 且
`SADP_ALLOW_MULTIPLE_ISSUERS=false`。此时插件必须填同一个地址，
且 Redmine 与 SADP 之间网络可达。

> 不要把端点路径写进 issuer。子路径部署用 SADP 的 `SADP_BASE_PATH`，
> 插件的 Issuer 仍然只填域名。

## 四、权限与管理员

SADP 会下发 `system_*` 系列声明。插件的处理方式：

| 声明 | 插件行为 |
|---|---|
| `system_admin: true` 且 `system_name` 等于配置的组名 | 把该用户提升为 Redmine 管理员 |
| `system_role: "admin"` | 同上（兼容口径） |
| 组名留空 | 永远不提升，这是默认值 |
| 声明缺失 | 按普通用户处理，不拒绝登录 |

插件**不使用** `system_permissions` / `system_pages` 做功能级管控——
Redmine 的权限模型是角色制，按页面码逐点映射既不可靠也难以维护。
需要精细权限时，用 SADP 的组映射到 Redmine 角色（`default_role_ids`）。

## 五、正式环境部署

`.cnb.yml` 里 `main` 分支 push 会触发 `deploy-production`，需要组织密钥仓库
`xindu.site/secrets` 提供以下变量：

| 变量 | 说明 |
|---|---|
| `DEPLOY_HOST` | Redmine 主机 |
| `DEPLOY_USER` | SSH 用户 |
| `DEPLOY_PORT` | SSH 端口，默认 22 |
| `DEPLOY_SSH_KEY` | SSH 私钥内容 |
| `REDMINE_HOME` | Redmine 根目录 |
| `REDMINE_SERVICE` | 服务名，默认 `redmine` |
| `REDMINE_URL` | 站点访问地址，供冒烟测试使用 |

部署流程：同步插件代码 → 跑数据库迁移 → 重启服务 → 冒烟测试。
任一步失败即中断，不会留下半成品状态。

## 六、排障

| 现象 | 原因 | 处理 |
|---|---|---|
| 回调报 `invalid_redirect_uri` | 回调地址与注册值不一致 | 逐字节比对，注意结尾斜杠 |
| `issuer mismatch` | 插件 Issuer 与 SADP 实际地址不同 | 改成实际访问地址，去掉端点路径 |
| 授权端点 400 且无提示 | SADP 把路径写进了 `SADP_ISSUER` | 改为 `SADP_ISSUER` + `SADP_BASE_PATH` |
| 登录成功但立刻跳回登录页 | 跨域 Cookie 未发送 | 让 Redmine 与 SADP 同域，或经反代统一入口 |
| 拿不到邮箱 | 未申请 `email` scope | 在 SADP 客户端勾选 `email`，并确认账号已绑定邮箱 |
| 自动开户失败 | 登录名或邮箱冲突 | 检查 Redmine 是否已有同邮箱账号；插件会按顺序匹配 |
| 改了权限但用户看到的还是旧的 | 权限声明在令牌签发时写入 | 重新登录 |
