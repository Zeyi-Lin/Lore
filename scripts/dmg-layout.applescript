-- Applies the guided Finder layout to a mounted release volume.
-- Usage: osascript scripts/dmg-layout.applescript "Lore 1.2.0"
--
-- The window is 640x546 points: a 520 pt background plus the title bar. Icon
-- positions match the dotted path drawn in scripts/dmg-background.png.
on run argv
    if (count of argv) is not 1 then error "usage: dmg-layout.applescript <volume name>"
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {120, 120, 760, 666}

            set options to the icon view options of container window
            set arrangement of options to not arranged
            set icon size of options to 96
            set text size of options to 12
            set background picture of options to file ".background:background.png"

            set position of item "Lore.app" of container window to {160, 165}
            set position of item "Applications" of container window to {480, 165}

            update without registering applications
            delay 1
            -- Finder only paints an icon-view background after the window is
            -- reopened once; this also writes the layout into .DS_Store.
            close
            delay 1
            open
            delay 1
            set bounds of container window to {120, 120, 760, 666}
            close
        end tell
    end tell
end run
