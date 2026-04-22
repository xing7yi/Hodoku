#!/usr/bin/env zsh
# =============================================================================
# build-mac.sh  —  Build HoDoKu and package as a native macOS .app
#
# Requirements:
#   - JDK 8 (Amazon Corretto 8) for compiling (matches existing source level)
#   - JDK 21 (Temurin 21) for jpackage
#   - macOS with iconutil available (standard on macOS)
#
# Usage:
#   ./build-mac.sh           # build jar + .app
#   ./build-mac.sh --jar     # build jar only
#   ./build-mac.sh --pkg     # package existing jar into .app only
# =============================================================================

set -e

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

# --------------- Toolchain ---------------------------------------------------
JAVA8_HOME=$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)
JAVA21_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || true)

if [[ -z "$JAVA8_HOME" ]]; then
  echo "ERROR: JDK 8 not found. Install Amazon Corretto 8." >&2
  exit 1
fi
if [[ -z "$JAVA21_HOME" ]]; then
  echo "ERROR: JDK 21 not found. Run: brew install --cask temurin@21" >&2
  exit 1
fi

JAVAC="$JAVA8_HOME/bin/javac"
JAR_CMD="$JAVA8_HOME/bin/jar"
JPACKAGE="$JAVA21_HOME/bin/jpackage"

# --------------- Paths -------------------------------------------------------
SRC_DIR="$SCRIPT_DIR/src"
BUILD_DIR="$SCRIPT_DIR/build/classes"
DIST_DIR="$SCRIPT_DIR/dist"
STAGING_DIR="$SCRIPT_DIR/dist/staging"
JAR_FILE="$STAGING_DIR/Hodoku.jar"
ICON_PNG="$SRC_DIR/img/hodoku02-256.png"
ICON_FILE="$SCRIPT_DIR/packaging/icons/hodoku.icns"
ICON_ICONSET="$SCRIPT_DIR/packaging/icons/hodoku.iconset"
APP_OUT_DIR="$SCRIPT_DIR/dist"

APP_NAME="HoDoKu"
APP_VERSION="2.3.0"
MAIN_CLASS="sudoku.Main"

# --------------- Argument parsing --------------------------------------------
BUILD_JAR=true
BUILD_APP=true

for arg in "$@"; do
  case "$arg" in
    --jar) BUILD_APP=false ;;
    --pkg) BUILD_JAR=false ;;
  esac
done

# =============================================================================
# 1. Compile
# =============================================================================
if $BUILD_JAR; then
  echo ">>> Compiling Java sources (JDK 8)..."
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  # Collect all .java files
  find "$SRC_DIR" -name "*.java" > /tmp/hodoku_sources.txt

  "$JAVAC" \
    -source 8 -target 8 \
    -encoding UTF-8 \
    -d "$BUILD_DIR" \
    @/tmp/hodoku_sources.txt

  echo "    Compiled $(wc -l < /tmp/hodoku_sources.txt | tr -d ' ') source files."

  # =============================================================================
  # 2. Copy resources (non-Java files from src/)
  # =============================================================================
  echo ">>> Copying resources..."
  # Copy all non-.java files preserving directory structure
  find "$SRC_DIR" \( -name "*.java" -o -name ".DS_Store" \) -prune -o -type f -print | while read f; do
    rel="${f#$SRC_DIR/}"
    dest="$BUILD_DIR/$rel"
    mkdir -p "${dest:h}"
    cp "$f" "$dest"
  done
  # Copy templates.dat to the root of the jar (not inside a package)
  if [[ -f "$SRC_DIR/templates.dat" ]]; then
    cp "$SRC_DIR/templates.dat" "$BUILD_DIR/"
  fi

  # =============================================================================
  # 3. Create JAR with manifest
  # =============================================================================
  echo ">>> Creating JAR..."
  mkdir -p "$STAGING_DIR"

  # Write manifest
  cat > /tmp/hodoku_manifest.txt <<MANIFEST
Manifest-Version: 1.0
Main-Class: $MAIN_CLASS
MANIFEST

  "$JAR_CMD" cfm "$JAR_FILE" /tmp/hodoku_manifest.txt -C "$BUILD_DIR" .
  echo "    JAR: $JAR_FILE ($(du -sh "$JAR_FILE" | cut -f1))"
fi

# =============================================================================
# 4. Generate .icns icon
# =============================================================================
if $BUILD_APP; then
  echo ">>> Generating .icns icon..."
  mkdir -p "$ICON_ICONSET"
  sips -z 16 16   "$ICON_PNG" --out "$ICON_ICONSET/icon_16x16.png"    &>/dev/null
  sips -z 32 32   "$ICON_PNG" --out "$ICON_ICONSET/icon_16x16@2x.png" &>/dev/null
  sips -z 32 32   "$ICON_PNG" --out "$ICON_ICONSET/icon_32x32.png"    &>/dev/null
  sips -z 64 64   "$ICON_PNG" --out "$ICON_ICONSET/icon_32x32@2x.png" &>/dev/null
  sips -z 128 128 "$ICON_PNG" --out "$ICON_ICONSET/icon_128x128.png"  &>/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICON_ICONSET/icon_128x128@2x.png" &>/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICON_ICONSET/icon_256x256.png"  &>/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICON_ICONSET/icon_256x256@2x.png" &>/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICON_ICONSET/icon_512x512.png"  &>/dev/null
  iconutil -c icns "$ICON_ICONSET" -o "$ICON_FILE"
  echo "    Icon: $ICON_FILE"
fi

# =============================================================================
# 5. Package with jpackage
# =============================================================================
if $BUILD_APP; then
  echo ">>> Packaging macOS DMG with jpackage (JDK 21)..."

  # Remove previous DMG if any
  rm -f "$APP_OUT_DIR/${APP_NAME}-${APP_VERSION}.dmg"

  "$JPACKAGE" \
    --type dmg \
    --name "$APP_NAME" \
    --app-version "$APP_VERSION" \
    --input "$STAGING_DIR" \
    --main-jar "Hodoku.jar" \
    --main-class "$MAIN_CLASS" \
    --icon "$ICON_FILE" \
    --dest "$APP_OUT_DIR" \
    --java-options "-Dapple.awt.application.name=$APP_NAME" \
    --java-options "-Dapple.laf.useScreenMenuBar=true" \
    --java-options "-Dapple.awt.graphics.UseQuartz=true" \
    --java-options "-Dapple.awt.fullscreencapturealldisplays=false" \
    --java-options "-Dsun.java2d.metal=true" \
    --java-options "-Xms64m" \
    --java-options "-Xmx512m"

  echo ""
  echo "========================================="
  echo "  Built: $APP_OUT_DIR/${APP_NAME}-${APP_VERSION}.dmg"
  echo "  Open with: open \"$APP_OUT_DIR/${APP_NAME}-${APP_VERSION}.dmg\""
  echo "========================================="
fi
