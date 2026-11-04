# Obsidian maintainer guide

Obsidian is a rebranded fork of Canvas (itself a fork of Folia and Paper). Canvas is merged in automatically; this
guide covers where Obsidian's own changes go and how to handle the sync.

## Where changes go

- New feature patches: `canvas-server/minecraft-patches/features/` (Minecraft code) or
  `canvas-server/paper-patches/features/` (Paper code). Do not edit Canvas's existing patches.
- New Java classes: `canvas-server/src/main/java/dev/obsidian/...`.
- Build and branding tweaks: `obsidian.gradle.kts`.
- The `canvas-api` and `canvas-server` folders keep their names on purpose, so upstream merges don't conflict.

## Patch workflow

Same as Canvas and Paper; see the [Canvas developer docs](https://docs.canvasmc.io/canvas/developers/contributing/canvas/) for the details ([CONTRIBUTING.md](CONTRIBUTING.md) only covers pull request guidelines). In short (Java 25 required):

1. `./gradlew applyAllPatches`
2. Edit and commit inside the patched source repos.
3. `./gradlew rebuildAllServerPatches rebuildPaperApiPatches rebuildPaperSingleFilePatches`
4. `./gradlew :canvas-server:createPaperclipJar`; the jar lands in
   `canvas-server/build/libs/obsidian-paperclip-<version>.jar`.

## Upstream sync

`.github/workflows/obsidian-sync.yml` runs daily at 04:17 UTC. It can also be run manually from
Actions, using "workflow_dispatch".

1. It picks the newest commit on Canvas `main` whose `gradle.properties` has `channel = STABLE`
   (`scripts/obsidian/find-stable.sh`).
2. It merges that commit with `scripts/obsidian/merge-upstream.sh`, using `--no-ff`. It never rebases and never uses
   `-X theirs`.
3. It applies patches, rebuilds them (committing any rebuild diff), then runs the tests and builds.
4. Only if all of that passes is `main` pushed. The run then builds and publishes a GitHub Release tagged
   `<mcVersion>-<short sha>`, where the short sha is the Obsidian commit that was built.
5. If anything fails, it pushes branch `upstream-sync/<short>` and opens a PR "Sync Canvas <short> (<mc>)". Here `<short>` is the Canvas commit, not an Obsidian one. The run
   fails so you get notified. `main` is untouched.

### Optional secret: SYNC_TOKEN

`SYNC_TOKEN` is a personal access token with `repo` and `workflow` scopes. It is needed when an upstream merge touches
`.github/workflows/*`, because `GITHUB_TOKEN` cannot push those changes. Without it, such syncs fail with an error
telling you to merge manually.

With `SYNC_TOKEN`, the push to `main` triggers `obsidian-build.yml` directly. Without it (pushes made with
`GITHUB_TOKEN` do not trigger workflows), the sync workflow calls the build itself.

### Resolving a sync PR locally

`merge-upstream.sh` merges into the currently checked-out branch, and only creates `upstream-sync/<short>` when there
is a conflict. Which case you are in depends on the PR:

**(a) Conflict PR.** The conflicted merge is on the pushed branch.

1. `git fetch origin upstream-sync/<short>` and `git checkout -b upstream-sync/<short> FETCH_HEAD` (or `git switch`).
2. Resolve the conflict markers, keeping Obsidian's code and Canvas's changes.
3. `./gradlew applyAllPatches` and fix any patch failures.
4. Rebuild the patches (command above), then run `./gradlew test`.
5. Commit, push the branch and merge the PR.

**(b) Verification-failure PR.** The clean merge is already on the pushed `upstream-sync/<short>`; check it out the
same way as in (a) and fix whatever failed (apply, rebuild, tests or build), then commit, push and merge the PR.

To redo the merge locally instead, never do it on `main`: first `git switch -c my-sync main`, then run
`git fetch upstream && bash scripts/obsidian/merge-upstream.sh upstream/main`.

`README.md` is owned by Canvas, so it can conflict on merges. That is accepted: when resolving conflicts, apply the
rule manually that Obsidian's README wins.

## Other workflows

`.github/workflows/obsidian-build.yml` runs on pushes to `main` and on pull requests. Canvas's `test-pr.yml` also still
runs on pull requests.

## Known follow-ups

- The in-game update checker (`CanvasVersionFetcher`) still compares against Canvas builds.
- Maven publishing of `obsidian-api`.
