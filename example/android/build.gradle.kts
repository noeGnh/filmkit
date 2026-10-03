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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// insta_assets_crop 0.1.2 (a dependency of insta_assets_picker) compiles against android-31,
// which current AndroidX libraries refuse. Raise it until upstream does.
subprojects {
    if (name == "insta_assets_crop") {
        val raiseCompileSdk = {
            extensions.configure<com.android.build.gradle.LibraryExtension> { compileSdk = 36 }
        }
        if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
