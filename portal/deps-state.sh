#!/usr/bin/env bash
# Print versions of the packages the patched portal depends on, so the launcher
# can tell when a rebuild is due.
pacman -Q xdg-desktop-portal-hyprland hyprutils hyprlang sdbus-cpp 2>/dev/null
