#!/bin/sh
# For a grown-up. Gives Brick his brain: stores an Anthropic API key in the login Keychain.
#
# It is the same Keychain spot the Claude mod uses, so if that one is already set up, Brick
# works already and there is nothing to do. `security` asks for the key in a hidden field, so
# it never lands in this script, your shell history, or the repo.
#
# Usage: ./set-key.sh          then restart Brick
KEYCHAIN_SERVICE=claude-anthropic

echo "Enter the Anthropic API key (hidden, asked twice):"
security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -T /usr/bin/security -w || exit 1

if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" > /dev/null 2>&1; then
    echo "Stored. Quit Brick from the menu bar and open him again."
else
    echo "Nothing was stored." >&2
    exit 1
fi
