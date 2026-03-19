# ImageArm — Build system outils CLI embarqués
# Compile les 6 outils CLI en arm64 pour macOS 14+
#
# Usage :
#   make check-deps   Vérifie les prérequis
#   make tools        Compile les 6 outils
#   make sign-tools   Signe les binaires (Developer ID + Hardened Runtime)
#   make verify-tools Vérifie les signatures (codesign + spctl)
#   make clean        Supprime les binaires compilés
#   make all          check-deps + tools (défaut)
#   make release      Build Release, signe et archive le .app
#   make dmg          Crée un DMG signé et notarié (nécessite create-dmg)

SHELL := /bin/bash
ROOT  := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))/.." && pwd)
BIN   := $(ROOT)/tools/bin
SCRIPTS := $(ROOT)/tools/scripts

MACOSX_DEPLOYMENT_TARGET := 14.0
export MACOSX_DEPLOYMENT_TARGET

# Identité Developer ID (lue depuis l'env ou détectée via le keychain)
DEVELOPER_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | grep -oE '"[^"]+"' | tr -d '"' || echo "")

TOOLS := $(BIN)/pngquant $(BIN)/oxipng $(BIN)/pngcrush $(BIN)/cjpeg $(BIN)/jpegtran $(BIN)/svgo $(BIN)/cwebp

# Apple ID pour notarisation (lire depuis env)
APPLE_ID ?=
TEAM_ID ?=
NOTARIZE_PASSWORD ?=

# Répertoires de build
BUILD_DIR := $(ROOT)/build
APP_NAME := ImageArm
DMG_NAME := $(APP_NAME).dmg

.PHONY: all check-deps tools sign-tools verify-tools release dmg notarize validate clean

all: check-deps tools

# ── Prérequis ──────────────────────────────────────────────────────────────────

check-deps:
	@echo "🔍 Vérification des prérequis..."
	@MISSING=0; \
	command -v cargo >/dev/null 2>&1 || { echo "  ❌ cargo manquant — installer Rust : brew install rust"; MISSING=1; }; \
	command -v rustc >/dev/null 2>&1 || { echo "  ❌ rustc manquant — installer Rust : brew install rust"; MISSING=1; }; \
	rustup target list --installed 2>/dev/null | grep -q aarch64-apple-darwin || { echo "  ❌ target Rust arm64 manquant : rustup target add aarch64-apple-darwin"; MISSING=1; }; \
	command -v bun >/dev/null 2>&1 || { echo "  ❌ bun manquant — installer Bun : brew install oven-sh/bun/bun"; MISSING=1; }; \
	command -v cmake >/dev/null 2>&1 || { echo "  ❌ cmake manquant : brew install cmake"; MISSING=1; }; \
	command -v pkg-config >/dev/null 2>&1 || { echo "  ⚠️  pkg-config manquant : brew install pkg-config"; }; \
	command -v nasm >/dev/null 2>&1 || echo "  ℹ️  nasm absent (mozjpeg SIMD désactivé) : brew install nasm"; \
	[ "$$MISSING" -eq 0 ] && echo "✅ Prérequis essentiels OK" || { echo ""; echo "❌ Prérequis manquants — corriger avant de lancer 'make tools'"; exit 1; }

# ── Compilation outils ─────────────────────────────────────────────────────────

tools: $(TOOLS)
	@echo ""
	@echo "✅ Tous les outils compilés dans tools/bin/"
	@ls -lh $(BIN)/ | grep -v '^total' | grep -v '.gitkeep'

$(BIN)/pngquant:
	@bash "$(SCRIPTS)/build-pngquant.sh"

$(BIN)/oxipng:
	@bash "$(SCRIPTS)/build-oxipng.sh"

$(BIN)/pngcrush:
	@bash "$(SCRIPTS)/build-pngcrush.sh"

$(BIN)/.mozjpeg-built:
	@bash "$(SCRIPTS)/build-mozjpeg.sh"
	@touch "$@"

$(BIN)/cjpeg: $(BIN)/.mozjpeg-built
$(BIN)/jpegtran: $(BIN)/.mozjpeg-built

$(BIN)/svgo:
	@bash "$(SCRIPTS)/build-svgo.sh"

$(BIN)/cwebp:
	@bash "$(SCRIPTS)/build-cwebp.sh"

# ── Signature code ─────────────────────────────────────────────────────────────

sign-tools:
	@if [ -z "$(DEVELOPER_ID)" ]; then \
		echo "❌ DEVELOPER_ID introuvable. Passer via : make sign-tools DEVELOPER_ID='Developer ID Application: ...'"; \
		exit 1; \
	fi
	@echo "🔏 Signature des binaires avec : $(DEVELOPER_ID)"
	@SIGNED=0; FAILED=0; \
	for BIN_FILE in $(TOOLS); do \
		BIN_NAME=$$(basename "$$BIN_FILE"); \
		if [ -f "$$BIN_FILE" ]; then \
			codesign --force --sign "$(DEVELOPER_ID)" --options runtime --timestamp "$$BIN_FILE" 2>&1 \
				&& codesign --verify --verbose "$$BIN_FILE" 2>&1 \
				&& { echo "  ✅ $$BIN_NAME signé et vérifié"; SIGNED=$$((SIGNED+1)); } \
				|| { echo "  ❌ $$BIN_NAME échec signature ou vérification"; FAILED=$$((FAILED+1)); }; \
		else \
			echo "  ⚠️  $$BIN_NAME absent (non compilé)"; FAILED=$$((FAILED+1)); \
		fi; \
	done; \
	echo ""; \
	echo "📊 Résultat : $$SIGNED signés et vérifiés, $$FAILED échecs"; \
	[ "$$FAILED" -eq 0 ] && echo "✅ Signature complète" || { echo "❌ Échecs détectés"; exit 1; }

