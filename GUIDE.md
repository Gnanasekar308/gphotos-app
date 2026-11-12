# Gphotos APK - GitHub steps (Tamil + English)

PC-ல எதுவும் install பண்ண வேண்டாம். GitHub website மட்டும் போதும்.

1. github.com → login → **New repository** → name: `gphotos-app` → Public → **Create repository**.
2. **Add file → Upload files**. இந்த folder-ஓட contents (`lib`, `.github`, `pubspec.yaml`, `.gitignore`) எல்லாத்தையும் drag & drop பண்ணுங்க → **Commit changes**.
   - `.github` folder upload ஆகலனா: **Add file → Create new file** → name-ல `.github/workflows/build.yml` type பண்ணி, build.yml content paste பண்ணுங்க.
3. மேல **Actions** tab → "Build APK" → **Run workflow** (push பண்ணாலே auto run ஆகும்).
4. 8-12 நிமிஷம் wait பண்ணுங்க. Green tick வந்தா அந்த run-ஐ open பண்ணுங்க → கீழ **Artifacts → Gphotos-debug-apk** download.
5. Zip extract பண்ணி `app-debug.apk` எடுங்க → phone-க்கு அனுப்புங்க → install (Unknown sources allow).
6. App open → **Allow photos** permission.

Build fail ஆனா (red X): fail ஆன step-ஐ open பண்ணி, last 40 lines copy பண்ணி எனக்கு அனுப்புங்க. நான் fix பண்ணித் தர்றேன்.
