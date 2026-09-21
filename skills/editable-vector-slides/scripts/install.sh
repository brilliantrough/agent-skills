#!/usr/bin/env bash
# editable-vector-slides setup: install Python packages, verify system tools, run smoke test.
# Idempotent; safe to re-run. Never touches LibreOffice/Chrome installation itself.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-python3}"

fail=0
note() { printf '%s\n' "$*"; }

note "[1/3] Python packages ($($PYTHON --version 2>&1))..."
PACKAGES=(python-pptx Pillow fonttools lxml)
if ! $PYTHON -m pip install --quiet --upgrade "${PACKAGES[@]}" 2>/dev/null; then
  # Debian/Ubuntu externally-managed environments and offline pip both land here.
  $PYTHON -m pip install --quiet --user "${PACKAGES[@]}" 2>/dev/null \
    || $PYTHON -m pip install --quiet --break-system-packages "${PACKAGES[@]}" \
    || { note "  FAIL: pip install failed; create a venv and set PYTHON=<venv python>"; fail=1; }
fi
if [ "$fail" -eq 0 ]; then
  $PYTHON - <<'EOF' || fail=1
import importlib.util
missing = [m for m in ('lxml', 'pptx', 'PIL', 'fontTools') if not importlib.util.find_spec(m)]
assert not missing, f'import check failed: {missing}'
print('  OK: lxml, python-pptx, Pillow, fontTools')
EOF
fi

note "[2/3] System tools..."
hint() { note "  MISSING: $1  →  Debian/Ubuntu: sudo apt install $2   Fedora: sudo dnf install $3   macOS: brew install $4"; fail=1; }
any_of() { for b in "$@"; do command -v "$b" >/dev/null 2>&1 && { note "  OK: $b ($(command -v "$b"))"; return 0; }; done; return 1; }

any_of google-chrome chromium chromium-browser || hint "Chrome/Chromium" "chromium-browser" "chromium" "--cask chromium"
for b in mutool pdfimages pdftoppm; do
  case "$b" in
    mutool)   command -v mutool    >/dev/null && note "  OK: mutool"    || hint mutool mupdf-tools mupdf mupdf ;;
    pdfimages|pdftoppm) command -v "$b" >/dev/null && note "  OK: $b" || hint "$b" poppler-utils poppler poppler ;;
  esac
done
command -v soffice >/dev/null 2>&1 || command -v libreoffice >/dev/null 2>&1 \
  && note "  OK: LibreOffice ($(command -v soffice || command -v libreoffice))" \
  || hint LibreOffice libreoffice libreoffice-fresh "--cask libreoffice"

note "[3/3] Smoke test..."
if $PYTHON "$HERE/check.py" >/dev/null 2>&1; then
  note "  OK: check.py passed"
else
  note "  FAIL: check.py failed"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "SETUP OK — convert with: $PYTHON $HERE/convert.py input.svg --format both --output-dir out"
else
  note "SETUP INCOMPLETE — install the missing items above, then re-run this script."
fi
exit "$fail"
