#!/bin/bash

# Navigate to the iOS directory
cd ios

# Create the directory structure if it doesn't exist
mkdir -p "Target Support Files/Pods-Runner"

# Create empty xcfilelist files to prevent the build error
touch "Target Support Files/Pods-Runner/Pods-Runner-resources-Debug-input-files.xcfilelist"
touch "Target Support Files/Pods-Runner/Pods-Runner-resources-Debug-output-files.xcfilelist"
touch "Target Support Files/Pods-Runner/Pods-Runner-frameworks-Debug-input-files.xcfilelist"
touch "Target Support Files/Pods-Runner/Pods-Runner-frameworks-Debug-output-files.xcfilelist"

echo "xcfilelist files created successfully!"