import com.android.build.gradle.BaseExtension

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
// we override it in afterEvaluate to guarantee 36 everywhere.
subprojects {
    project.plugins.withId("com.android.application") {
        project.afterEvaluate {
            (project.extensions.findByName("android") as BaseExtension).compileSdk = 36
        }
    }
    project.plugins.withId("com.android.library") {
        project.afterEvaluate {
            (project.extensions.findByName("android") as BaseExtension).compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
