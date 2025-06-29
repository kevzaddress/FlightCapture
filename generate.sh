#!/bin/bash

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen is not installed. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "Homebrew is not installed. Please install Homebrew first:"
        echo "https://brew.sh"
        exit 1
    fi
    brew install xcodegen
fi

# Remove existing Xcode project
if [ -d "FlightCapture.xcodeproj" ]; then
    echo "Removing existing Xcode project..."
    rm -rf FlightCapture.xcodeproj
fi

# Generate new Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo "Xcode project generated successfully!"
echo "You can now open FlightCapture.xcodeproj in Xcode" 