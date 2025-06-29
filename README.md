# FlightCapture

A SwiftUI iOS application for flight capture functionality.

## Project Setup with XcodeGen

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from a specification file. This approach provides several benefits:

- **Version Control Friendly**: The project structure is defined in `project.yml` instead of complex Xcode project files
- **Consistent Structure**: Ensures all team members have the same project structure
- **Easy Maintenance**: Adding new files or targets is as simple as updating the YAML file

## Getting Started

### Prerequisites

- Xcode 15.0 or later
- macOS (for development)
- Homebrew (for installing xcodegen)

### Installation

1. **Install XcodeGen** (if not already installed):
   ```bash
   brew install xcodegen
   ```

2. **Generate the Xcode Project**:
   ```bash
   ./generate.sh
   ```
   
   Or manually:
   ```bash
   xcodegen generate
   ```

3. **Open the Project**:
   ```bash
   open FlightCapture.xcodeproj
   ```

## Project Structure

```
FlightCapture/
├── project.yml          # XcodeGen project specification
├── generate.sh          # Script to regenerate the Xcode project
├── FlightCapture/       # Source code directory
│   ├── FlightCaptureApp.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   └── Assets.xcassets/
└── README.md
```

## Development Workflow

1. **Adding New Files**: Add your Swift files to the `FlightCapture/` directory
2. **Updating Project**: Run `./generate.sh` to regenerate the Xcode project
3. **Building**: Open the generated `.xcodeproj` file in Xcode and build as usual

## Configuration

The project configuration is defined in `project.yml`. Key settings include:

- **Bundle Identifier**: `com.yourcompany.FlightCapture` (update this to your actual bundle ID)
- **Deployment Target**: iOS 15.0
- **Swift Version**: 5.0
- **Xcode Version**: 15.0

## Customization

To customize the project:

1. Edit `project.yml` to modify project settings
2. Run `./generate.sh` to apply changes
3. The generated Xcode project will reflect your changes

## Troubleshooting

- **XcodeGen not found**: Install it via `brew install xcodegen`
- **Project won't build**: Make sure all source files are included in the `sources` section of `project.yml`
- **Missing files**: Run `./generate.sh` to regenerate the project after adding new files

## Version Control

The following files should be committed to version control:
- `project.yml` - Project specification
- `generate.sh` - Generation script
- `FlightCapture/` - Source code
- `README.md` - This file

The following files are generated and should NOT be committed:
- `FlightCapture.xcodeproj/` - Generated Xcode project
- `xcuserdata/` - User-specific Xcode settings

## ⚠️ Workflow Note: XcodeGen & Xcode Project Prompts

When using XcodeGen, you may see a prompt in Xcode saying:

> The file "project.xcworkspace" has been modified by another application.

This happens if you run `./generate.sh` (or `xcodegen generate`) while the project is open in Xcode. **This is normal and safe.**

**Best Practice:**
- You do NOT need to close Xcode every time you regenerate the project.
- When prompted, always choose **"Use Version on Disk"**. This ensures Xcode reloads the latest project structure from your `project.yml`.
- Never manually edit the project structure in Xcode—always use `project.yml` and regenerate.

**Summary:**
- Edit code and `project.yml` as needed.
- Regenerate the project as needed (even with Xcode open).
- If prompted, choose **"Use Version on Disk"**.

This workflow keeps your project in sync and avoids merge conflicts or lost changes.

## 📝 Quick Reference: When to Run `./generate.sh`

| Action                                      | Run `./generate.sh`? |
|---------------------------------------------|:--------------------:|
| Edit existing Swift files                   |         ❌           |
| Accept code improvements from Cursor        |         ❌           |
| Change code logic or UI in existing files   |         ❌           |
| Add new Swift files or resources            |         ✅           |
| Remove files from the project               |         ✅           |
| Rename files (to update in Xcode)           |         ✅           |
| Add/remove targets or change project.yml    |         ✅           |
| Change build settings in project.yml        |         ✅           |
| Edit assets inside existing asset catalogs  |         ❌           |

**Legend:**
- ✅ = Yes, run `./generate.sh` after this change
- ❌ = No, you do not need to regenerate 