#!/usr/bin/env bash
set -e

BASE_URL="https://releases.ubuntu.com"
LATEST=$(curl -s $BASE_URL/ | grep -oP 'href="\K24\.04\.[0-9]+' | sort -V | tail -1)
ISO_URL="$BASE_URL/$LATEST/ubuntu-$LATEST-desktop-amd64.iso"

[[ -d "${HOME}/vbox/images" ]] || mkdir "${HOME}/vbox/images"
wget -O "${HOME}/vbox/images/ubuntu-${LATEST}-desktop-amd64.iso" "${ISO_URL}"
