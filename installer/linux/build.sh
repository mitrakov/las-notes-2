#!/usr/bin/env bash
# v1.0.0 (2026-02-12)
set -eo pipefail
clear

BUILD_PATH=build/linux/x64/release

# check tools
function require() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH ($PATH)"
    exit 1
  fi
}
require flutter
require zip
require git

# switch to main flutter dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$WORK_DIR" && pwd

# get current version
[ -f "pubspec.yaml" ] || { echo "pubspec.yaml not found"; exit 1; }
fullVersion=$(grep "version: " pubspec.yaml)
VERSION=$(echo "$fullVersion" | cut -d " " -f 2 | cut -d "+" -f 1)   # BUILD_NUMBER=$(echo "$fullVersion" | cut -d "+" -f 2)

# modify db.dart file for Linux
sed -i.bkp 's/password: password,//g; s/sqflite_sqlcipher\/sqflite.dart/sqflite_common_ffi\/sqflite_ffi.dart/g' lib/model/db.dart
flutter -v build linux
mv -v lib/model/db.dart.bkp lib/model/db.dart

# copy SQLite library
[ -f "sqlcipher/linux/libsqlite3.so" ] || { echo "SQLite library missing"; exit 1; }
[ -d "$BUILD_PATH/bundle" ] || { echo "Bundle directory missing"; exit 1; }
cp -v sqlcipher/linux/libsqlite3.so $BUILD_PATH/bundle/lib

# make a *.zip
pushd $BUILD_PATH && pwd
mv -v bundle/ lasnotes/
zip -r9 "lasnotes-linux-$VERSION.zip" lasnotes/
popd && pwd

# move to dist/ folder
(cd dist/ && rm -f lasnotes-linux-*.zip)
mv -v "$BUILD_PATH/lasnotes-linux-$VERSION.zip" dist/

# finish
flutter clean

# git
git status
git add "dist/lasnotes-linux-$VERSION.zip"
git status
git commit -m "Release $VERSION for Linux"
git status
read -p "Git push? (Y/n): " -r
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  git push
fi
git status

echo "Done..."
