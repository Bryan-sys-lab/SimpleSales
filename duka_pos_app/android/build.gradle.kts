import com.android.build.api.dsl.CommonExtension

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

// Force compileSdk to 36 on every Android subproject (app + library plugins
// such as :workmanager and :sqflite_sqlcipher). flutter.compileSdkVersion
// resolves to android-31 on Flutter 3.47, but workmanager 0.10.10's
// transitive AndroidX dependencies require compileSdk 33-34+. Flutter's
// Gradle plugin re-asserts compileSdk = 31 during project evaluation, so
// this runs after ALL projects are evaluated via gradle.projectsEvaluated,
// guaranteeing our value wins.
gradle.projectsEvaluated {
    subprojects { sub ->
        sub.extensions.findByName("android")?.let { ext ->
            (ext as CommonExtension).compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
