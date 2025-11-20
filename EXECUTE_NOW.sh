#!/bin/bash
# EXECUTE_NOW.sh - One-command publish to GitHub
# Run this to publish the K8s audit tool to WozzHQ/wozz

set -e

echo "🚀 Publishing Wozz K8s Audit Tool to GitHub"
echo "=============================================="
echo ""

# Verify we're in the right directory
if [ ! -f "scripts/wozz-audit.sh" ]; then
    echo "❌ Error: scripts/wozz-audit.sh not found"
    echo "   Make sure you're in the Wozz-app directory"
    exit 1
fi

echo "✅ Found audit script"
echo ""

# Stage public files
echo "📦 Staging public files..."
git add README.md LICENSE .gitignore package.json
git add scripts/
git add test-fixtures/

# Remove old files
echo "🗑️  Removing old files..."
git rm SETUP.md airbyte-story.html how-it-works.html index.html vercel.json 2>/dev/null || true

# Show what will be committed
echo ""
echo "📋 Files to be committed:"
git status --short | grep -E "^[AM]|^D " | head -10
echo ""

# Ask for confirmation
read -p "Continue with commit and push? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

# Update remote
echo ""
echo "🔗 Updating remote to WozzHQ/wozz..."
git remote remove origin 2>/dev/null || true
git remote add origin git@github.com:WozzHQ/wozz.git

# Commit
echo ""
echo "💾 Committing changes..."
git commit -m "feat: Kubernetes cost audit tool - Phase 1 release

- Add wozz-audit.sh for cluster data collection
- Add analyze-audit.py for waste analysis
- Add test fixtures and verification scripts
- All sensitive data properly anonymized
- Verified: anonymization works correctly

This replaces the previous AWS/Terraform implementation with
a Kubernetes-focused cost optimization tool."

# Force push
echo ""
echo "🚀 Force pushing to GitHub (overwrites old code)..."
git push -f origin main

# Create release tag
echo ""
echo "🏷️  Creating release tag..."
git tag -a v0.1.0 -m "Initial release - Kubernetes cost audit script"
git push origin v0.1.0

echo ""
echo "✅ Published successfully!"
echo ""
echo "Next steps:"
echo "1. Visit: https://github.com/WozzHQ/wozz"
echo "2. Verify: Only public files visible"
echo "3. Create release: Go to Releases → Draft new release → Select v0.1.0"
echo ""
echo "🎉 Done!"

