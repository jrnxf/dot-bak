---
name: workers-builds
description: 'Set up, move to, debug and maintain Cloudflare Workers deployed by Cloudflare Workers Builds (git-connected builds) instead of GitHub Actions. Use when connecting a repo to Builds, replacing a wrangler deploy workflow, reading a failed "Workers Builds: <worker>" check, managing build tokens, or turning off preview builds.'
license: MIT
metadata:
  tags: "Cloudflare, Workers, CI, Deploy"
  category: "devops"
---

# Workers Builds

Cloudflare Workers Builds clones the repo on each push, runs a build command, then a deploy command, and reports a GitHub check named `Workers Builds: <worker>`. No Cloudflare token lives in GitHub.

## Ground rules

- Use the API, not the dashboard, for anything repeatable. The dashboard hides settings (preview builds, token names) and some of its labels go stale.
- Load the Cloudflare token only inside a subshell from a keys file: `(set -a; . ~/.cloudflare-keys; set +a; <cmd>)`. Never echo it, never put it on a command line.
- The token calling the Builds API must be a **user** token (account-owned tokens get "Invalid token") with Workers Builds Configuration: Edit, plus Workers Scripts: Read to look up Worker tags.
- Ask before anything that touches production data: a first production build runs the deploy command, which often applies remote D1 migrations.

## API map

Base: `https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID`

| Need | Call |
|---|---|
| Worker tag (the Builds API's `external_script_id`) | `GET /workers/scripts` -> `.result[] | {id, tag}` |
| Triggers on a Worker | `GET /builds/workers/<tag>/triggers` |
| Create a trigger | `POST /builds/triggers` |
| Change a trigger | `PATCH /builds/triggers/<trigger_uuid>` |
| Build variables | `PATCH /builds/triggers/<trigger_uuid>/environment_variables` with `{"NAME":{"value":"x","is_secret":false}}` (merges, keeps others) |
| Run a build | `POST /builds/triggers/<trigger_uuid>/builds` with `{"branch":"main"}` |
| Builds for a Worker | `GET /builds/workers/<tag>/builds` |
| One build / its log | `GET /builds/builds/<build_uuid>` and `.../logs` (`.result.lines[][1]`) |
| GitHub repo link | `PUT /builds/repos/connections` with provider ids (GitHub user id and repo id from `api.github.com`) |
| Build tokens | `GET /builds/tokens`, `POST /builds/tokens`, `DELETE /builds/tokens/<uuid>` |
| Per-branch previews | `GET /builds/workers/<tag>/previews`, `PATCH .../previews/<preview_id>` with `{"auto_build":false}` |

A 404 "No build configuration" on `/triggers` means nothing is connected for that tag, not that the API is wrong.

## Setting up a Worker

1. Read the repo: `wrangler.json(c)`/`wrangler.toml` `name` (the Worker), package manager and version (`packageManager`), and what the old workflow ran (checks, migrations, build env).
2. Link the repo (`PUT /builds/repos/connections`), then create two triggers on the Worker tag:
   - **Production**: `branch_includes: ["main"]`, deploy command = the real deploy, for example `bunx wrangler d1 migrations apply <db> --remote && bunx wrangler deploy`.
   - **Branches**: `branch_includes: ["*"]`, `branch_excludes: ["main"]`, deploy command `<pm> wrangler versions upload`. This gives PRs a check without going live. Never put migrations here.
3. Same build command on both, and make it run the project's checks (for example `bun run preflight && bun run build`) so no GitHub check-only job is needed.
4. Monorepo: set `root_directory` (for example `/admin`) and `path_includes: ["admin/*"]` so it only builds for its own changes.
5. Pin the toolchain with build variables. Builds defaults are old (bun 1.2.x): set `BUN_VERSION`, `NODE_VERSION`, `PNPM_VERSION` to what the repo uses.
6. Build-time values only go in build variables (for example `VITE_*` inlined into the client bundle). Runtime secrets stay on the Worker (`wrangler secret put`). A browser Sentry DSN is public; a Sentry auth token is a secret.
7. Run a branch build via the API and wait for green before deleting the old deploy path. A build started from the API does not post a GitHub check; push a commit for that.
8. If the dashboard already created a trigger with defaults (`bun run build` / `npx wrangler deploy`, root `/`), `PATCH` it rather than creating a duplicate (`12042 A trigger already exists`).

## Moving off GitHub Actions

1. PR that deletes the deploy workflow, says "do not merge until Builds is green", and lists the exact Builds settings.
2. Make the build pass with an empty environment (env validation can throw on import; give tests placeholder env in a test preload).
3. After the first green production build on main: delete the now-unused GitHub secrets and variables (`gh secret list/delete`, `gh variable list/delete`), delete an empty deploy environment, and revoke the old CI API tokens.

## Failure patterns

| Symptom | Cause | Fix |
|---|---|---|
| Check fails in about 1 second, log ends in wrangler's help text or "missing a `previews` block" | Worker Previews: new Workers run `npx wrangler preview` on every non-main push | `PATCH /builds/workers/<tag>/previews/<id>` `{"auto_build":false}` per branch preview; the branches trigger above covers PR checks. Deleting the preview trigger does not help: it comes back on the next push |
| Build runs defaults, fails | Build ran before settings were saved, or a dashboard-made trigger kept defaults | `PATCH` the trigger, rerun |
| Tests pass locally, fail in Builds | Different bun/node version changes file order and exposes test state leaks | Pin the version, and fix the leak (for example a test that leaves `PRAGMA foreign_keys` off on a shared connection) |
| Every build fails after token cleanup | The build token was deleted on the API Tokens page | Register a live token (below) and point every trigger at it |
| Empty commit skips a monorepo trigger | `path_includes` matched no changed file | Expected; the previous green build stands |

## Build tokens

- Builds keeps its own registry of tokens (`/builds/tokens`): a copied secret plus the name at registration time. Renaming or deleting the API token never updates it, so stale or deleted names linger in the dashboard dropdown.
- The dashboard's "Create new token" always names it `Workers Builds - <date>` and cannot be renamed. To get a clean name, register a token yourself: `POST /builds/tokens` with `{"build_token_name": "workers-builds", "build_token_secret": "<value>", "cloudflare_token_id": "<api token id>"}`. To reuse an existing API token whose secret you do not have, roll it (`PUT /user/tokens/<id>/value`, needs a short-lived token with User > API Tokens: Edit) and register the new value without printing it.
- Use one shared build token for every Worker. Builds only accepts user tokens, which are account-wide, so per-Worker tokens add no isolation.
- After switching, `PATCH` every trigger's `build_token_uuid`, run one branch build, then delete the old registry entry and the old API token.
- New Workers: pick the existing token in Settings > Builds > API token instead of "Create new token".
