#!/usr/bin/env bash
# Lance l'app dans un simulateur iPhone et capture les écrans principaux en mode démonstration.
# Usage : scripts/screenshots.sh <chemin/Growtin.app> <dossier de sortie>
set -euo pipefail
APP_PATH="$1"
OUT_DIR="$2"
BUNDLE_ID="app.growtin.ios"
mkdir -p "$OUT_DIR"

# Choisit le simulateur iPhone le plus récent disponible.
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in data if "iOS" in r), reverse=True)
for runtime in runtimes:
    phones = [d for d in data[runtime] if d["name"].startswith("iPhone") and "Pro" in d["name"] and "Max" not in d["name"]]
    phones = phones or [d for d in data[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[-1]["udid"]); break
')
echo "Simulateur : $DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

capture() {
  local name="$1"; shift
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" "$@" >/dev/null
  # Attente adaptative : un écran vide (barre d'état seule) pèse moins de 150 Ko.
  # On reprend la capture jusqu'à ce que l'interface soit affichée, puis on laisse les animations finir.
  local size=0
  for attempt in $(seq 1 15); do
    sleep 3
    xcrun simctl io "$DEVICE_ID" screenshot "$OUT_DIR/$name.png" >/dev/null 2>&1 || continue
    size=$(stat -f%z "$OUT_DIR/$name.png" 2>/dev/null || echo 0)
    if [ "$size" -gt 150000 ]; then
      sleep 2
      xcrun simctl io "$DEVICE_ID" screenshot "$OUT_DIR/$name.png" >/dev/null
      break
    fi
  done
  echo "Capture : $name ($((size / 1024)) Ko)"
}

for appearance in light dark; do
  xcrun simctl ui "$DEVICE_ID" appearance "$appearance"
  capture "$appearance-01-onboarding-bienvenue" -demoScreen onboarding -demoStep 0
  capture "$appearance-10-aujourdhui" -demoScreen today
  capture "$appearance-20-progres" -demoScreen progress
  capture "$appearance-53-photo-comparaison" -demoScreen photoCompare
  capture "$appearance-60-nutrition" -demoScreen nutrition
  capture "$appearance-30-coach" -demoScreen coach
  if [ "$appearance" = "light" ]; then
    for step in 1 2 3 4 5 6 7 8 9 10 11; do
      capture "light-02-onboarding-etape-$(printf "%02d" $step)" -demoScreen onboarding -demoStep "$step"
    done
    capture "light-11-fiche-de-preuve" -demoScreen evidence
    capture "light-12-bilan-du-jour" -demoScreen checkin
    capture "light-13-routine" -demoScreen editRoutine
    capture "light-14-respiration" -demoScreen breathing
    capture "light-15-reglages" -demoScreen settings
    capture "light-16-premium" -demoScreen paywall
    capture "light-31-coach-consentement" -demoScreen coachConsent
    capture "light-40-explorer" -demoScreen explore
    capture "light-41-exercice" -demoScreen exercise
    capture "light-42-seance-exercice" -demoScreen exerciseSession
    capture "light-43-article" -demoScreen article
    capture "light-61-recette" -demoScreen recipe
    capture "light-62-planning" -demoScreen mealPlan
    capture "light-63-courses" -demoScreen shopping
    capture "light-50-photo-seance" -demoScreen photoSession
    capture "light-51-photo-capture" -demoScreen photoCapture
    capture "light-52-photo-frise" -demoScreen photoTimeline
    capture "light-54-photo-lecture-ia" -demoScreen photoReading
    capture "light-55-photo-lecture-consentement" -demoScreen photoReadingConsent
  fi
done
