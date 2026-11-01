"""Aplica as configurações Android do GAZMAP (idempotente)."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
manifest = ROOT / "android/app/src/main/AndroidManifest.xml"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]

m = manifest.read_text()
for perm in PERMISSIONS:
    tag = f'<uses-permission android:name="{perm}"/>'
    if perm not in m:
        m = m.replace("<application", f"{tag}\n    <application", 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="GAZMAP"', m, count=1)

# Necessário para os avisos por voz (Android 11+).
tts = '<action android:name="android.intent.action.TTS_SERVICE"/>'
if tts not in m:
    block = f"<intent>\n            {tts}\n        </intent>"
    if "<queries>" in m:
        m = m.replace("<queries>", f"<queries>\n        {block}", 1)
    else:
        m = m.replace("</manifest>", f"    <queries>\n        {block}\n    </queries>\n</manifest>")
manifest.write_text(m)

# Kotlin mais recente (exigido por alguns plugins).
for name in ("settings.gradle", "settings.gradle.kts"):
    f = ROOT / "android" / name
    if f.exists():
        s = f.read_text()
        s = re.sub(r'(org\.jetbrains\.kotlin\.android"\)?\s*version\s*")1\.[0-8]\.\d+', r"\g<1>1.9.24", s)
        f.write_text(s)

# compileSdk 35 (exigido por versões recentes de alguns plugins).
for name in ("build.gradle", "build.gradle.kts"):
    f = ROOT / "android/app" / name
    if f.exists():
        s = f.read_text()
        s = s.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 35")
        s = s.replace("compileSdkVersion flutter.compileSdkVersion", "compileSdkVersion 35")
        f.write_text(s)

print("Manifest e Gradle configurados.")
