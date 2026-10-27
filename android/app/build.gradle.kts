import java.security.KeyStore
import java.security.PrivateKey
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}
val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use { releaseKeyProperties.load(it) }
}

val releaseStorePassword = releaseKeyProperties.getProperty("storePassword")
val releaseKeyPassword = releaseKeyProperties.getProperty("keyPassword")
val releaseKeyAlias = releaseKeyProperties.getProperty("keyAlias")?.trim()
val releaseStorePath = releaseKeyProperties.getProperty("storeFile")?.trim()
val releaseStoreFile = releaseStorePath
    ?.takeIf(String::isNotEmpty)
    ?.let { path ->
        val candidate = file(path)
        if (candidate.isAbsolute) candidate else rootProject.file(path)
    }
val releaseSigningValuesPresent =
    !releaseStorePassword.isNullOrEmpty() &&
        !releaseKeyPassword.isNullOrEmpty() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseStorePath.isNullOrBlank()

if (releaseBuildRequested) {
    if (!releaseKeyPropertiesFile.isFile) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties with the actual release keystore path, alias, store password, and key password. See the project's release-signing instructions.",
        )
    }
    if (!releaseSigningValuesPresent) {
        throw GradleException(
            "Release signing configuration is incomplete. android/key.properties must define non-empty storePassword, keyPassword, keyAlias, and storeFile values.",
        )
    }
    if (releaseStoreFile?.isFile != true) {
        throw GradleException(
            "The release keystore configured in android/key.properties does not exist or is not a file. Check the storeFile path.",
        )
    }

    try {
        val keyStore = KeyStore.getInstance("JKS")
        releaseStoreFile.inputStream().use {
            keyStore.load(it, releaseStorePassword!!.toCharArray())
        }
        if (!keyStore.containsAlias(releaseKeyAlias)) {
            throw GradleException(
                "The configured release keystore does not contain the keyAlias from android/key.properties.",
            )
        }
        if (keyStore.getKey(releaseKeyAlias, releaseKeyPassword!!.toCharArray())
                !is PrivateKey
        ) {
            throw GradleException(
                "The configured keyAlias does not contain a private signing key.",
            )
        }
    } catch (error: GradleException) {
        throw error
    } catch (_: Exception) {
        throw GradleException(
            "Could not open the configured release keystore or unlock its signing key. Check the keystore path, alias, storePassword, and keyPassword in android/key.properties.",
        )
    }
}

android {
    namespace = "dev.pages.barath.pocketexpense"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.pages.barath.pocketexpense"
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
        if (releaseSigningValuesPresent && releaseStoreFile?.isFile == true) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningValuesPresent && releaseStoreFile?.isFile == true) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
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
