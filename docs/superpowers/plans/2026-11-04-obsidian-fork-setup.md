# Obsidian Fork Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Obsidian GitHub fork of CanvasMC, rebrand it with minimal upstream-conflict surface, and add CI that safely merges each new stable Canvas commit.

**Architecture:** A real GitHub fork with `origin` (Szabolcs05/Obsidian) and `upstream` (CraftCanvasMC/Canvas). Obsidian-owned logic lives in new files only (`obsidian.gradle.kts`, `scripts/obsidian/`, `dev/obsidian` package, new feature patches); Canvas-owned files get at most one-line hooks. A shell script picks the newest STABLE upstream commit; a workflow merges it, verifies, and pushes or opens a PR.

**Tech Stack:** git, gh CLI, Bash, Gradle (Canvas `io.canvasmc.weaver.patcher`), Java 25, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-04-obsidian-fork-design.md`

## Global Constraints

- Repo: `Szabolcs05/Obsidian`, GitHub fork of `CraftCanvasMC/Canvas`, default branch `main`.
- Upstream source: `upstream/main`, commits whose `gradle.properties` has `channel = STABLE`.
- Never: rebase onto upstream, `-X theirs`/`-X ours`, `git push --force`.
- Do not rename `canvas-api` / `canvas-server`; do not edit existing Canvas patches.
- Brand values: name `Obsidian`, id `obsidian:obsidian`, vendor `Obsidian`, website `https://github.com/Szabolcs05/Obsidian`, group `dev.obsidian`.
- Java 25 (temurin) in CI.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Deviation from spec §3 (recorded):** branding is done by overriding the jar manifest `Brand-*`/`Implementation-Title` attributes from `obsidian.gradle.kts` instead of a feature patch — Paper's `ServerBuildInfo` (used by `/version`, F3 brand, startup log) reads these, and it avoids editing Canvas's `build.gradle.kts.patch`. `CanvasVersionFetcher` (update checker that queries Canvas builds) is left as-is and listed as a follow-up.

## Review Focus

1. Upstream `main` head is BETA/unstable (e.g. a new MC version in progress) → sync must pick the last STABLE commit, not head. Test: `find-stable` fixture with STABLE→BETA history.
2. Newest STABLE commit already merged → sync is a no-op, no empty merge commit, no PR. Test: `find-stable` + `is-merged` check in sync script test.
3. Merge conflict on an Obsidian-modified file → `main` unchanged, branch `upstream-sync/<sha>` pushed with conflict, PR opened. Test: merge script fixture with conflicting edit exits 1 and leaves HEAD of main unchanged.
4. Obsidian-only files (new files) survive a merge byte-for-byte. Test: merge fixture asserts file content after clean merge.
5. Re-running sync while a sync PR for the same sha is already open → no duplicate PR. Covered by workflow step using `gh pr list --head`.

---

### Task 1: Create the fork and local clone

**Files:**
- Keep: `docs/superpowers/specs/…`, `docs/superpowers/plans/…` (already in the folder)

- [ ] **Step 1: Create the GitHub fork**
  Run: `gh repo fork CraftCanvasMC/Canvas --fork-name Obsidian --clone=false --default-branch-only`
  Expected: `Szabolcs05/Obsidian` created.
- [ ] **Step 2: Clone into the existing folder (non-empty)**
  Run in `Desktop/Dev/Obsidian`: `git init -b main && git remote add origin https://github.com/Szabolcs05/Obsidian.git && git remote add upstream https://github.com/CraftCanvasMC/Canvas.git && git fetch origin && git fetch upstream && git checkout -t origin/main`
  Expected: working tree = Canvas `main`; docs folder untracked.
- [ ] **Step 3: Enable Actions and write permissions on the fork**
  `gh api -X PUT repos/Szabolcs05/Obsidian/actions/permissions -F enabled=true -f allowed_actions=all`
  `gh api -X PUT repos/Szabolcs05/Obsidian/actions/permissions/workflow -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true`
