#!/usr/bin/env bash
# Refresh the bundled CloudWatch agent schema snapshot from upstream.
#
# Usage: ./scripts/bump-schema.sh [ref]
#   ref defaults to "main". Pass a tag or commit SHA to pin a specific version.

set -euo pipefail

REF="${1:-main}"
REPO="aws/amazon-cloudwatch-agent"
UPSTREAM_PATH="translator/config/schema.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_DIR="$SKILL_DIR/schema"
SCHEMA_FILE="$SCHEMA_DIR/schema.json"
VERSION_FILE="$SCHEMA_DIR/SCHEMA_VERSION"

mkdir -p "$SCHEMA_DIR"

# Resolve the ref to a concrete commit SHA so the pin is unambiguous.
SHA="$(curl -fsSL "https://api.github.com/repos/$REPO/commits/$REF" | python -c 'import json,sys; print(json.load(sys.stdin)["sha"])')"

echo "Fetching $UPSTREAM_PATH from $REPO@$SHA"

RAW_URL="https://raw.githubusercontent.com/$REPO/$SHA/$UPSTREAM_PATH"
# Use a tempfile in the schema dir itself to avoid /tmp <-> Windows path issues.
TMP="$SCHEMA_DIR/schema.json.new"
trap 'rm -f "$TMP"' EXIT

curl -fsSL "$RAW_URL" -o "$TMP"

# Sanity-check that what we got is actually JSON. Pass the path as an argv arg
# so we don't have to interpolate quoting into a -c string.
python -c "import json, sys; json.load(open(sys.argv[1]))" "$TMP"

if [[ -f "$SCHEMA_FILE" ]]; then
  echo "Diff against current snapshot:"
  diff -u "$SCHEMA_FILE" "$TMP" || true
fi

mv "$TMP" "$SCHEMA_FILE"
trap - EXIT
echo "$SHA" > "$VERSION_FILE"

echo
echo "Updated $SCHEMA_FILE"
echo "Pinned to $REPO@$SHA"
echo
echo "Review the diff above, then:"
echo "  git add $SCHEMA_FILE $VERSION_FILE"
echo "  git commit -m \"Bump CloudWatch agent schema to $SHA\""
