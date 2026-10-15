---
name: workers-builds
description: 'Set up, debug and maintain Cloudflare Workers deployed by Cloudflare Workers Builds (git-connected builds). Use when connecting a repo to Builds, changing build settings, or reading a failed "Workers Builds: <worker>" check.'
license: MIT
metadata:
  tags: "Cloudflare, Workers, CI, Deploy"
  category: "devops"
---

# Workers Builds

Cloudflare Workers Builds clones the repo on each push, runs a build command, then a deploy command, and reports a GitHub check named `Workers Builds: <worker>`. No Cloudflare token lives in GitHub.

## Ground rules

- Use the API, not the dashboard, for anything repeatable. The dashboard hides some settings and some of its labels go stale.
- Load the Cloudflare token only inside a subshell from a keys file: `(set -a; . ~/.cloudflare-keys; set +a; <cmd>)`. Never echo it, never put it on a command line.
- The token calling the Builds API must be a **user** token (account-owned tokens get "Invalid token") with Workers Builds Configuration: Edit, plus Workers Scripts: Read to look up Worker tags.
- Ask before a first production build: the deploy command often applies remote D1 migrations.

## API map

Base: `https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID`

| Need | Call |
|---|---|
| Worker tag (the Builds API's `external_script_id`) | `GET /workers/scripts` -> `.result[] | {id, tag}` |
| Triggers on a Worker | `GET /builds/workers/<tag>/triggers` (404 "No build configuration" = not connected) |
| Create / change a trigger | `POST /builds/triggers`, `PATCH /builds/triggers/<trigger_uuid>` |
| Build variables | `PATCH /builds/triggers/<trigger_uuid>/environment_variables` with `{"NAME":{"value":"x","is_secret":false}}` (merges) |
| Run a build | `POST /builds/triggers/<trigger_uuid>/builds` with `{"branch":"main"}` |
| Builds, one build, its log | `GET /builds/workers/<tag>/builds`, `GET /builds/builds/<uuid>`, `.../logs` (`.result.lines[][1]`) |
| GitHub repo link | `PUT /builds/repos/connections` with the GitHub user id and repo id from `api.github.com` |
| Build token uuid | `GET /builds/tokens` |
| Branch previews | `GET /builds/workers/<tag>/previews`, `PATCH .../previews/<preview_id>` `{"auto_build":false}` |

## Setting up a Worker

1. Read the repo: the `name` in the wrangler config (the Worker), the package manager and its version (`packageManager`), the checks it should run, and any migrations.
2. Link the repo, then create two triggers on the Worker tag, both using the shared `workers-builds` build token:
   - **Production**: `branch_includes: ["main"]`, deploy command = the real deploy, for example `bunx wrangler d1 migrations apply <db> --remote && bunx wrangler deploy`.
   - **Branches**: `branch_includes: ["*"]`, `branch_excludes: ["main"]`, deploy command `<pm> wrangler versions upload`. PRs get a check without going live. Never put migrations here.
3. Same build command on both, and make it run the project's checks (for example `bun run preflight && bun run build`), so GitHub needs no check job.
4. Monorepo: set `root_directory` (for example `/admin`) and `path_includes: ["admin/*"]`.
5. Pin the toolchain with build variables; Builds defaults are old (bun 1.2.x). Set `BUN_VERSION`, `NODE_VERSION` or `PNPM_VERSION` to what the repo uses.
6. Build-time values go in build variables (for example `VITE_*`, inlined into the client bundle). Runtime secrets stay on the Worker (`wrangler secret put`). The build must pass with no runtime secrets set.
7. Run a branch build through the API and wait for green. An API-started build posts no GitHub check; push a commit for that.
8. Turn off preview builds for the PR branch (see below), or its check fails.
9. If the dashboard already made a trigger with defaults (`bun run build`, `npx wrangler deploy`, root `/`), `PATCH` it instead of creating another (`12042 A trigger already exists`).

## When a check fails

| Symptom | Cause | Fix |
|---|---|---|
| Fails in about 1 second, log ends in wrangler's help text or "missing a `previews` block" | Worker Previews: new Workers run `npx wrangler preview` on each non-main push | `PATCH .../previews/<id>` `{"auto_build":false}` for that branch's preview. Deleting the preview trigger does not help: it comes back on the next push |
| Default commands ran | A build ran before settings were saved | `PATCH` the trigger, rerun |
| Passes locally, fails in Builds | Different bun or node version | Pin the version; if order changed, look for state leaking between tests |

Read the log first: `GET /builds/builds/<uuid>/logs`.

## Build token

- Every trigger uses one shared build token, `workers-builds`. Builds only accepts user tokens, which are account-wide, so per-Worker tokens add no isolation.
- New Worker in the dashboard: pick `workers-builds` under Settings > Builds > API token, never "Create new token" (that adds a token named `Workers Builds - <date>`).
- Builds keeps its own copy of each token's secret and name. Renaming or deleting the API token does not update it. If the token is ever replaced, register the new one with `POST /builds/tokens` (`build_token_name`, `build_token_secret`, `cloudflare_token_id`), `PATCH` every trigger's `build_token_uuid`, run one branch build, then delete the old entry.