- [ ] **Step 4: Commit docs** — `git add docs && git commit -m "docs: Obsidian fork design and plan"`

### Task 2: Stable-commit finder (TDD)

**Files:**
- Create: `scripts/obsidian/find-stable.sh`
- Create: `scripts/obsidian/tests/test-find-stable.sh`

**Interfaces:**
- Produces: `find-stable.sh <ref>` → prints full sha of newest first-parent commit reachable from `<ref>` whose `gradle.properties` matches `^channel[[:space:]]*=[[:space:]]*STABLE[[:space:]]*$`; exit 1 with message on stderr if none within 500 commits.

- [ ] **Step 1: Write failing test** — builds a temp repo: c1 STABLE, c2 STABLE, c3 BETA. Asserts `find-stable.sh HEAD` == sha(c2); asserts a repo with only BETA commits exits 1.
- [ ] **Step 2: Run** `bash scripts/obsidian/tests/test-find-stable.sh` → FAIL (script missing).
- [ ] **Step 3: Implement** using `git rev-list --first-parent --max-count=500 <ref>` + `git show <sha>:gradle.properties`.
- [ ] **Step 4: Run test** → PASS.
- [ ] **Step 5: Commit** `feat(ci): add stable upstream commit finder`

### Task 3: Safe merge script (TDD)

**Files:**
- Create: `scripts/obsidian/merge-upstream.sh`
- Create: `scripts/obsidian/tests/test-merge-upstream.sh`

**Interfaces:**
- Consumes: `find-stable.sh`.
- Produces: `merge-upstream.sh <upstream-ref>`; outputs `key=value` lines to `$GITHUB_OUTPUT` if set, else stdout: `status=up-to-date|merged|conflict`, `sha=<full>`, `short=<7>`, `mc=<mcVersion at sha>`. Exit 0 for `up-to-date`/`merged`, 2 for `conflict`. On conflict: creates branch `upstream-sync/<short>` from pre-merge HEAD, commits the conflicted merge there (markers included, message `Merge Canvas <short> (<mc>) [CONFLICTS]`), and checks `main` back out unchanged. Merge message: `Merge Canvas <short> (<mc>)`. Uses `git merge --no-ff --no-edit`, never strategy options.

- [ ] **Step 1: Write failing tests** (fixture repos: an "upstream" and a "fork" clone):
  - already merged → `status=up-to-date`, no new commit.
  - clean merge with Obsidian-only file `dev-obsidian.txt` → `status=merged`, file byte-identical, upstream change present.
  - both edit same line of `shared.txt` → exit 2, `status=conflict`, `main` sha unchanged, branch `upstream-sync/<short>` exists and contains `<<<<<<<` in `shared.txt`.
- [ ] **Step 2: Run** `bash scripts/obsidian/tests/test-merge-upstream.sh` → FAIL.
- [ ] **Step 3: Implement.** Up-to-date check: `git merge-base --is-ancestor <sha> HEAD`.
- [ ] **Step 4: Run tests** → PASS (also re-run Task 2 test).
- [ ] **Step 5: Commit** `feat(ci): add safe upstream merge script`

### Task 4: Rebrand via `obsidian.gradle.kts`

**Files:**
- Create: `obsidian.gradle.kts`
- Modify: `build.gradle.kts` (append one line at end: `apply(from = "obsidian.gradle.kts")`)
- Modify: `settings.gradle.kts` (`rootProject.name = "Obsidian"`)
- Modify: `gradle.properties` (`group = dev.obsidian`)

**Interfaces:**
- Produces: built server jar whose manifest has `Brand-Id=obsidian:obsidian`, `Brand-Name=Obsidian`, `Brand-Vendor=Obsidian`, `Brand-Website=https://github.com/Szabolcs05/Obsidian`, `Implementation-Title=Obsidian`, `Specification-Title=Obsidian`, `Specification-Vendor=Obsidian`. Paperclip jar output named `obsidian-<version>.jar` (via `archiveBaseName`/rename in `obsidian.gradle.kts`).

