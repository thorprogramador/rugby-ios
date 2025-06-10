#!/bin/bash

# Script to automate the creation of the Rugby release package.

# Exit immediately if a command exits with a non-zero status.
set -e

# Define the root directory of the project
PROJECT_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
RELEASE_DIR="$PROJECT_ROOT_DIR/releases"
RUGBY_BINARY_NAME="rugby"
INSTALL_SCRIPT_SOURCE="$PROJECT_ROOT_DIR/install-prebuilt-rugby.sh"
INSTALL_SCRIPT_DESTINATION="$RELEASE_DIR/install.sh"
BUILT_BINARY_PATH="$PROJECT_ROOT_DIR/.build/releases/$RUGBY_BINARY_NAME"

echo "🚀 Starting the release packaging process..."

# 1. Create the release directory
echo "📂 Creating release directory: $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 2. Build the rugby binary in release mode
echo "🛠️  Building Rugby binary in release mode (swift build -c release --product rugby)..."
swift build -c release --product rugby
if [ $? -ne 0 ]; then
  echo "❌ Error: Swift build failed."
  exit 1
fi
echo "✅ Rugby binary built successfully."

# 3. Copy the built rugby binary to the release folder
echo "📦 Copying Rugby binary to $RELEASE_DIR/$RUGBY_BINARY_NAME..."
cp "$BUILT_BINARY_PATH" "$RELEASE_DIR/$RUGBY_BINARY_NAME"
if [ $? -ne 0 ]; then
  echo "❌ Error: Failed to copy Rugby binary."
  exit 1
fi
chmod +x "$RELEASE_DIR/$RUGBY_BINARY_NAME"
echo "✅ Rugby binary copied and made executable."

# 4. Generate the install.sh script with GitHub download logic
echo "📄 Generating install script at $INSTALL_SCRIPT_DESTINATION..."
cat << 'EOF' > "$INSTALL_SCRIPT_DESTINATION"
#!/bin/bash

# Script to download and install a pre-compiled version of Rugby from a GitHub release.

# --- Configuration for your fork ---
# Ensure these are correct for your repository and desired release
GITHUB_USER="thorprogramador"
GITHUB_REPO="rugby-ios"
RELEASE_TAG="3.0.21" # IMPORTANT: Update this tag for new releases!
BINARY_NAME="rugby"
DOWNLOAD_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$RELEASE_TAG/$BINARY_NAME"

echo "🚀 Rugby Installer for $GITHUB_USER/$GITHUB_REPO, version $RELEASE_TAG"
echo "Binary name: $BINARY_NAME"

# --- Download the binary ---
echo "📥 Downloading Rugby binary from $DOWNLOAD_URL..."
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

# Verify that the downloaded binary works
echo "🔍 Verifying that the binary works..."
if ! ./$BINARY_NAME --version >/dev/null 2>&1; then
  echo "❌ Error: The binary '$BINARY_NAME' does not seem to function correctly."
  echo "   Verify it is compatible with your system ($(uname -m))."
  popd > /dev/null
  exit 1
fi
echo "✅ Downloaded binary is functional."

# Directorio de instalación
INSTALL_DIR="$HOME/.rugby/bin"
mkdir -p "$INSTALL_DIR"

# Eliminar versión anterior si existe
if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
  echo "🗑️  Removing previous version of Rugby from $INSTALL_DIR/$BINARY_NAME..."
  rm "$INSTALL_DIR/$BINARY_NAME"
fi

# Copiar el binario
echo "📦 Installing Rugby to $INSTALL_DIR/$BINARY_NAME..."
cp "./$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

# Clean up by exiting the temporary directory (handled by popd before trap or here)
popd > /dev/null
# TMP_DIR will be removed by the trap

echo "✅ Rugby ($BINARY_NAME) version $RELEASE_TAG installed successfully to $INSTALL_DIR."

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
PATH_STRING="export PATH=\\"$INSTALL_DIR:\\$PATH\\""

