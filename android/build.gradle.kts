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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureCompileSdk = {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                var currentSdk: Int? = null
                try {
                    val getCompileSdkMethod = androidExt.javaClass.getMethod("getCompileSdkVersion")
                    val sdkStr = getCompileSdkMethod.invoke(androidExt)?.toString()
                    currentSdk = sdkStr?.removePrefix("android-")?.toIntOrNull()
                } catch (_: Throwable) {
                    try {
                        val getCompileSdkMethod = androidExt.javaClass.getMethod("getCompileSdk")
                        val sdkVal = getCompileSdkMethod.invoke(androidExt)
                        if (sdkVal is Int) currentSdk = sdkVal
                    } catch (_: Throwable) {}
                }

                if (currentSdk == null || currentSdk < 35) {
                    try {
                        val compileSdkMethod = androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                        compileSdkMethod.invoke(androidExt, 35)
                    } catch (_: Throwable) {
                        try {
                            val setCompileSdkMethod = androidExt.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                            setCompileSdkMethod.invoke(androidExt, 35)
                        } catch (_: Throwable) {
                            try {
                                val setCompileSdkBoxed = androidExt.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java)
                                setCompileSdkBoxed.invoke(androidExt, 35)
                            } catch (_: Throwable) {}
                        }
                    }
                }
            }
        }
    }
    if (project.state.executed) {
        configureCompileSdk()
    } else {
        project.afterEvaluate {
            configureCompileSdk()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
