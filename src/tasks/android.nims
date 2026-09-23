## ---------------------------------------------------------------------------
## android <- build the Android app with Gradle (rare; most repos have none)
## ---------------------------------------------------------------------------
##
##   buildAndroid    -> gradle :app:assembleDebug   (makes the .apk)
##   installAndroid  -> gradle :app:installDebug    (puts it on a phone)
##
## Android project folder, first one found:
##
##   android/
##   src/clients/android/
##   src/client/frontend/android/
##
## or `const androidDir: string = "…"` before the include.
##
## Gradle program, first one found:
##
##   $ANDROID_GRADLE_CMD  ->  <androidDir>/gradlew(.bat)  ->  gradle on PATH
##
## ANDROID_HOME is filled in from the usual SDK folder when it is empty:
##
##   Windows   %USERPROFILE%\AppData\Local\Android\Sdk
##   Linux     ~/Android/Sdk

proc androidDirOrEmpty(): string =
  var
    t: string = overrideOf(androidDir)
  if t.len == 0:
    t = firstExistingDir(["android", "src/clients/android",
      "src/client/frontend/android"])
  result = t

proc androidProjectDir(): string =
  var
    t: string = androidDirOrEmpty()
  if t.len == 0 or not dirExists(t):
    stop("No Android project found. Looked in:\n    android/\n    " &
      "src/clients/android/\n    src/client/frontend/android/\n" &
      "  Or set `const androidDir: string = \"path\"` before the include.")
  result = t

proc gradleCommand(dir: string): string =
  ## dir: Android project folder
  var
    wrapper: string = joinPath(dir, "gradlew")
    t: string = getEnv("ANDROID_GRADLE_CMD")
  when defined(windows):
    wrapper = joinPath(dir, "gradlew.bat")
  if t.len == 0 and fileExists(wrapper):
    t = quoteShell(absolutePath(wrapper))
  if t.len == 0 and findExe("gradle").len > 0:
    t = "gradle"
  if t.len == 0:
    stop("No Gradle found: no " & wrapper & ", no `gradle` on PATH, " &
      "and ANDROID_GRADLE_CMD is empty.")
  result = t

proc configureAndroidEnv() =
  var
    sdk: string = joinPath(getHomeDir(), "Android", "Sdk")
  when defined(windows):
    sdk = joinPath(getHomeDir(), "AppData", "Local", "Android", "Sdk")
  if getEnv("ANDROID_HOME").len == 0 and getEnv("ANDROID_SDK_ROOT").len == 0 and
      dirExists(sdk):
    putEnv("ANDROID_HOME", sdk)

proc gradle(step: string) =
  ## step: gradle target, e.g. ":app:assembleDebug"
  var
    dir: string = androidProjectDir()
  configureAndroidEnv()
  withDir(dir):
    exec gradleCommand(".") & " " & step

proc buildAndroidApk() =
  gradle(":app:assembleDebug")

sharedTask buildAndroid, "Build the Android debug APK":
  buildAndroidApk()

sharedTask installAndroid, "Build and install the Android debug APK on a connected device":
  gradle(":app:installDebug")
