#!/bin/bash

# Script to download and install a pre-compiled version of Rugby from a GitHub release.

# --- Configuration for your fork ---
# Ensure these are correct for your repository and desired release
GITHUB_USER="thorprogramador"
GITHUB_REPO="rugby-ios"
RELEASE_TAG="3.1.0" # IMPORTANT: Update this tag for new releases!
BINARY_NAME="rugby"
DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$RELEASE_TAG/$BINARY_NAME"

echo "🚀 Rugby Installer for $GITHUB_USER/$GITHUB_REPO, version $RELEASE_TAG"
echo "Binary name: $BINARY_NAME (Universal Binary - supports both x86_64 and arm64)"

# --- Download the binary ---
echo "📥 Downloading Rugby universal binary from $DOWNLOAD_URL..."
TMP_DIR=$(mktemp -d)
if [ -z "$TMP_DIR" ]; then
    echo "❌ Error: Failed to create a temporary directory."
    exit 1
fi
# Ensure TMP_DIR is cleaned up on exit
trap 'rm -rf "$TMP_DIR"' EXIT

pushd "$TMP_DIR" > /dev/null || { echo "❌ Error: Failed to navigate to temporary directory."; exit 1; }

echo "Attempting to download to $(pwd)/$BINARY_NAME"
if curl -SLfo "./$BINARY_NAME" "$DOWNLOAD_URL"; then
    echo "✅ Download complete."
else
    echo "❌ Error: Failed to download Rugby binary from $DOWNLOAD_URL."
    echo "   Please check the GITHUB_USER, GITHUB_REPO, RELEASE_TAG, and ensure the '$BINARY_NAME' asset exists in the specified release."
    echo "   Current directory for download attempt: $(pwd)"
    ls -la # List contents of temp dir for debugging
    popd > /dev/null
    exit 1
fi

# Verify that the binary exists in the temporary directory
if [ ! -f "./$BINARY_NAME" ]; then
  echo "❌ Error: Downloaded binary '$BINARY_NAME' not found in temporary directory '$TMP_DIR'."
  popd > /dev/null
  exit 1
fi

# Make the downloaded binary executable
echo "🔧 Making the downloaded binary executable..."
chmod +x "./$BINARY_NAME"

# Verify binary architecture compatibility
echo "🔍 Verifying binary architecture compatibility..."
CURRENT_ARCH=$(uname -m)
if command -v lipo &> /dev/null; then
    echo "Binary architectures: $(lipo -info "./$BINARY_NAME" 2>/dev/null || echo "Unable to determine")"
fi
echo "Current system architecture: $CURRENT_ARCH"

# Verify that the downloaded binary works
echo "🔍 Verifying that the binary works..."
if ! ./$BINARY_NAME --version >/dev/null 2>&1; then
  echo "❌ Error: The binary '$BINARY_NAME' does not seem to function correctly."
  echo "   Verify it is compatible with your system ($CURRENT_ARCH)."
  popd > /dev/null
  exit 1
fi
echo "✅ Downloaded binary is functional."

# Directorio de instalación
INSTALL_DIR="$HOME/.rugby/clt"

# Store the downloaded binary path before cleanup
DOWNLOADED_BINARY_PATH="$(pwd)/$BINARY_NAME"

# Clean up by exiting the temporary directory first
popd > /dev/null
# TMP_DIR will be removed by the trap

# Agregar al PATH si no está (al principio para que tome precedencia)
SHELL_CONFIG_FILE=""
CURRENT_SHELL=$(basename "$SHELL")

if [ "$CURRENT_SHELL" = "zsh" ]; then
    SHELL_CONFIG_FILE="$HOME/.zshrc"
elif [ "$CURRENT_SHELL" = "bash" ]; then
    if [ -f "$HOME/.bash_profile" ]; then
        SHELL_CONFIG_FILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_CONFIG_FILE="$HOME/.bashrc" # Common on Linux
    else
        SHELL_CONFIG_FILE="$HOME/.profile" # Fallback for bash
    fi
else # Fallback for other shells or if detection fails
    SHELL_CONFIG_FILE="$HOME/.profile"
fi

# Ensure the config file exists
touch "$SHELL_CONFIG_FILE"

PATH_ENTRY_COMMENT="# Rugby PATH entry"
PATH_STRING="export PATH=\"$INSTALL_DIR:\$PATH\""

