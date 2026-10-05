#!/bin/sh
# Builds Brick.app. Then double-click Brick.app to start him.
cd "$(dirname "$0")" || exit 1
swiftc -O Brick.swift -o Brick.app/Contents/MacOS/Brick
