#!/bin/bash
# KanaPath — First time setup script
# Run this after cloning the repository

echo "🚀 KanaPath Setup"
echo ""

# Check flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first."
    exit 1
fi

echo "📦 Running flutter pub get..."
flutter pub get

echo ""
echo "✅ Setup complete! pubspec.lock has been generated."
echo "   Please commit pubspec.lock: git add pubspec.lock && git commit -m 'chore: add pubspec.lock'"
echo ""
echo "🔨 To build debug APK:"
echo "   flutter build apk --debug"