- [ ] **Step 1:** Implement `obsidian.gradle.kts`: `project(":canvas-server") { afterEvaluate { tasks.withType<Jar>().configureEach { manifest.attributes(<values above>) } } }` plus paperclip output rename; verify actual paperclip task name with `./gradlew :canvas-server:tasks --all` (expected `createMojmapPaperclipJar`).
- [ ] **Step 2: Verify** `./gradlew applyAllPatches` then `./gradlew :canvas-server:createMojmapPaperclipJar` (long; run in background). Unzip manifest of the server jar and confirm all seven attributes; confirm jar file name starts with `obsidian-`.
- [ ] **Step 3: Verify** rebuild patches leave no diff (same commands as Canvas `test-pr.yml`).
- [ ] **Step 4: Commit** `feat: rebrand to Obsidian`

### Task 5: Workflows

**Files:**
- Create: `.github/workflows/obsidian-build.yml`
- Create: `.github/workflows/obsidian-sync.yml`

**Interfaces:**
- Consumes: `merge-upstream.sh` outputs; paperclip task from Task 4.
- `obsidian-build.yml`: on `push: main`, `pull_request`, `workflow_call`; steps = checkout, setup-java 25 temurin, setup-gradle, git config, `applyAllPatches`, rebuild patches + `git diff --exit-code`, `test`, paperclip jar with `BUILD_NUMBER=${{ github.run_number }}`; on `main` (non-PR) upload jar to Release `<mcVersion>-build.<run_number>` via `gh release create`. Also runs `scripts/obsidian/tests/*.sh`.
- `obsidian-sync.yml`: `schedule: cron "17 4 * * *"` + `workflow_dispatch`; permissions `contents: write`, `pull-requests: write`; concurrency group `obsidian-sync`. Steps: checkout `fetch-depth: 0`, fetch upstream, run `merge-upstream.sh upstream/main`. If `merged`: apply patches, rebuild patches, commit diff if any (`chore: rebuild patches after Canvas <short>`), test, build; success → `git push origin main` then call build job (reusable `obsidian-build.yml`, since GITHUB_TOKEN pushes don't trigger workflows); failure → push the merge to `upstream-sync/<short>` instead. If `conflict` or failure: push branch and open PR `Sync Canvas <short> (<mc>)` unless `gh pr list --head upstream-sync/<short> --state open` already returns one; job fails so you're notified.

- [ ] **Step 1:** Write both workflows.
- [ ] **Step 2: Verify locally** with `actionlint` if available (else YAML parse via `python -c "import yaml,sys;yaml.safe_load(open(sys.argv[1]))"`).
- [ ] **Step 3: Commit** `ci: add Obsidian build and upstream sync workflows`

### Task 6: Docs and push

**Files:**
- Modify: `README.md` (Obsidian intro, credits Canvas/Folia/Paper, link to OBSIDIAN.md; keep LICENSE untouched)
- Create: `OBSIDIAN.md` (where to put changes; how sync works; resolving a sync PR: `git fetch origin upstream-sync/<short>`, resolve markers, `./gradlew applyAllPatches`, rebuild, test, merge PR)

- [ ] **Step 1:** Write docs; commit `docs: Obsidian README and contributor guide`.
- [ ] **Step 2:** `git push origin main`.
- [ ] **Step 3: Verify** `gh workflow run obsidian-sync.yml` → run succeeds with `status=up-to-date` (success criterion 2); `obsidian-build` run on the push succeeds and creates a Release with the `obsidian-…jar`.

## Follow-ups (not in this plan)
- Replace `CanvasVersionFetcher` update checks with Obsidian's own (feature patch / own class).
- Maven publishing of `obsidian-api`.
