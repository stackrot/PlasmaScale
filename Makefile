PACKAGE_ID := com.stackrot.plasmascale
VERSION := $(shell python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
ARCHIVE := dist/PlasmaScale-$(VERSION).plasmoid
# Distros keep qmllint in Qt's host bin directory rather than on PATH.
QT_HOST_BINS := $(shell qmake6 -query QT_HOST_BINS 2>/dev/null)
QMLLINT ?= $(or $(wildcard $(QT_HOST_BINS)/qmllint),qmllint)

.PHONY: check package install upgrade uninstall clean

check:
	python3 -m json.tool package/metadata.json >/dev/null
	$(QMLLINT) package/contents/ui/main.qml
	@test -s package/contents/icons/tailscale.svg

package: check
	mkdir -p dist
	rm -f $(ARCHIVE)
	cd package && zip -qr ../$(ARCHIVE) metadata.json contents
	unzip -t $(ARCHIVE)

install: check
	kpackagetool6 --type Plasma/Applet --install package

upgrade: check
	kpackagetool6 --type Plasma/Applet --upgrade package

uninstall:
	kpackagetool6 --type Plasma/Applet --remove $(PACKAGE_ID)

clean:
	rm -rf dist
