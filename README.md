# Obsidian

Obsidian is a public fork of [CanvasMC](https://github.com/CraftCanvasMC/Canvas), which is itself a fork of
[Folia](https://github.com/PaperMC/Folia) and [Paper](https://github.com/PaperMC/Paper). It tracks Canvas's stable
releases automatically and layers Obsidian's own changes on top.

Source: <https://github.com/Szabolcs05/Obsidian>

## Downloads

Server jars are published on the [GitHub Releases](https://github.com/Szabolcs05/Obsidian/releases) page. Releases are
tagged `<mcVersion>-<short sha>` and contain an `obsidian-paperclip-<version>.jar`. Java 25 or newer is required.

## Building

Requirements: Java 25 and Git (with name and email configured).

```bash
./gradlew applyAllPatches                  # apply all patches to construct the source
./gradlew :canvas-server:createPaperclipJar # build the jar
```

The jar is written to `canvas-server/build/libs/obsidian-paperclip-<version>.jar`.

## Contributing and maintenance

See [OBSIDIAN.md](OBSIDIAN.md) for where Obsidian changes live, how the upstream sync works, and how to resolve a
failed sync. The general patch workflow is described in [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and license

Obsidian would not exist without the work of [CanvasMC](https://github.com/CraftCanvasMC/Canvas),
[Folia](https://github.com/PaperMC/Folia) and [Paper](https://github.com/PaperMC/Paper). Canvas also incorporates
patches derived from other projects; their licenses are in
`canvas-server/src/main/resources/META-INF/licenses/`.

Like its upstreams, Obsidian is licensed under the GNU General Public License v3 (GPL-3.0). See [LICENSE](LICENSE).
