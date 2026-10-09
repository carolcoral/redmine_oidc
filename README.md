# Redmine OIDC Plugin

OpenID Connect single sign-on for **Redmine 6.x**, built and tested against the
[SADP](https://cnb.cool/xindu.site/sadp) identity provider.

Users sign in with their existing SADP account instead of a separate Redmine
password, and the plugin keeps Redmine and the provider in sync on every login.

## Features

- **Authorization Code flow** with `state` + `nonce` protection
- **RS256 ID token verification** against the provider JWKS (`iss` / `aud` / `exp` / `nbf` / `nonce`)
- **Explicit user binding** — subject → login → email → create, in that order
- **Optional auto-provisioning** with configurable default roles
- **Optional admin promotion** gated on a provider group, off by default
- **RP-initiated logout** when the provider advertises `end_session_endpoint`
- **Admin settings screen** with a one-click connectivity test
- No extra gems — uses `net/http` and `openssl` from the Ruby stdlib

## Requirements

- Redmine 6.0 or newer
- Ruby 3.1+ (Redmine 6.x ships with Ruby 3.1–3.3)
- An OIDC provider with a discovery document, e.g. SADP

## Installation

```bash
cd /path/to/redmine/plugins
git clone https://cnb.cool/xindu.site/redmine_oidc.git redmine_oidc

cd /path/to/redmine
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
touch tmp/restart.txt
```

## Configuration

Log in as an administrator and open **Administration → OIDC Single Sign-On**.

### Provider

| Setting | Notes |
|---|---|
| Enable OIDC single sign-on | Master switch. Everything below is ignored while off. |
| Issuer | Provider's public base URL, **without** any endpoint path. Example: `https://sso.example.com` |
| Client ID / Client secret | From the provider's application registration |
| Callback URL override | Leave blank unless Redmine cannot infer its public URL behind a proxy |
| Scopes | Defaults to `openid profile email` |

Register the callback URL at the provider **byte for byte** — protocol, host,
port, path and trailing slash all matter. The settings page shows the URL the
plugin will actually send.

> For SADP: leave `SADP_ISSUER` empty so the provider derives the issuer from the
> request, or set it to the exact URL you use to reach SADP. Do not append an
> endpoint path to the issuer — use `SADP_BASE_PATH` instead.

### Users

| Setting | Notes |
|---|---|
| Login button label | Text on the sign-in page button |
| Create users on first login | Off means only pre-existing accounts can sign in |
| Update name and email from the provider | Local edits are preserved when off |
| Default roles for new users | Applied only when creating an account |
| Provider admin group | Must match the provider's `system_name` or any `oidc_roles` name; blank disables promotion |

### Behaviour

| Setting | Notes |
|---|---|
| Redirect the login page to the provider | Hands off immediately, no button click needed |
| Sign out at the provider on logout | Uses `end_session_endpoint` when available |
| Verify TLS certificates | Turn off only for self-signed certs on internal hosts |
| HTTP timeout | Seconds, applies to discovery, token and userinfo calls |

## How users are matched

On every successful login the plugin resolves the account in this order:

1. A user already bound to the provider `sub`
2. A user whose Redmine login equals the provider's `preferred_username`
3. A user whose email equals the provider's verified `email`
4. A newly created account, if auto-provisioning is enabled

The first match wins, and the account is then bound to the subject so later
logins short-circuit at step 1. If nothing matches and auto-provisioning is off,
the login is rejected with a clear message.

Because the binding is stored on the user row, renaming an account on either side
does not break the association.

## Security notes

- The client secret never leaves the server; the browser only ever sees `state` and `nonce`.
- ID tokens are verified against the live JWKS. `alg: none` and HMAC-signed tokens are rejected outright.
- Auto-redirect (`Redirect the login page to the provider`) removes the local form from view. Set
  `hide_local_login` in the settings hash if you also want to reject password logins for non-admins.
- Admin promotion requires a configured group name **and** a matching `system_name` or `oidc_roles` entry (SADP's role path omits `system_name`). Leaving the group blank makes that path dead code.
- Passwords are generated as 32 random bytes for provisioned accounts, so OIDC-only users cannot be brute-forced locally.

## Development

```bash
# Run the suite with coverage
bash scripts/quality-gate.sh

# Ruby syntax + locale consistency only
ruby -c init.rb
ruby -U scripts/check_locales.rb
```

Tests live in `test/unit` and run against a lightweight Rails shim in
`test/test_helper.rb`, so the suite needs no database and takes about five
seconds. Line coverage must stay at or above 80%.

### Repository layout

```
app/controllers/          HTTP entry point for the OIDC flow
app/controllers/redmine_oidc/
                          Admin settings controller, callback URL builder
app/views/                Login button, failure page, settings form
config/locales/           English and Chinese strings
lib/redmine_oidc/         Protocol and provisioning logic (pure Ruby)
db/migrate/               Adds users.oidc_subject
test/unit/                Unit tests
scripts/                  Quality gate, migration check, deploy, smoke test
.cnb.yml                  CI: test on every push/PR, deploy on main
```

## License

MIT
