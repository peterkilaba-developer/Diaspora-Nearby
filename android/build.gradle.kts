allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            val android = project.extensions.findByName("android") as? com.android.build.gradle.LibraryExtension
            if (android != null) {
                // Force compileSdk to 36 for all modules to satisfy plugin requirements (like sqflite_android, isar_flutter_libs)
                android.compileSdk = 36
                android.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
                
                project.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                    compilerOptions {
                        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                    }
                }

                if (android.namespace == null) {
                   android.namespace = "com.diasporanearby.generated.${project.name.replace("-", "_")}"
                }
                // Strip package attribute from Manifest to fix AGP 8 compatibility for older plugins
                try {
                    val manifest = project.file("src/main/AndroidManifest.xml")
                    if (manifest.exists()) {
                        var content = manifest.readText()
                        val newContent = content.replace(Regex("package=\"[^\"]+\""), "")
                        if (content != newContent) {
                             manifest.writeText(newContent)
                             println("Removed package attribute from ${project.name} manifest")
                        }
                    }
                } catch (e: Exception) {
                    println("Failed to clean manifest for ${project.name}: $e")
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


