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
    project.evaluationDependsOn(":app")
}

// Force compileSdk to 36 on every Android subproject (app + library plugins
// such as :workmanager and :sqflite_sqlcipher). flutter.compileSdkVersion
// resolves to android-31 on Flutter 3.47, but workmanager 0.10.10's
// transitive AndroidX dependencies require compileSdk 33-34+. Flutter's
// Gradle plugin re-asserts compileSdk = 31 during project evaluation, so
// we override it in each subproject's afterEvaluate callback, which runs
// after Flutter's plugin sets compileSdk = 31 but before the subproject
// reads compileSdk to configure its compilation.
configure(subprojects) {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as CommonExtension).compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
