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
    "android.permission.SEND_SMS",
    "android.permission.VIBRATE",
    "android.permission.ACTIVITY_RECOGNITION",
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_STATE",
    "android.permission.BLUETOOTH_ADVERTISE",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.NEARBY_WIFI_DEVICES",
]
# Legados (Android 11 ou anterior), com limite de versão.
LEGACY = [
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>',
]

m = manifest.read_text()
for perm in PERMISSIONS:
    tag = f'<uses-permission android:name="{perm}"/>'
    if perm not in m:
        m = m.replace("<application", f"{tag}\n    <application", 1)

for tag in LEGACY:
    if tag not in m:
        m = m.replace("<application", f"{tag}\n    <application", 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="GAZMAP"', m, count=1)

# Abrir links (WhatsApp, telefone, mapa) a partir do app.
for scheme in ("https", "tel", "sms", "geo"):
    tag = f'<data android:scheme="{scheme}"/>'
    if tag not in m:
        block = (f'<intent>\n            <action android:name="android.intent.action.VIEW"/>\n'
                 f'            {tag}\n        </intent>')
        m = m.replace("<queries>", f"<queries>\n        {block}", 1)

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

# compileSdk 36 (exigido por versões recentes de alguns plugins).
for name in ("build.gradle", "build.gradle.kts"):
    f = ROOT / "android/app" / name
    if f.exists():
        s = f.read_text()
        s = s.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
        s = s.replace("compileSdkVersion flutter.compileSdkVersion", "compileSdkVersion 36")
        f.write_text(s)

print("Manifest e Gradle configurados.")

# Ícone do app (idêntico ao logo do site; gerado por tool/generate_icons.py).
import shutil
icons = ROOT / "assets/icon"
res = ROOT / "android/app/src/main/res"
for d in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    target = res / f"mipmap-{d}"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy(icons / f"ic_launcher_{d}.png", target / "ic_launcher.png")
    shutil.copy(icons / f"ic_launcher_foreground_{d}.png", target / "ic_launcher_foreground.png")
anydpi = res / "mipmap-anydpi-v26"
anydpi.mkdir(parents=True, exist_ok=True)
(anydpi / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n'
)
values = res / "values"
values.mkdir(parents=True, exist_ok=True)
(values / "ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources>\n    <color name="ic_launcher_background">#FF6B1A</color>\n</resources>\n'
)
print("Ícone do app configurado.")

# Canal nativo (SMS do SOS, lanterna, vibração, bipe).
kt_src = ROOT / "tool/android/MainActivity.kt"
for kt in (ROOT / "android/app/src/main").rglob("MainActivity.kt"):
    shutil.copy(kt_src, kt)
    print("MainActivity.kt substituído em", kt)
for java in (ROOT / "android/app/src/main").rglob("MainActivity.java"):
    raise SystemExit("MainActivity.java inesperado: gere o projeto com Kotlin")
