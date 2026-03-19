#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find ImageArm.app: /Applications, ~/Applications, or Xcode build output
if [ -d "/Applications/ImageArm.app" ]; then
    APP_BUNDLE="/Applications/ImageArm.app"
elif [ -d "$HOME/Applications/ImageArm.app" ]; then
    APP_BUNDLE="$HOME/Applications/ImageArm.app"
elif [ -d "$SCRIPT_DIR/build/Release/ImageArm.app" ]; then
    APP_BUNDLE="$SCRIPT_DIR/build/Release/ImageArm.app"
else
    APP_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData/ImageArm-*/Build/Products/Release/ImageArm.app -maxdepth 0 2>/dev/null | head -1)
    if [ -z "$APP_BUNDLE" ]; then
        APP_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData/ImageArm-*/Build/Products/Debug/ImageArm.app -maxdepth 0 2>/dev/null | head -1)
    fi
fi

SERVICE_NAME="Optimiser avec ImageArm"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_DIR="$SERVICES_DIR/$SERVICE_NAME.workflow"

echo "=== ImageArm - Installation du service Finder ==="

# 1. Check that the app is built
if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
    echo "Erreur: ImageArm.app introuvable. Buildez d'abord le projet dans Xcode."
    exit 1
fi

echo "App: $APP_BUNDLE"

# 2. Install app to /Applications (or ~/Applications as fallback)
if [ ! -d "/Applications/ImageArm.app" ] && [ ! -d "$HOME/Applications/ImageArm.app" ]; then
    echo "Copie dans /Applications..."
    if cp -R "$APP_BUNDLE" /Applications/ImageArm.app 2>/dev/null; then
        APP_BUNDLE="/Applications/ImageArm.app"
        echo "  Installé dans /Applications"
    else
        echo "  /Applications non accessible, utilisation de ~/Applications..."
        mkdir -p "$HOME/Applications"
        cp -R "$APP_BUNDLE" "$HOME/Applications/ImageArm.app"
        APP_BUNDLE="$HOME/Applications/ImageArm.app"
        echo "  Installé dans ~/Applications"
    fi
elif [ -d "/Applications/ImageArm.app" ]; then
    APP_BUNDLE="/Applications/ImageArm.app"
    echo "  Déjà dans /Applications"
else
    APP_BUNDLE="$HOME/Applications/ImageArm.app"
    echo "  Déjà dans ~/Applications"
fi

# 3. Create Automator Quick Action workflow bundle manually
rm -rf "$WORKFLOW_DIR"
mkdir -p "$WORKFLOW_DIR/Contents"

# Generate UUIDs for the workflow
INPUT_UUID=$(uuidgen)
OUTPUT_UUID=$(uuidgen)
ACTION_UUID=$(uuidgen)

# Create document.wflow (Automator workflow plist)
cat > "$WORKFLOW_DIR/Contents/document.wflow" << WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key>
    <string>523</string>
    <key>AMApplicationVersion</key>
    <string>2.10</string>
    <key>AMDocumentVersion</key>
    <string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Optional</key>
                    <false/>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.path</string>
                    </array>
                </dict>
                <key>AMActionVersion</key>
                <string>1.0</string>
                <key>AMApplication</key>
                <array>
                    <string>Automator</string>
                </array>
                <key>AMLargeIconName</key>
                <string>RunShellScript</string>
                <key>AMParameterProperties</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <dict/>
                    <key>inputMethod</key>
                    <dict/>
                    <key>shell</key>
                    <dict/>
                    <key>source</key>
                    <dict/>
                </dict>
                <key>AMProvides</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.path</string>
                    </array>
                </dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>"$APP_BUNDLE/Contents/MacOS/ImageArm" --headless "\$@"</string>
                    <key>CheckedForUserDefaultShell</key>
                    <true/>
                    <key>inputMethod</key>
                    <integer>1</integer>
                    <key>shell</key>
                    <string>/bin/bash</string>
                    <key>source</key>
                    <string></string>
                </dict>
                <key>BundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key>
                <string>1.0</string>
                <key>CanShowSelectedItemsWhenRun</key>
                <false/>
                <key>CanShowWhenRun</key>
                <true/>
                <key>Category</key>
                <array>
                    <string>AMCategoryUtilities</string>
                </array>
                <key>Class Name</key>
                <string>RunShellScriptAction</string>
                <key>InputUUID</key>
                <string>$INPUT_UUID</string>
                <key>Keywords</key>
                <array>
                    <string>Shell</string>
                    <string>Script</string>
                </array>
                <key>OutputUUID</key>
                <string>$OUTPUT_UUID</string>
                <key>UUID</key>
                <string>$ACTION_UUID</string>
                <key>UnlocalizedApplications</key>
                <array>
                    <string>Automator</string>
                </array>
                <key>arguments</key>
                <dict/>
                <key>is498</key>
                <true/>
                <key>isViewVisible</key>
                <true/>
                <key>location</key>
                <string>529.000000:620.000000</string>
                <key>nibPath</key>
                <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
            </dict>
            <key>isViewVisible</key>
            <true/>
        </dict>
    </array>
    <key>connectors</key>
    <dict/>
    <key>workflowMetaData</key>
    <dict>
        <key>workflowTypeIdentifier</key>
        <string>com.apple.Automator.servicesMenu</string>
        <key>serviceInputTypeIdentifier</key>
        <string>com.apple.Automator.fileSystemObject</string>
        <key>serviceApplicationBundleID</key>
        <string>com.apple.finder</string>
    </dict>
</dict>
</plist>
WFLOW

# Create Info.plist to register as Finder Quick Action for image files
cat > "$WORKFLOW_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Optimiser avec ImageArm</string>
    <key>CFBundleIdentifier</key>
    <string>com.imagearm.finder-action</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Optimiser avec ImageArm</string>
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>com.compuserve.gif</string>
                <string>public.svg-image</string>
                <string>org.webmproject.webp</string>
                <string>public.folder</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "  Workflow installé dans: $WORKFLOW_DIR"

# 4. Create CLI wrapper
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/imagearm" << WRAPPER
#!/bin/bash
# ImageArm CLI - optimise images en mode headless
APP="$APP_BUNDLE/Contents/MacOS/ImageArm"
if [ \$# -eq 0 ]; then
    echo "Usage: imagearm <fichier(s)> [dossier(s)]"
    echo "Optimise les images en mode headless (sans fenêtre)."
    exit 0
else
    "\$APP" --headless "\$@"
fi
WRAPPER
chmod +x "$HOME/.local/bin/imagearm"

# 5. Register the service
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo ""
echo "=== Installation terminée ==="
echo ""
echo "Utilisation:"
echo "  Finder : clic droit > Actions rapides > Optimiser avec ImageArm"
echo "  CLI    : imagearm image1.png image2.jpg (ajoutez ~/.local/bin au PATH)"
echo "  Open   : open -a ImageArm fichier.png (mode UI)"
echo ""
echo "Si le service n'apparaît pas dans le Finder:"
echo "  Réglages > Clavier > Raccourcis > Services > activer 'Optimiser avec ImageArm'"
