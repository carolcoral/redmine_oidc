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
| 服务端管理员组 | 见下方「四、权限与管理员」，填系统名或角色名 |

> SADP 的 `client_secret` 由平台生成，是 base64url 字符集（字母数字加 `-` `_`）。
> 插件按标准 Basic 认证原样发送，不做二次转义。

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

SADP 会下发 `system_*` 系列声明，但**两条下发路径的字段并不相同**：

| 路径 | 何时触发 | 关键声明 |
|---|---|---|
| 角色路径 | 在「用户管理」给用户分配了 OIDC 角色 | `system_admin` / `system_role` / `system_permissions` / `_pages` / `_page_tree` / `oidc_roles`，**但没有 `system_name`** |
| 逐系统路径 | 在「接入系统权限」按系统纳管 | 除上述外**额外**带 `system_name` / `system_roles` |

插件的管理员提升判定（三者同时满足）：

1. `system_admin == true` 或 `system_role == "admin"`；
2. **配置了**「服务端管理员组」（留空 = 永远不提升，默认值）；
3. 组名与 `system_name` **或** `oidc_roles` 中任一角色名大小写不敏感相等
   （`admin` 为保留值，始终命中）。

第 3 条同时比对系统名与角色名，是因为角色路径**不下发 `system_name`**——
若只比对系统名，走角色路径的管理员永远无法提升。因此：

- 想让 SADP 里某个角色的人在 Redmine 也是管理员 → 组名填**角色名**；
- 想按系统整体放行 → 组名填**系统名**（仅逐系统路径有效）。

插件**不使用** `system_permissions` / `system_pages` 做功能级管控——
Redmine 的权限模型是角色制，按页面码逐点映射既不可靠也难以维护。
需要精细权限时，用 SADP 的角色映射到 Redmine 角色（`default_role_ids`）。

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
