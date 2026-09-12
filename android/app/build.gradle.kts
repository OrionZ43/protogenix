import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ подписи release-сборок (.claude/rules/release.md).
// android/key.properties есть только у Orion и в git не попадает
// (android/.gitignore). Если файла или самого keystore нет, release
// подписывается debug-ключом: так собираются локальные сборки, но
// публиковать такой APK нельзя.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) }
    }
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
val hasReleaseKey = releaseStoreFile?.exists() == true

// APK под одну архитектуру (tool/release.ps1: flutter build apk --target-platform …).
// Движок Flutter и код приложения собираются только под target-platform, но
// abiFilters Flutter сам выставляет на все ABI (FlutterPlugin.configureAbiWithoutSplits),
// поэтому .so плагинов (libmpv, libsqlite3) попадали бы в APK под все архитектуры.
// Такой APK встаёт на телефон другой архитектуры и падает при запуске — лишние
// ABI вырезаем при упаковке. Проверено 2026-09-11, см. .claude/rules/release.md.
val flutterPlatformAbis = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val targetAbis = (findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull { flutterPlatformAbis[it.trim()] }
    .orEmpty()
val splitPerAbi = findProperty("split-per-abi")?.toString()?.toBoolean() == true
val excludedAbis = if (targetAbis.isEmpty() || splitPerAbi) {
    emptyList()
} else {
    flutterPlatformAbis.values - targetAbis.toSet()
}

android {
    namespace = "z43.studios.protogenix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "z43.studios.protogenix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            excludedAbis.forEach { excludes += "**/$it/*.so" }
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties or the keystore is missing - " +
                        "the release build is signed with the DEBUG key and must not be published."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
