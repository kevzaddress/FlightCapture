#!/bin/bash

# Regenerate and open the Xcode project
echo "Regenerating Xcode project..."
./generate.sh

echo "Opening project in Xcode..."
open FlightCapture.xcodeproj 