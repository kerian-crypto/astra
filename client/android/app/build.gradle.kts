import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Notifications push : actives seulement avec le fichier de configuration
// Firebase de l'application com.astra.astra_client (non versionné).
// Sans lui, l'application se compile et fonctionne sans push.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("google-services.json absent : notifications push désactivées.")
}

// Les --dart-define arrivent en base64 dans la propriété « dart-defines ».
// DISTRIBUTION=play : build Google Play (bundle .aab signé avec la clé d'envoi).
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    .orEmpty()
    .split(",")
    .filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it)) }
    .filter { it.contains("=") }
    .associate { it.substringBefore("=") to it.substringAfter("=") }
val isPlayStoreBuild = dartDefines["DISTRIBUTION"] == "play"

// Clé d'envoi Google Play (Play App Signing) : android/key.properties, jamais versionné.
val uploadKeyFile = rootProject.file("key.properties")
val uploadKey = Properties().apply {
    if (uploadKeyFile.exists()) uploadKeyFile.inputStream().use { load(it) }
}

android {
    namespace = "com.astra.astra_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.astra.astra_client"
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
        if (uploadKeyFile.exists()) {
            create("upload") {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (isPlayStoreBuild) {
                if (!uploadKeyFile.exists()) {
                    throw GradleException("Build Play : android/key.properties manquant (clé d'envoi).")
                }
                signingConfigs.getByName("upload")
            } else {
                // APK distribués par le serveur Astra : même clé que les versions
                // déjà installées, sinon Android refuserait leurs mises à jour.
                signingConfigs.getByName("debug")
            }
        }
    }

    // Hors Play Store seulement : permission d'ouvrir l'installeur d'APK.
    if (!isPlayStoreBuild) {
        sourceSets.getByName("release").manifest.srcFile("src/sideload/AndroidManifest.xml")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
