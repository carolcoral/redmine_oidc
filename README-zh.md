# Redmine OIDC 插件

为 **Redmine 6.x** 提供 OpenID Connect 单点登录，基于
[SADP](https://cnb.cool/xindu.site/sadp) 身份提供方开发与验证。

用户直接用已有的 SADP 账号登录 Redmine，无需再记一套密码；每次登录插件都会
把 Redmine 侧的账号信息与服务端保持一致。

## 功能

- **授权码模式**，携带 `state` 与 `nonce` 双重防护
- **RS256 ID Token 校验**，基于服务端 JWKS 校验签名与 `iss` / `aud` / `exp` / `nbf` / `nonce`
- **明确的账号匹配顺序**：subject → 登录名 → 邮箱 → 创建
- **可选的自动开户**，支持配置新用户默认角色
- **可选的管理员提升**，需匹配服务端指定的组，默认关闭
- **RP 主动登出**，服务端提供 `end_session_endpoint` 时生效
- **后台配置页**，附一键连通性测试
- **无额外 gem 依赖**，仅使用 Ruby 标准库的 `net/http` 与 `openssl`

## 环境要求

- Redmine 6.0 及以上
- Ruby 3.1+（Redmine 6.x 通常自带 3.1–3.3）
- 支持元数据发现的 OIDC 服务端，例如 SADP

## 安装

```bash
cd /path/to/redmine/plugins
git clone https://cnb.cool/xindu.site/redmine_oidc.git redmine_oidc

cd /path/to/redmine
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
touch tmp/restart.txt
```

## 配置

用管理员账号登录，进入 **管理 → OIDC 单点登录**。

### 服务端

| 配置项 | 说明 |
|---|---|
| 启用 OIDC 单点登录 | 总开关，关闭时其余配置一律不生效 |
| Issuer | 服务端对外访问地址，**不要带端点路径**，例如 `https://sso.example.com` |
| 客户端标识 / 密钥 | 由服务端应用注册处获取 |
| 回调地址覆盖 | 一般留空；仅当 Redmine 反向代理后无法推断自身地址时填写 |
| 授权范围 | 默认 `openid profile email` |

回调地址需在服务端**逐字节登记**，协议、主机、端口、路径、结尾斜杠都算差异。
配置页会显示插件实际发出的回调地址。

> SADP 场景：`SADP_ISSUER` 建议留空由服务端按请求地址动态推导，或填写你实际访问
> SADP 的地址。不要把端点路径拼进 issuer，子路径部署请用 `SADP_BASE_PATH`。

### 用户

| 配置项 | 说明 |
|---|---|
| 登录按钮文案 | 登录页按钮上的文字 |
| 首次登录自动创建用户 | 关闭时仅允许已存在的账号登录 |
| 使用服务端资料更新姓名与邮箱 | 关闭时保留本地修改 |
| 新用户默认角色 | 仅在创建账号时应用 |
| 服务端管理员组 | 需与服务端 `system_name` 一致，留空则不提升任何管理员 |

### 行为

| 配置项 | 说明 |
|---|---|
| 登录页自动跳转到服务端 | 免点击直接跳转 |
| 登出时同时退出服务端会话 | 服务端提供 `end_session_endpoint` 时生效 |
| 校验 TLS 证书 | 仅内网自签证书场景才建议关闭 |
| HTTP 超时（秒） | 作用于发现、令牌与用户信息请求 |

## 账号匹配顺序

每次登录成功后，插件按以下顺序确定账号：

1. 已绑定该服务端 `sub` 的用户
2. 登录名等于服务端 `preferred_username` 的用户
3. 邮箱等于服务端已验证 `email` 的用户
4. 新建账号（仅在开启自动开户时）

一旦命中即停止，并立刻把账号绑定到 subject，后续登录在第 1 步就完成。
若全部未命中且未开启自动开户，登录会被明确拒绝。

绑定关系保存在用户记录上，因此任一侧改名都不会断开关联。

## 安全说明

- 客户端密钥始终留在服务端，浏览器只能看到 `state` 与 `nonce`。
- ID Token 会基于实时 JWKS 验签；`alg: none` 与 HMAC 签名的令牌一律拒绝。
- 开启「登录页自动跳转到服务端」会隐藏本地表单；如需进一步禁用普通用户的口令登录，
  可在设置中打开 `hide_local_login`。
- 管理员提升需要**同时**满足：配置了组名，且服务端下发的 `system_name` 与之一致。
  组名留空即彻底关闭该路径。
- 自动开户的账号使用 32 字节随机口令，无法被本地爆破。

## 开发

```bash
# 跑测试并校验覆盖率
bash scripts/quality-gate.sh

# 仅做语法与本地化校验
ruby -c init.rb
ruby -U scripts/check_locales.rb
```

测试位于 `test/unit`，基于 `test/test_helper.rb` 中的轻量 Rails 桩运行，
无需数据库，约五秒完成。行覆盖率须保持 80% 以上。

### 目录结构

```
app/controllers/          OIDC 流程的 HTTP 入口
app/controllers/redmine_oidc/
                          后台配置控制器、回调地址构造
app/views/                登录按钮、失败页、配置表单
config/locales/           中英文文案
lib/redmine_oidc/         协议与开户逻辑（纯 Ruby）
db/migrate/               新增 users.oidc_subject
test/unit/                单元测试
scripts/                  质量阀门、迁移检查、部署、冒烟测试
.cnb.yml                  CI：推送/PR 跑测试，main 分支自动部署
```

## 许可证

MIT
