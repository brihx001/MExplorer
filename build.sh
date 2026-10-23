#!/bin/bash
# Construit MExplorer.app (bundle signe ad-hoc avec le sandbox actif).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="MExplorer.app"
BIN=".build/${CONFIG}/MExplorer"

# Contraintes de toolchain sans Xcode selectionne (macOS 27 / Swift 6.4) :
#  - le systeme de compilation par defaut (swiftbuild) echoue avec les seuls
#    Command Line Tools, y compris sur un paquet vide ("Unknown error parsing
#    property list") ; le systeme natif, lui, fonctionne ;
#  - les macros SwiftUI (@State, @Observable...) sont fournies par un greffon
#    livre uniquement avec Xcode, absent des Command Line Tools.
BUILD_ARGS=()
if swift build --build-system native --help >/dev/null 2>&1; then
  BUILD_ARGS+=(--build-system native)
fi

MACRO_PLUGINS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
if [ -f "${MACRO_PLUGINS}/libSwiftUIMacros.dylib" ]; then
  BUILD_ARGS+=(-Xswiftc -plugin-path -Xswiftc "${MACRO_PLUGINS}")
elif ! [ -f "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
  echo "ATTENTION : greffon de macros SwiftUI introuvable." >&2
  echo "Installez Xcode, ou selectionnez-le : sudo xcode-select -s /Applications/Xcode.app" >&2
fi

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}" "${BUILD_ARGS[@]}"

echo "==> assemblage du bundle"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/MExplorer"
cp Packaging/Info.plist "${APP}/Contents/Info.plist"
if [ -f Packaging/AppIcon.icns ]; then
  cp Packaging/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
else
  echo "ATTENTION : Packaging/AppIcon.icns absent." >&2
  echo "Regenerez-la : cd Packaging/Icon && swift make-icon.swift . && iconutil --convert icns --output ../AppIcon.icns AppIcon.iconset" >&2
fi
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Identite de signature.
#
# En ad-hoc, l'empreinte du code sert d'identite : elle change a chaque
# reconstruction, et macOS oublie alors toutes les autorisations de
# confidentialite accordees (volumes amovibles, Telechargements, Bureau...).
# L'utilisateur les redonne a chaque mise a jour.
#
# Signer avec un certificat stable - "Apple Development: ..." suffit - lie les
# autorisations au certificat et non au binaire : elles survivent aux
# reconstructions. Le certificat n'est pas publie : les artefacts de release
# restent signes en ad-hoc.
#
#   MEXPLORER_SIGN_IDENTITY="Apple Development: moi@exemple.fr (XXXXXXXXXX)" ./build.sh release
#
# Ou, une fois pour toutes, en ecrivant cette ligne dans .signing-identity
# (fichier local, ignore par git).
IDENTITY="${MEXPLORER_SIGN_IDENTITY:-}"
if [ -z "${IDENTITY}" ] && [ -f .signing-identity ]; then
  IDENTITY="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' .signing-identity)"
fi

if [ -n "${IDENTITY}" ]; then
  echo "==> signature + entitlements (${IDENTITY})"
else
  echo "==> signature ad-hoc + entitlements"
  IDENTITY="-"
fi
codesign --force --sign "${IDENTITY}" \
  --entitlements Packaging/MExplorer.entitlements \
  --options runtime \
  --timestamp=none \
  "${APP}"

codesign --verify --verbose=2 "${APP}" 2>&1 | sed 's/^/    /'
echo "==> OK : $(pwd)/${APP}"
