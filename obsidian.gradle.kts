// Obsidian rebrand layer. Applied from the end of build.gradle.kts so the Canvas-owned
// build files stay (nearly) untouched and upstream merges stay trivial.
// Note: this is a script plugin, so no `plugins {}` block and no type-safe accessors.

project(":canvas-server").afterEvaluate {
    // Runs after canvas-server/build.gradle.kts has configured `tasks.jar`; these override Canvas' values.
    tasks.named<Jar>("jar") {
        manifest {
            attributes(
                "Implementation-Title" to "Obsidian",
                "Specification-Title" to "Obsidian",
                "Specification-Vendor" to "Obsidian",
                "Brand-Id" to "obsidian:obsidian",
                "Brand-Name" to "Obsidian",
                "Brand-Vendor" to "Obsidian",
                "Brand-Website" to "https://github.com/Szabolcs05/Obsidian",
            )
        }
    }

    // The paperclip/bundler jar names are build/libs/<bundlerJarName>-paperclip-<version>.jar
    // (PaperclipTasks.jarName); bundlerJarName defaults to "paper".
    extensions.configure<io.papermc.paperweight.core.extension.PaperweightCoreExtension> {
        bundlerJarName.set("obsidian")
    }
}
