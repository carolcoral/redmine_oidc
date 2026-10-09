# Contributing

## Setup

No database or Rails boot is required for development:

```bash
gem install minitest activesupport simplecov webmock
```

## Running checks

```bash
bash scripts/quality-gate.sh
```

That runs, in order:

1. the full unit suite with an 80% line-coverage floor,
2. an explicit re-check of the coverage threshold,
3. `ruby -c` over every source file,
4. locale key parity between `en.yml` and `zh.yml`.

Individual pieces:

```bash
ruby -Ilib -Itest test/run.rb          # tests only
ruby -Ilib -Itest test/unit/claims_test.rb   # one file
ruby -U scripts/check_locales.rb       # locales only
ruby -c init.rb                        # syntax only
```

## Layout

Put protocol logic in `lib/redmine_oidc/` and keep it free of Rails calls where
possible — that is what makes it testable without a database. Controllers should
stay thin: parse input, delegate, render.

## Tests

`test/test_helper.rb` shims the small slice of Rails the code touches
(`Rails.cache`, `Rails.logger`, `Setting`, `I18n`). Tests that need Net::HTTP use
WebMock.

When you add behaviour, add a test that would fail without it. Security-relevant
paths (token verification, state/nonce checks, admin promotion, back-URL
sanitisation) need a test that asserts the *rejection*, not just the happy path.

## Style

- `# frozen_string_literal: true` at the top of every Ruby file.
- Comments explain *why*, not *what*. If a line needs a comment to be
  understandable, prefer rewriting the line.
- Keep methods short enough to read on one screen.
- Chinese comments are fine in docs and scripts; keep code comments in English so
  the plugin stays reviewable upstream.

## Migrations

Name them `db/migrate/<timestamp>_<description>.rb`. `scripts/check-migration.sh`
fails the build on syntax errors or duplicate version numbers, because either
would break `rake redmine:plugins:migrate` in production.