# Remove old Rugby PATH entries to avoid duplicates and ensure it's at the start
if grep -q "$PATH_ENTRY_COMMENT" "$SHELL_CONFIG_FILE"; then
    echo "🔄 Removing existing Rugby PATH configuration from $SHELL_CONFIG_FILE..."
    # Use a temporary file for sed -i compatibility on macOS
    TMP_SED_FILE_PATH=$(mktemp)
    sed "/$PATH_ENTRY_COMMENT/d" "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    sed "/export PATH=\\".*$INSTALL_DIR:\\$PATH\\"/d" "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    # Clean up any empty lines that might result from deletion
    sed '/^$/d' "$SHELL_CONFIG_FILE" > "$TMP_SED_FILE_PATH" && mv "$TMP_SED_FILE_PATH" "$SHELL_CONFIG_FILE"
    rm -f "$TMP_SED_FILE_PATH"
fi

echo "🔄 Adding $INSTALL_DIR to your PATH in $SHELL_CONFIG_FILE..."
echo -e "\\n$PATH_ENTRY_COMMENT\\n$PATH_STRING" >> "$SHELL_CONFIG_FILE"
echo "✅ Rugby PATH configured. Please restart your terminal or run 'source $SHELL_CONFIG_FILE'."


echo "📋 You can now run Rugby with the command: $BINARY_NAME"

# Verify the installation by checking the version using the (potentially) new PATH
echo ""
echo "🔍 Verifying installation (using updated PATH in current session for check)..."
export PATH="$INSTALL_DIR:$PATH" # Update PATH for current script session
if command -v $BINARY_NAME &> /dev/null; then
    echo "✅ Verification successful: $($BINARY_NAME --version)"
else
    echo "❌ Verification failed. Try running 'source $SHELL_CONFIG_FILE' and then '$BINARY_NAME --version'."
fi

echo ""
echo "🚀 Example usage:"
echo "$BINARY_NAME --version"
echo "$BINARY_NAME build -v -o fold --except NavigationMocks" # Example command

echo ""
echo "📝 Notes:"
echo "- This installation of Rugby (version $RELEASE_TAG from $GITHUB_USER/$GITHUB_REPO) will take precedence if other versions are in your PATH."
echo "- This installation is local to the current user ($USER)."
EOF
# 4. Copy and rename the install script
# echo "📄 Copying install script from $INSTALL_SCRIPT_SOURCE to $INSTALL_SCRIPT_DESTINATION..."
# cp "$INSTALL_SCRIPT_SOURCE" "$INSTALL_SCRIPT_DESTINATION"
# if [ $? -ne 0 ]; then
#  echo "❌ Error: Failed to copy install script."
#  exit 1
# fi
chmod +x "$INSTALL_SCRIPT_DESTINATION"
echo "✅ Install script generated at $INSTALL_SCRIPT_DESTINATION and made executable."

echo "🎉 Release package created successfully in $RELEASE_DIR"
echo "Contains:"
echo "  - $RUGBY_BINARY_NAME (release binary)"
echo "  - install.sh (installation script)"
echo ""
echo "Next steps:"
echo "1. Review $INSTALL_SCRIPT_DESTINATION. The GITHUB_USER, GITHUB_REPO, and BINARY_NAME are set."
echo "   IMPORTANT: Ensure RELEASE_TAG (currently '$RELEASE_TAG') in $INSTALL_SCRIPT_DESTINATION is correct for the version you are releasing."
echo "2. Commit these changes to your Git repository."
echo "3. Create a new release on GitHub with the tag you specified in install.sh."
echo "4. Upload '$RELEASE_DIR/$RUGBY_BINARY_NAME' and '$INSTALL_SCRIPT_DESTINATION' as assets to that GitHub release."
echo "5. Host the '$INSTALL_SCRIPT_DESTINATION' (e.g., via GitHub Pages) and use its URL for installation."

