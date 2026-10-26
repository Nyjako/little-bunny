plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.github.nyjako.little_bunny"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (M43) requires this on Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.github.nyjako.little_bunny"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // A stable release signing key (env-var-driven, see below) so one
    // release's .apk can upgrade-install over the previous one -- without
    // this, every CI run signs with a freshly auto-generated debug
    // keystore (a new one each time, since none is committed/cached), so
    // every release has a DIFFERENT signing certificate and Android
    // refuses to install it over whatever's already on the phone ("App not
    // installed as package appears to be invalid"/conflicts with an
    // existing package), which looks like the autoupdate silently doing
    // nothing. Falls back to the debug keystore when the env vars aren't
    // set (every local/dev build, `flutter run --release` included) --
    // only release.yml's CI build ever sets them, via a keystore stored as
    // a GitHub secret.
    val releaseKeystorePath = System.getenv("BUNNY_ANDROID_KEYSTORE_PATH")
    signingConfigs {
        if (releaseKeystorePath != null) {
            create("release") {
                storeFile = file(releaseKeystorePath)
                storePassword = System.getenv("BUNNY_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("BUNNY_ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("BUNNY_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (releaseKeystorePath != null) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
