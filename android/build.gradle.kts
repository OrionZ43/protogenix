allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Фикс для старых плагинов (например audiotags), у которых нет namespace в build.gradle
    afterEvaluate {
        val androidLib = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (androidLib != null && androidLib.namespace == null) {
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val packageName = groovy.xml.XmlParser().parse(manifestFile).attribute("package") as? String
                if (!packageName.isNullOrBlank()) {
                    androidLib.namespace = packageName
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}