#!/usr/bin/env bash
# Android Studio / Gradle 없이 APK를 만드는 스크립트 (Ubuntu + apt 도구 + Maven Central 의 kotlin 컴파일러 사용).
# 필요: apt install aapt apksigner zipalign dalvik-exchange libandroid-23-java junit4 / JDK
# 사용: scripts/build_apk.sh <도구jar폴더> <작업폴더>
set -euo pipefail
TOOLS=${1:?kotlin jar dir}; OUT=${2:?work dir}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BT=/usr/lib/android-sdk/build-tools/debian; AJ=/usr/lib/android-sdk/platforms/android-23/android.jar
SL=$TOOLS/kotlin-stdlib-1.9.24.jar
CP=$(ls "$TOOLS"/*.jar | tr '\n' ':')
kc() { java -cp "$CP" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect "$@"; }
SRC=$ROOT/app/src/main/java/com/wildflow/magiccalc
rm -rf "$OUT/build" "$OUT/jvmtest"; mkdir -p "$OUT/build/classes" "$OUT/jvmtest"
echo "== unit tests"
kc -cp "$SL:/usr/share/java/junit4.jar" -d "$OUT/jvmtest" "$SRC/CalcEngine.kt" "$ROOT/app/src/test/java/com/wildflow/magiccalc/CalcEngineTest.kt"
java -cp "$OUT/jvmtest:$SL:/usr/share/java/junit4.jar:/usr/share/java/hamcrest-core.jar" org.junit.runner.JUnitCore com.wildflow.magiccalc.CalcEngineTest | tail -3
echo "== compile"
kc -jvm-target 1.8 -Xlambdas=class -Xsam-conversions=class -cp "$SL:$AJ" -d "$OUT/build/classes" "$SRC"/*.kt
cp "$SL" "$OUT/build/stdlib.jar"; zip -q -d "$OUT/build/stdlib.jar" 'META-INF/versions/*' >/dev/null 2>&1 || true
"$BT/dx" --dex --min-sdk-version=26 --output="$OUT/build/classes.dex" "$OUT/build/classes" "$OUT/build/stdlib.jar"
sed 's|<manifest xmlns:android="http://schemas.android.com/apk/res/android">|<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.wildflow.magiccalc">|' "$ROOT/app/src/main/AndroidManifest.xml" > "$OUT/build/AndroidManifest.xml"
"$BT/aapt" package -f -M "$OUT/build/AndroidManifest.xml" -I "$AJ" --min-sdk-version 26 --target-sdk-version 34 --version-code 1 --version-name 1.0 -F "$OUT/build/unsigned.apk"
(cd "$OUT/build" && zip -q -j unsigned.apk classes.dex && "$BT/zipalign" -f 4 unsigned.apk aligned.apk)
[ -f "$OUT/debug.keystore" ] || keytool -genkeypair -keystore "$OUT/debug.keystore" -storepass android -keypass android -alias debug -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=MagicCalc"
"$BT/apksigner" sign --ks "$OUT/debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$OUT/build/magiccalc.apk" "$OUT/build/aligned.apk"
"$BT/apksigner" verify "$OUT/build/magiccalc.apk" && echo "APK: $OUT/build/magiccalc.apk"
