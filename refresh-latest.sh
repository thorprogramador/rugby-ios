#!/bin/bash

# Rugby +latest File Refresh Script
# This script regenerates the ~/.rugby/bin/+latest file with all existing cached binaries

set -e

RUGBY_BIN_PATH="$HOME/.rugby/bin"
LATEST_FILE="$RUGBY_BIN_PATH/+latest"

echo "🏈 Rugby: Refreshing +latest file with all cached binaries..."

# Check if Rugby bin directory exists
if [ ! -d "$RUGBY_BIN_PATH" ]; then
    echo "❌ Error: Rugby bin directory not found at $RUGBY_BIN_PATH"
    echo "   Make sure you have run 'rugby build' or 'rugby cache' at least once."
    exit 1
fi

# Find all target/config combinations and get the latest binary for each
echo "🔍 Scanning for cached binaries..."
TEMP_FILE=$(mktemp)

# Find all binary directories and group by target/config to get only the latest
find "$RUGBY_BIN_PATH" -type d -maxdepth 3 -mindepth 3 | while read -r binary_path; do
    # Extract target/config part (everything except the hash)
    target_config=$(dirname "$binary_path")
    # Get the creation time and full path
    echo "$(stat -f "%m" "$binary_path") $binary_path"
done | sort -k1,1n | awk '{
    target_config = $2
    gsub(/\/[^\/]+$/, "", target_config)  # Remove hash part
    latest[target_config] = $2            # Keep latest path for each target/config
}
END {
    for (tc in latest) print latest[tc]
}' | sort > "$TEMP_FILE"

BINARIES=$(cat "$TEMP_FILE")
rm "$TEMP_FILE"

if [ -z "$BINARIES" ]; then
    echo "❌ No cached binaries found in $RUGBY_BIN_PATH"
    echo "   Run 'rugby build' or 'rugby cache' to create some binaries first."
    exit 1
fi

# Count binaries
BINARY_COUNT=$(echo "$BINARIES" | wc -l | xargs)
echo "📦 Found $BINARY_COUNT latest binaries (one per target/config)"

# Backup existing +latest file if it exists
if [ -f "$LATEST_FILE" ]; then
    BACKUP_FILE="${LATEST_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$LATEST_FILE" "$BACKUP_FILE"
    echo "💾 Backed up existing +latest file to: $(basename "$BACKUP_FILE")"
fi

# Write all binary paths to +latest file
echo "$BINARIES" > "$LATEST_FILE"

echo "✅ Successfully refreshed +latest file with $BINARY_COUNT latest binaries (one per target/config)"
echo "📄 Updated: $LATEST_FILE"

# Show sample of what was written
echo ""
echo "📋 Sample of binaries in +latest file:"
head -5 "$LATEST_FILE" | sed 's/^/   /'
if [ "$BINARY_COUNT" -gt 5 ]; then
    echo "   ... and $((BINARY_COUNT - 5)) more"
fi

echo ""
echo "🚀 Your +latest file is now ready for S3 upload scripts!"
