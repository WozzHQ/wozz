#!/bin/bash
# verify-anonymization.sh - Verify that anonymization works correctly

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔒 Anonymization Verification"
echo "=============================="
echo ""

# Find the most recent audit tarball
TARBALL=$(ls -t wozz-audit-*.tar.gz 2>/dev/null | head -1)

if [ -z "$TARBALL" ]; then
    echo -e "${RED}❌ No audit tarball found${NC}"
    echo "   Run ./scripts/wozz-audit.sh first"
    exit 1
fi

echo "📦 Found: $TARBALL"
echo ""

# Extract to temp directory
TEMP_DIR=$(mktemp -d)
tar -xzf "$TARBALL" -C "$TEMP_DIR" > /dev/null 2>&1

AUDIT_DIR=$(find "$TEMP_DIR" -type d -name "wozz-audit-*" | head -1)
ANON_FILE="$AUDIT_DIR/pods-anonymized.json"

if [ ! -f "$ANON_FILE" ]; then
    echo -e "${RED}❌ pods-anonymized.json not found${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "🔍 Checking for data leaks..."
echo ""

FAILURES=0

# Check for plain-text "nginx"
if grep -qi "nginx" "$ANON_FILE" 2>/dev/null; then
    echo -e "${RED}❌ FAIL: Found plain-text 'nginx'${NC}"
    grep -i "nginx" "$ANON_FILE" | head -3
    ((FAILURES++))
else
    echo -e "${GREEN}✓ PASS: No plain-text 'nginx' found${NC}"
fi

# Check for plain-text "test-nginx"
if grep -qi "test-nginx" "$ANON_FILE" 2>/dev/null; then
    echo -e "${RED}❌ FAIL: Found plain-text 'test-nginx'${NC}"
    grep -i "test-nginx" "$ANON_FILE" | head -3
    ((FAILURES++))
else
    echo -e "${GREEN}✓ PASS: No plain-text 'test-nginx' found${NC}"
fi

# Check for unhashed generateName
if grep -q '"generateName":' "$ANON_FILE" 2>/dev/null; then
    GENERATE_NAMES=$(grep '"generateName":' "$ANON_FILE" | grep -vE '[a-f0-9]{12}' | head -1)
    if [ -n "$GENERATE_NAMES" ]; then
        echo -e "${RED}❌ FAIL: Found unhashed generateName${NC}"
        echo "$GENERATE_NAMES"
        ((FAILURES++))
    else
        echo -e "${GREEN}✓ PASS: All generateName values are hashed${NC}"
    fi
fi

# Check for unhashed image names
if grep -q '"image":' "$ANON_FILE" 2>/dev/null; then
    IMAGES=$(grep '"image":' "$ANON_FILE" | grep -E '(nginx|latest|docker)' | head -1)
    if [ -n "$IMAGES" ]; then
        echo -e "${RED}❌ FAIL: Found unhashed image names${NC}"
        echo "$IMAGES"
        ((FAILURES++))
    else
        echo -e "${GREEN}✓ PASS: All image values are hashed${NC}"
    fi
fi

# Check for unhashed label values
if grep -q '"app":' "$ANON_FILE" 2>/dev/null; then
    APP_LABELS=$(grep '"app":' "$ANON_FILE" | grep -vE '[a-f0-9]{12}' | grep -v 'null' | head -1)
    if [ -n "$APP_LABELS" ]; then
        echo -e "${RED}❌ FAIL: Found unhashed app label values${NC}"
        echo "$APP_LABELS"
        ((FAILURES++))
    else
        echo -e "${GREEN}✓ PASS: All app label values are hashed${NC}"
    fi
fi

# Check for hashed values (should exist)
if grep -qE '[a-f0-9]{12}' "$ANON_FILE" 2>/dev/null; then
    HASH_COUNT=$(grep -oE '[a-f0-9]{12}' "$ANON_FILE" | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ PASS: Found $HASH_COUNT hashed values${NC}"
else
    echo -e "${YELLOW}⚠ WARNING: No hashed values found (might be empty cluster)${NC}"
fi

# Verify JSON is valid
if python3 -c "import json; json.load(open('$ANON_FILE'))" 2>/dev/null; then
    echo -e "${GREEN}✓ PASS: JSON structure is valid${NC}"
else
    echo -e "${RED}❌ FAIL: JSON structure is invalid${NC}"
    ((FAILURES++))
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "================================"
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✅ ALL CHECKS PASSED${NC}"
    echo "   Anonymization is working correctly!"
    exit 0
else
    echo -e "${RED}❌ $FAILURES CHECK(S) FAILED${NC}"
    echo "   Data leak detected! Do NOT launch."
    exit 1
fi

