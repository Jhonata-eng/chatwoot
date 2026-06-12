# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Ruby version**: 3.4.4 (manage via `rbenv`, install with `rbenv install $(cat .ruby-version)`, init with `eval "$(rbenv init -)"`)
- **Run dev server**: `overmind start -f Procfile.dev` (or `pnpm dev`)
- **Seed local data**: `bundle exec rails db:seed`
- **Seed richer test data**: `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Ruby test at line**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **E2E tests**: `tests/playwright/` (Playwright, own package.json)
- **Always use `bundle exec`** for Ruby CLI tasks

## Project Overview

Chatwoot is an open-source omnichannel customer support platform (alternative to Intercom/Zendesk). It centralizes conversations from 11+ channels (Website, Email, Facebook, Instagram, WhatsApp, Telegram, Twitter, SMS, Line, Twilio, API, TikTok) into a unified inbox. Includes a Help Center portal and Captain (AI agent for support).

Version: 4.14.2 | Branch model: git-flow, base branch is `develop`.

## Tech Stack

- **Backend**: Ruby 3.4.4, Rails ~> 7.1, PostgreSQL (with pgvector), Redis, Sidekiq ~> 7.3, Puma ~> 7.2
- **Frontend**: Vue 3.5+ (Composition API with `<script setup>`), Vue Router 4, Pinia 3 (new) + Vuex 4 (legacy, still active), Vite 6.4, pnpm 10.x, Tailwind CSS 3.4
- **Real-time**: ActionCable (WebSocket)
- **Search**: OpenSearch via Searchkick
- **Auth**: Devise + devise_token_auth + devise-two-factor + Pundit + JWT + Omniauth (Google, SAML)
- **Testing**: RSpec (backend), Vitest (frontend), Playwright (E2E)
- **AI/LLM**: `lib/llm/`, `lib/captain/`, Ruby OpenAI, ai-agents gem, pgvector for embeddings

## Architecture

### Backend

Standard Rails app with a rich service layer and event-driven architecture:

- **Controllers**: `app/controllers/api/v1/` and `api/v2/` (versioned REST API), plus channel-specific controllers (`instagram/`, `twilio/`, `twitter/`, `microsoft/`, `slack_uploads/`, `linear/`, `shopify/`, `notion/`)
- **Models**: Core domain — `Account`, `User`, `Inbox`, `Conversation`, `Message`, `Contact`, `ContactInbox`. Channel models in `channel/` subdirectory.
- **Services**: `app/services/` — per-channel service classes and cross-cutting services (`contacts/`, `conversations/`, `messages/`, `reports/`, `notifications/`, `onboarding/`, `auto_assignment/`, `automation_rules/`, `macros/`, `llm_formatter/`)
- **Builders**: `app/builders/` — Builder pattern classes (Account, Agent, Campaign, ContactInbox, Conversation, Messages, Notification)
- **Presenters**: `app/presenters/` — View/serialization layer
- **Policies**: `app/policies/` — Pundit authorization (includes `captain/` subdirectory)
- **Listeners**: `app/listeners/` — Wisper pub/sub event handlers
  - **Sync** (ActionCableListener, AgentBotListener) — real-time updates
  - **Async** (AutomationRule, Campaign, CsatSurvey, Hook, Notification, Participation, ReportingEvent, Webhook) — dispatched via Sidekiq
- **Dispatcher**: `app/dispatchers/` — Singleton event dispatcher; `Dispatcher.dispatch(event_name, timestamp, data)` routes to sync listeners directly and enqueues `EventDispatcherJob` for async listeners
- **Mailers**: `app/mailers/` — `ConversationReplyMailer` (primary), admin/agent/team notifications
- **Mailboxes**: `app/mailboxes/` — ActionMailbox inbound email handlers + `imap/` for IMAP-based email channel
- **Background Jobs**: Sidekiq with 15 named queues (critical → low, plus scheduled_jobs, purgable, housekeeping, etc.). Scheduled via `config/schedule.yml` (sidekiq-cron)
- **Lib**: `lib/` — ChatwootApp module, Redis helpers, event system, LLM integration, custom exceptions (`lib/custom_exceptions/`), seeders

### Frontend

Multiple independent Vue apps sharing code via `app/javascript/shared/`:

| Entry Point | App | Purpose |
|---|---|---|
| `dashboard.js` | `app/javascript/dashboard/` | Main dashboard SPA |
| `widget.js` | `app/javascript/widget/` | Customer-facing chat widget |
| `sdk.js` | `app/javascript/sdk/` | Embeddable widget SDK (vanilla JS) |
| `v3app.js` | `app/javascript/v3/` | Next-gen Vue 3 app |
| `superadmin_pages.js` | `app/javascript/superadmin/` | Super admin panel |
| `portal.js` | `app/javascript/portal/` | Help center |
| `survey.js` | `app/javascript/survey/` | CSAT survey widget |

Dashboard routes: `dashboard/routes/dashboard/` — campaigns, captain, commands, companies, contacts, conversation, customviews, helpcenter, inbox, notifications, onboarding, settings, upgrade

Vite aliases (from `vite.shared.ts`): `vue` → vue ESM bundler, `components` → `dashboard/components`, `next` → `dashboard/components-next`, plus `dashboard`, `helpers`, `shared`, `v3`, `assets`

### Enterprise Edition Overlay

The `enterprise/` directory is a parallel Rails app tree that overlays OSS code at boot time:

- **Structure mirrors `app/`**: controllers, models, services, policies, views, jobs, listeners, mailers, initializers
- **How it works**: `ChatwootApp.enterprise?` checks for `enterprise/` directory (disable with `DISABLE_ENTERPRISE` env var). `InjectEnterpriseEditionModule` adds `prepend_mod_with`, `include_mod_with`, `extend_mod_with` to `Module` — these inject corresponding Enterprise modules via Ruby's `prepend`/`include`/`extend`
- **Premium features** (`enterprise/config/premium_features.yml`): disable_branding, audit_logs, SLA, custom_roles, Captain, CSAT review notes, conversation required attributes, advanced search, SAML, companies, voice channel, advanced assignment
- **Feature flags**: `config/features.yml` — checked via `InstallationConfig`/`GlobalConfig`; premium features gated by `ChatwootApp.enterprise?`
- **When modifying core logic**: always check for corresponding files in `enterprise/` and keep behavior compatible. Use `prepend_mod_with`/`include_mod_with` for Enterprise extensions rather than editing OSS files directly

## Code Style

- **Ruby**: Follow RuboCop rules (150 char max line length); use compact `module/class` definitions
- **Vue/JS**: ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Always use Composition API with `<script setup>` at the top; PascalCase component names; camelCase events
- **Styling**: Tailwind only — no custom CSS, no scoped CSS, no inline styles. Reference `tailwind.config.js` for color definitions
- **I18n**: No bare strings in templates. Backend → `en.yml`, Frontend → `en.json`. Only update English files; other languages handled by community
- **Frontend new components**: Use `components-next/` directory (legacy `components/` is being deprecated)
- **Error handling**: Use custom exceptions from `lib/custom_exceptions/`
- **Branding**: For user-facing strings containing "Chatwoot", prefer `replaceInstallationName` from `shared/composables/useBranding`

## General Guidelines

- MVP focus: least code change, happy-path only
- No unnecessary defensive programming; ship happy path first, iterate after confirmation
- Prefer minimal, readable code over elaborate abstractions
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code; don't write multiple versions for the same logic
- In specs: prefer `with_modified_env` over stubbing `ENV`; compare `error.class.name` over constant class equality for parallel/reloading environments

## Commit Messages & PRs

- Conventional Commits: `type(scope): subject` (scope optional)
- Do not reference Claude in commit messages
- PR descriptions: start with short user-facing paragraph, add `Closes` section with issue links, `How to test` for features, `How to reproduce` for bugfixes. Do not add `How this was tested` section

## Codex Worktree Workflow

- Use separate git worktree + branch per task for isolation
- Keep Codex-specific setup under `.codex/`, use `Procfile.worktree` for process orchestration
- `.codex/environments/environment.toml` dynamically generates per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions
- Each worktree gets its own Overmind socket/title