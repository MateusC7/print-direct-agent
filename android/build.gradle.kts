allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    if (project.path != ":app") {
        project.evaluationDependsOn(":app")
    }
    
    val configureNamespaceAndJvm = {
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            val android = extensions.findByName("android")
            if (android != null) {
                // 1. Inject Namespace if needed
                val getNamespaceMethod = android.javaClass.methods.firstOrNull { it.name == "getNamespace" }
                val setNamespaceMethod = android.javaClass.methods.firstOrNull { it.name == "setNamespace" }
                
                if (setNamespaceMethod != null) {
                    val currentNamespace = try {
                        getNamespaceMethod?.invoke(android) as? String
                    } catch (e: Exception) {
                        null
                    }
                    
                    if (currentNamespace.isNullOrEmpty()) {
                        var resolvedNamespace: String? = null
                        val manifestFile = file("src/main/AndroidManifest.xml")
                        if (manifestFile.exists()) {
                            val manifestContent = manifestFile.readText()
                            val match = Regex("package=\"([^\"]+)\"").find(manifestContent)
                            if (match != null) {
                                resolvedNamespace = match.groupValues[1]
                            }
                        }
                        if (resolvedNamespace.isNullOrEmpty()) {
                            val packageName = project.name.replace("-", ".").replace("_", ".")
                            resolvedNamespace = "com.example.$packageName"
                        }
                        setNamespaceMethod.invoke(android, resolvedNamespace)
                        logger.lifecycle("Subproject [${project.name}]: injected namespace '$resolvedNamespace'")
                    }
                }

                // 2. Align JVM compatibility targets in Android extension compileOptions
                try {
                    val compileOptions = android.javaClass.methods.firstOrNull { it.name == "getCompileOptions" }?.invoke(android)
                    if (compileOptions != null) {
                        val setSource = compileOptions.javaClass.methods.firstOrNull { it.name == "setSourceCompatibility" }
                        val setTarget = compileOptions.javaClass.methods.firstOrNull { it.name == "setTargetCompatibility" }
                        setSource?.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_1_8)
                        setTarget?.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_1_8)
                    }
                } catch (e: Exception) {}

                try {
                    val kotlinOptions = android.javaClass.methods.firstOrNull { it.name == "getKotlinOptions" }?.invoke(android)
                    if (kotlinOptions != null) {
                        val setJvmTarget = kotlinOptions.javaClass.methods.firstOrNull { it.name == "setJvmTarget" }
                        setJvmTarget?.invoke(kotlinOptions, "1.8")
                    }
                } catch (e: Exception) {}
            }
        }
    }
    
    if (state.executed) {
        configureNamespaceAndJvm()
    } else {
        afterEvaluate {
            configureNamespaceAndJvm()
        }
    }

    // 3. Align JVM compatibility targets directly in compilation tasks
    tasks.configureEach {
        if (name.contains("Kotlin")) {
            try {
                val kotlinOptions = javaClass.methods.firstOrNull { it.name == "getKotlinOptions" }?.invoke(this)
                if (kotlinOptions != null) {
                    val setJvmTarget = kotlinOptions.javaClass.methods.firstOrNull { it.name == "setJvmTarget" }
                    setJvmTarget?.invoke(kotlinOptions, "1.8")
                    logger.lifecycle("Configured Kotlin JVM Target to 1.8 for task '$name' in project '${project.name}'")
                }
            } catch (e: Exception) {}
        }
        if (name.contains("Java")) {
            try {
                val setSource = javaClass.methods.firstOrNull { it.name == "setSourceCompatibility" }
                val setTarget = javaClass.methods.firstOrNull { it.name == "setTargetCompatibility" }
                setSource?.invoke(this, "1.8")
                setTarget?.invoke(this, "1.8")
            } catch (e: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