verify-tools:
	@echo "🔍 Vérification des signatures..."
	@VERIFIED=0; FAILED=0; \
	for BIN_FILE in $(TOOLS); do \
		BIN_NAME=$$(basename "$$BIN_FILE"); \
		if [ ! -f "$$BIN_FILE" ]; then \
			echo "  ⚠️  $$BIN_NAME absent"; FAILED=$$((FAILED+1)); continue; \
		fi; \
		echo "  ── $$BIN_NAME ──"; \
		if codesign --verify --verbose "$$BIN_FILE" 2>&1; then \
			echo "    codesign: ✅"; \
		else \
			echo "    codesign: ❌ non signé ou signature invalide"; FAILED=$$((FAILED+1)); continue; \
		fi; \
		SPCTL_OUT=$$(spctl --assess --type execute "$$BIN_FILE" 2>&1); \
		if echo "$$SPCTL_OUT" | grep -qi "accepted\|valid"; then \
			echo "    spctl:    ✅ ($$SPCTL_OUT)"; \
		else \
			echo "    spctl:    ⚠️  $$SPCTL_OUT"; \
		fi; \
		FLAGS=$$(codesign --display --verbose "$$BIN_FILE" 2>&1 | grep "flags=" || true); \
		if echo "$$FLAGS" | grep -q "runtime"; then \
			echo "    runtime:  ✅ Hardened Runtime activé"; \
		else \
			echo "    runtime:  ❌ Hardened Runtime ABSENT"; FAILED=$$((FAILED+1)); continue; \
		fi; \
		VERIFIED=$$((VERIFIED+1)); \
	done; \
	echo ""; \
	echo "📊 Résultat : $$VERIFIED vérifiés OK, $$FAILED échecs"; \
	[ "$$FAILED" -eq 0 ] && echo "✅ Vérification complète" || { echo "❌ Échecs détectés"; exit 1; }

# ── Build Release & DMG ────────────────────────────────────────────────────────

release:
	@echo "📦 Build Release..."
	@mkdir -p "$(BUILD_DIR)"
	@xcodebuild -project "$(ROOT)/ImageArm.xcodeproj" \
		-scheme ImageArm \
		-configuration Release \
		-derivedDataPath "$(BUILD_DIR)/DerivedData" \
		CONFIGURATION_BUILD_DIR="$(BUILD_DIR)" \
		CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" \
		CODE_SIGN_STYLE=Manual \
		ENABLE_HARDENED_RUNTIME=YES \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
		2>&1 | tail -5
	@if [ -d "$(BUILD_DIR)/$(APP_NAME).app" ]; then \
		echo "✅ $(APP_NAME).app créé dans $(BUILD_DIR)/"; \
		du -sh "$(BUILD_DIR)/$(APP_NAME).app" | awk '{print "   Taille : " $$1}'; \
	else \
		echo "❌ Build Release échoué"; exit 1; \
	fi

dmg: release
	@echo "💿 Création du DMG..."
	@command -v create-dmg >/dev/null 2>&1 || { echo "❌ create-dmg requis : brew install create-dmg"; exit 1; }
	@rm -f "$(BUILD_DIR)/$(DMG_NAME)"
	@create-dmg \
		--volname "$(APP_NAME)" \
		--volicon "$(BUILD_DIR)/$(APP_NAME).app/Contents/Resources/AppIcon.icns" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "$(APP_NAME).app" 150 190 \
		--app-drop-link 450 190 \
		--hide-extension "$(APP_NAME).app" \
		"$(BUILD_DIR)/$(DMG_NAME)" \
		"$(BUILD_DIR)/$(APP_NAME).app" \
		2>&1 | tail -5 || true
	@if [ -f "$(BUILD_DIR)/$(DMG_NAME)" ]; then \
		echo "✅ DMG créé : $(BUILD_DIR)/$(DMG_NAME)"; \
		du -sh "$(BUILD_DIR)/$(DMG_NAME)" | awk '{print "   Taille : " $$1}'; \
	else \
		echo "❌ Création DMG échouée"; exit 1; \
	fi

KEYCHAIN_PROFILE ?= AC_PASSWORD

notarize:
	@echo "📤 Soumission pour notarisation..."
	@xcrun notarytool submit "$(BUILD_DIR)/$(DMG_NAME)" \
		--keychain-profile "$(KEYCHAIN_PROFILE)" \
		--wait 2>&1 | tail -10
	@echo "📎 Agrafage du ticket de notarisation..."
	@xcrun stapler staple "$(BUILD_DIR)/$(DMG_NAME)" 2>&1
	@echo "✅ DMG notarié et agrafé : $(BUILD_DIR)/$(DMG_NAME)"

# ── Validation pre-release ────────────────────────────────────────────────────

validate: release
	@bash "$(SCRIPTS)/validate-release.sh" "$(BUILD_DIR)/$(APP_NAME).app"

# ── Nettoyage ──────────────────────────────────────────────────────────────────

clean:
	@echo "🧹 Nettoyage de tools/bin/..."
	@rm -f $(TOOLS) $(BIN)/.mozjpeg-built
	@rm -rf "$(BUILD_DIR)"
	@echo "✅ tools/bin/ et build/ nettoyés"
