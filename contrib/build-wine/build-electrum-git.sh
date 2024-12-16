#!/bin/bash

NAME_ROOT=electrum

export PYTHONDONTWRITEBYTECODE=1  # don't create __pycache__/ folders with .pyc files


# Let's begin!
set -e

. "$CONTRIB"/build_tools_util.sh

pushd $WINEPREFIX/drive_c/electrum

#VERSION=$(git describe --tags --dirty --always)
VERSION=4.5.8

info "Last commit: $VERSION"

# Load electrum-locale for this release
git submodule update --init

LOCALE="$WINEPREFIX/drive_c/electrum/electrum/locale/"
# we want the binary to have only compiled (.mo) locale files; not source (.po) files
rm -rf "$LOCALE"
"$CONTRIB/build_locale.sh" "$CONTRIB/deterministic-build/electrum-locale/locale/" "$LOCALE"

find -exec touch -h -d '2000-11-11T11:11:11+00:00' {} +
popd


# opt out of compiling C extensions
export AIOHTTP_NO_EXTENSIONS=1
export YARL_NO_EXTENSIONS=1
export MULTIDICT_NO_EXTENSIONS=1
export FROZENLIST_NO_EXTENSIONS=1
export ELECTRUM_ECC_DONT_COMPILE=1


# Add the new package here
info "Installing electrum_aionostr..."
$WINE_PYTHON -m pip install --no-build-isolation --no-dependencies --no-warn-script-location \
    --cache-dir "$WINE_PIP_CACHE_DIR" electrum_aionostr websockets

info "Installing requirements..."
$WINE_PYTHON -m pip install --no-build-isolation --no-dependencies --no-binary :all: --no-warn-script-location \
    --cache-dir "$WINE_PIP_CACHE_DIR" -r "$CONTRIB"/deterministic-build/requirements.txt
info "Installing dependencies specific to binaries..."
# TODO tighten "--no-binary :all:" (but we don't have a C compiler...)
$WINE_PYTHON -m pip install --no-build-isolation --no-dependencies --no-warn-script-location \
    --no-binary :all: --only-binary cffi,cryptography,PyQt6,PyQt6-Qt6,PyQt6-sip \
    --cache-dir "$WINE_PIP_CACHE_DIR" -r "$CONTRIB"/deterministic-build/requirements-binaries.txt
info "Installing hardware wallet requirements..."
$WINE_PYTHON -m pip install --no-build-isolation --no-dependencies --no-warn-script-location \
    --no-binary :all: --only-binary cffi,cryptography,hidapi \
    --cache-dir "$WINE_PIP_CACHE_DIR" -r "$CONTRIB"/deterministic-build/requirements-hw.txt

pushd $WINEPREFIX/drive_c/electrum
# see https://github.com/pypa/pip/issues/2195 -- pip makes a copy of the entire directory
info "Pip installing Electrum. This might take a long time if the project folder is large."
$WINE_PYTHON -m pip install --no-build-isolation --no-dependencies --no-warn-script-location .
# pyinstaller needs to be able to "import electrum_ecc", for which we need libsecp256k1:
# (or could try "pip install -e" instead)
cp electrum/libsecp256k1-*.dll "$WINEPREFIX/drive_c/python3/Lib/site-packages/electrum_ecc/"
popd


rm -rf dist/

# build standalone and portable versions
info "Running pyinstaller..."
ELECTRUM_CMDLINE_NAME="$NAME_ROOT-$VERSION" wine "$WINE_PYHOME/scripts/pyinstaller.exe" --noconfirm --clean deterministic.spec

# set timestamps in dist, in order to make the installer reproducible
pushd dist
find -exec touch -h -d '2000-11-11T11:11:11+00:00' {} +
popd

info "building NSIS installer"
# $VERSION could be passed to the electrum.nsi script, but this would require some rewriting in the script itself.
makensis -DPRODUCT_VERSION=$VERSION electrum.nsi

cd dist
mv electrum-setup.exe $NAME_ROOT-$VERSION-setup.exe
cd ..


sha256sum dist/electrum*.exe
