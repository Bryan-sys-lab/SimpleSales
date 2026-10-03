import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties()
val hasReleaseSigning = signingPropertiesFile.exists()
if (hasReleaseSigning) {
    signingProperties.load(FileInputStream(signingPropertiesFile))
}

android {
    namespace = "com.dukapos.duka_pos"
    compileSdk = flutter.compileSdkVersion
    // This is the NDK *this app* needs. It is not the only one a build may ask
    // for: `path_provider_android` reaches `jni`, whose own module pins a newer
    // NDK, so a machine without that second copy fails at :jni — not here.
    ndkVersion = "27.1.12297006"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dukapos.duka_pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = signingProperties["keyAlias"] as String?
                keyPassword = signingProperties["keyPassword"] as String?
                storeFile = (signingProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = signingProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Null when key.properties is absent. `getByName` would throw
            // during configuration, and because `buildTypes` is evaluated
            // eagerly that would break *every* variant — including `flutter run`
            // and debug builds — on any machine without a release keystore.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Fail fast rather than silently emitting an unsigned release APK that can
// never update an existing install. key.properties is gitignored, so it is
// intentionally absent on most machines.
//
// This deliberately lives outside `buildTypes`: that block runs at
// configuration time, so a check there fails the build regardless of which
// variant was requested, breaking `flutter run` and debug builds too.
//
// The requested task names are inspected instead of `taskGraph.whenReady`:
// in a Kotlin DSL script `whenReady` has a Groovy `Closure` overload that a
// lambda binds to, which leaves the graph type uninferred and the script
// uncompilable. Flutter always asks for an explicit variant
// (`assembleDebug` / `assembleRelease`), so the task names are authoritative.
val requestedTasks = gradle.startParameter.taskNames
val wantsRelease = requestedTasks.any { requested ->
    requested.substringAfterLast(':').contains("Release", ignoreCase = true)
}
if (wantsRelease && !hasReleaseSigning) {
    throw GradleException(
        "Release signing is not configured. Create android/key.properties " +
            "(storeFile, storePassword, keyAlias, keyPassword) before building a release APK."
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
