# Obsidian — Canvas fork setup design

Date: 2026-11-04
Status: approved in chat, pending spec review

## Goal

Obsidian is a public, rebranded fork of [CanvasMC](https://github.com/CraftCanvasMC/Canvas)
(Folia/Paper-based Minecraft server). It must continuously pick up the newest
**stable** Canvas while **never losing code that Obsidian adds**.

## Context (Canvas as of 2026-11-04)

- Canvas is a patch-based project built with `io.canvasmc.weaver.patcher`
  (a paperweight fork) on top of Paper (`paperRef` in `gradle.properties`).
- Patches: `canvas-server/minecraft-patches/{base,sources,features}`,
  `canvas-server/paper-patches/{base,features,files}`,
  `canvas-api/paper-patches`. Own sources in `canvas-server/src/main/java`.
- Java 25 toolchain. Current version `mcVersion = 26.3`.
- No GitHub releases/tags. "Stable" = a commit on `main` whose
  `gradle.properties` contains `channel = STABLE`. `ver/*` branches hold old
  versions; `dev/*` branches are unstable.
- Canvas CI (`test-pr.yml`): `applyAllPatches` → rebuild patches →
  `git diff --exit-code` → `test`.

## Decisions

| Topic | Decision |
|---|---|
| Repo | GitHub fork `Szabolcs05/Obsidian` of `CraftCanvasMC/Canvas` (public; GPL obligations met by being public). |
| Local | `C:\Users\SzabolcsAsztali\Desktop\Dev\Obsidian`, remotes `origin` (fork) and `upstream` (Canvas). |
| Upstream tracking | Canvas `main`, only commits with `channel = STABLE`. |
| Integration | `git merge` (never rebase, never `-X theirs`, never force-push). |
| Directory names | Keep `canvas-api` / `canvas-server` unchanged to minimise merge conflicts. |

## 1. Protecting Obsidian code

- Merges are the only integration mechanism; git either combines both sides or
  stops with a conflict — it never silently drops our lines.
- The sync bot pushes to `main` only if: merge is clean **and**
  `applyAllPatches` succeeds **and** rebuilt patches produce no diff **and**
  build + tests pass.
- Anything else → a PR from branch `upstream-sync/<canvas-short-sha>` (with
  conflict markers committed if the merge conflicted) plus a failing status, for
  manual resolution. `main` is untouched.
- Branch protection on `main` is out of scope for the bot (it pushes directly
  after passing checks); human changes go through PRs by convention.

## 2. Where Obsidian changes live

- Minecraft/server behaviour changes: **new** feature patches in
  `canvas-server/minecraft-patches/features/` (and `paper-patches/features/`
  when touching Paper code). Do not edit Canvas's existing patches unless
  unavoidable.
- New Java classes: `canvas-server/src/main/java/dev/obsidian/...` (Canvas never
  touches this package).
- Note: feature patches are renumbered on rebuild. If Canvas adds patch N while
  ours is also N, the files differ by name so git won't conflict; the sync
  run's `applyAllPatches` + rebuild renumbers them and the bot commits the
  rebuilt result as part of the sync.

## 3. Rebrand

- Root files: `rootProject.name = "Obsidian"`, `group = dev.obsidian`, version
  string `<mc>.build.<n>-<channel>` kept but jar named `obsidian-...`.
- One feature patch "Obsidian branding": server brand name (F3 / `/version`
  / startup log) → "Obsidian". Exact touch points are found during
  implementation.
- `README.md` rewritten for Obsidian, crediting Canvas, Folia and Paper;
  `LICENSE` kept unchanged.
- `.github/workflows/test-pr.yml` from Canvas is kept (it's upstream-owned).

## 4. Automation

### `sync-upstream.yml`
- Triggers: daily cron + `workflow_dispatch`.
- Steps: checkout full history → add/fetch `upstream` → find newest commit on
  `upstream/main` with `channel = STABLE` → if already merged, exit → merge
  (`--no-ff`, message `Merge Canvas <sha> (<mcVersion>)`) → Java 25 → apply
  patches → rebuild patches → commit any rebuild diff → build + test →
  push `main`; on any failure push `upstream-sync/<sha>` and open/update a PR.
- Uses `GITHUB_TOKEN` with `contents: write`, `pull-requests: write`.
  Note: pushes by `GITHUB_TOKEN` don't trigger other workflows, so the sync
  workflow calls the build/release job itself (reusable workflow).

### `build.yml`
- Triggers: push to `main`, PRs, `workflow_call`.
- Steps: apply patches → rebuild check → test → `createMojmapPaperclipJar`
  (task name verified during implementation).
- On `main`: publish jar to a GitHub Release tagged
  `<mcVersion>-build.<run_number>`, `BUILD_NUMBER` env set to run number.

## 5. Developer docs

`OBSIDIAN.md`: how to add a patch, how upstream sync works, how to resolve a
sync PR locally (`git fetch upstream && git merge <sha>`, then apply/rebuild).

## Out of scope

Actual gameplay/perf features, Maven publishing of the API, a downloads
website, multi-version (`ver/*`) tracking.

## Success criteria

1. Fork exists, local clone builds a jar named Obsidian with Java 25.
2. Running the sync workflow on an up-to-date fork is a no-op.
3. A sync that conflicts leaves `main` untouched and opens a PR.
4. Obsidian files (own package, own patches) survive merges unchanged.
