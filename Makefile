.PHONY: sign

# Re-sign the app bundle after any change to files inside it.
# Required after editing launch.sh or any other bundle resource —
# an invalid signature prevents macOS from displaying the app icon.
sign:
	xattr -cr claude-basecamp-cli.app
	codesign --force --deep --sign - claude-basecamp-cli.app
