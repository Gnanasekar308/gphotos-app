# Gphotos APK - GitHub steps (Tamil + English)

PC-ல Flutter install பண்ண வேண்டாம். GitHub Actions APK build பண்ணும்.

1. Repo: https://github.com/Gnanasekar308/gphotos-app (code already uploaded).
2. **Actions** tab → "Build APK" → latest run. Push பண்ணாலே auto run ஆகும்; manual-ஆ **Run workflow** கூட பண்ணலாம்.
3. Run steps: Analyze → Tests → Build debug APK. 10-15 நிமிஷம் ஆகும்.
4. Green tick வந்தா run-ஐ open பண்ணுங்க → கீழ **Artifacts → Gphotos-debug-apk** download.
5. Zip extract → `app-debug.apk` → phone-க்கு அனுப்பி install (Unknown sources allow).
6. App open → **Allow access** (photos permission).

First use:
- **People** tab → **Scan library**: முழு library-யும் scan ஆகும் (app open-ஆ இருக்கும்போது). Pause பண்ணி அப்புறம் Continue பண்ணலாம்.
  Groups approximate: தப்பா இருந்தா Person open பண்ணி faces select → Split / Move / Not a face; Merge menu-ல.
- **Vault**: முதல் தடவை PIN (4-8 digits) create பண்ணுங்க. PIN மறந்தா vault open ஆகாது.
  Photos select → lock icon → encrypt + verify ஆன பிறகு "Delete originals?" கேக்கும்.
- Photos tab: long-press + slide = பல photos select (மேல/கீழ edge-க்கு போனா auto scroll). இரண்டு விரல் pinch = columns மாறும்.

Build fail ஆனா (red X): fail ஆன step-ஐ open பண்ணி last 40 lines copy பண்ணி அனுப்புங்க.
