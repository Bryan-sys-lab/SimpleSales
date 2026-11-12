import com.android.build.api.dsl.CommonExtension
import org.gradle.api.Project
import org.gradle.api.initialization.ProjectDescriptor

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
// we set compileSdk = 36 when each Android plugin is registered via
// gradle.beforeProject — this runs before the subproject's own build.gradle.kts
// reads compileSdk, guaranteeing our value wins.
gradle.beforeProject { p: ProjectDescriptor ->
    p.plugins.withId("com.android.application") {
        p.android.compileSdk = 36
    }
    p.plugins.withId("com.android.library") {
        p.android.compileSdk = 36
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