# Remove old Rugby PATH entries to avoid duplicates and ensure it's at the start
if grep -q "$PATH_ENTRY_COMMENT" "$SHELL_CONFIG_FILE"; then
    echo "🔄 Removing existing Rugby PATH configuration from $SHELL_CONFIG_FILE..."
    # Use a temporary file for sed -i compatibility on macOS
    TMP_SED_FILE_PATH=$(mktemp)
    sed "/$PATH_ENTRY_COMMENT/d" "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    sed "/export PATH=\".*$INSTALL_DIR:\$PATH\"/d" "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    # Clean up any empty lines that might result from deletion
    sed '/^$/d' "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    rm -f "$TMP_SED_FILE_PATH"
fi

# Full cleanup of all Rugby installations and PATH entries
echo "🧹 Performing full cleanup of all Rugby installations..."

# Remove BOTH rugby/bin and rugby/clt directories
OLD_BIN_DIR="$HOME/.rugby/bin"
OLD_CLT_DIR="$HOME/.rugby/clt"

if [ -d "$OLD_BIN_DIR" ]; then
    echo "   Removing Rugby bin directory at $OLD_BIN_DIR..."
    rm -rf "$OLD_BIN_DIR"
fi

if [ -d "$OLD_CLT_DIR" ]; then
    echo "   Removing Rugby clt directory at $OLD_CLT_DIR..."
    rm -rf "$OLD_CLT_DIR"
fi

# Remove ALL Rugby-related PATH exports and entries from shell config
if [ -f "$SHELL_CONFIG_FILE" ]; then
    echo "   Cleaning all Rugby PATH entries from $SHELL_CONFIG_FILE..."
    TMP_SED_FILE_PATH=$(mktemp)
    
    # First pass: Remove all export PATH lines containing .rugby
    grep -v "export PATH=.*\.rugby" "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    
    # Second pass: Remove malformed PATH exports with backslashes
    sed '/export PATH=\\/d' "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    
    # Third pass: Remove Rugby PATH comment lines
    sed '/# Rugby PATH entry/d' "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    
    # Fourth pass: Clean up any remaining .rugby paths from existing PATH exports
    sed 's|:[^:]*\.rugby/[^:]*||g' "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    
    # Clean up any multiple consecutive blank lines
    sed '/^$/N;/^\n$/d' "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    
    rm -f "$TMP_SED_FILE_PATH"
fi

# Now recreate the clt directory for the new installation
mkdir -p "$INSTALL_DIR"

# Copy the binary to the installation directory
echo "📦 Installing Rugby to $INSTALL_DIR/$BINARY_NAME..."
if [ -f "$DOWNLOADED_BINARY_PATH" ]; then
    cp "$DOWNLOADED_BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    echo "✅ Rugby ($BINARY_NAME) version $RELEASE_TAG installed successfully to $INSTALL_DIR."
else
    echo "❌ Error: Downloaded binary not found at $DOWNLOADED_BINARY_PATH"
    exit 1
fi

echo "🔄 Adding $INSTALL_DIR to your PATH in $SHELL_CONFIG_FILE..."
echo "" >> "$SHELL_CONFIG_FILE"
echo "$PATH_ENTRY_COMMENT" >> "$SHELL_CONFIG_FILE"
echo "$PATH_STRING" >> "$SHELL_CONFIG_FILE"
echo "✅ Rugby PATH configured. Please restart your terminal or run 'source $SHELL_CONFIG_FILE'."


echo "📋 You can now run Rugby with the command: $BINARY_NAME"

# Verify the installation by checking the version directly
echo ""
echo "🔍 Verifying installation..."
if [ -f "$INSTALL_DIR/$BINARY_NAME" ] && [ -x "$INSTALL_DIR/$BINARY_NAME" ]; then
    INSTALLED_VERSION=$("$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "✅ Verification successful: Rugby version $INSTALLED_VERSION installed at $INSTALL_DIR/$BINARY_NAME"
    else
        echo "⚠️  Rugby binary installed but unable to get version. Try running '$INSTALL_DIR/$BINARY_NAME --version' directly."
    fi
else
    echo "❌ Verification failed. Rugby binary not found at expected location: $INSTALL_DIR/$BINARY_NAME"
fi
echo ""
echo "📝 To use Rugby, either:"
echo "   1. Restart your terminal, or"
echo "   2. Run: source $SHELL_CONFIG_FILE"
echo "   Then you can use: $BINARY_NAME --version"

echo ""
echo "🚀 Example usage:"
echo "$BINARY_NAME --version"
echo "$BINARY_NAME build -v -o fold --except NavigationMocks" # Example command

echo ""
echo "📝 Notes:"
echo "- This installation of Rugby (version $RELEASE_TAG from $GITHUB_USER/$GITHUB_REPO) will take precedence if other versions are in your PATH."
echo "- This installation is local to the current user ($USER)."
