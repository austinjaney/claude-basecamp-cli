ICONSET := /tmp/AppIcon.iconset
SOURCE_PNG := Icons/AppIcon_1024x1024.png
ICNS_DEST := claude-basecamp-cli.app/Contents/Resources/applet.icns

.PHONY: sign icon

# Re-sign the app bundle after any change to files inside it.
# Required after editing launch.sh or any other bundle resource —
# an invalid signature prevents macOS from displaying the app icon.
sign: icon
	xattr -cr claude-basecamp-cli.app
	codesign --force --deep --sign - claude-basecamp-cli.app

# Rebuild applet.icns from the source PNG at all required macOS sizes.
# Run this whenever the icon artwork changes, then run make sign.
icon:
	mkdir -p $(ICONSET)
	sips -z 16 16     $(SOURCE_PNG) --out $(ICONSET)/icon_16x16.png
	sips -z 32 32     $(SOURCE_PNG) --out $(ICONSET)/icon_16x16@2x.png
	sips -z 32 32     $(SOURCE_PNG) --out $(ICONSET)/icon_32x32.png
	sips -z 64 64     $(SOURCE_PNG) --out $(ICONSET)/icon_32x32@2x.png
	sips -z 128 128   $(SOURCE_PNG) --out $(ICONSET)/icon_128x128.png
	sips -z 256 256   $(SOURCE_PNG) --out $(ICONSET)/icon_128x128@2x.png
	sips -z 256 256   $(SOURCE_PNG) --out $(ICONSET)/icon_256x256.png
	sips -z 512 512   $(SOURCE_PNG) --out $(ICONSET)/icon_256x256@2x.png
	sips -z 512 512   $(SOURCE_PNG) --out $(ICONSET)/icon_512x512.png
	cp $(SOURCE_PNG) $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICNS_DEST)
	rm -rf $(ICONSET)
