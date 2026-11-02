# settings.py — dmgbuild settings for the NetRelish disk image. Read by make-dmg.sh as
#   dmgbuild -s settings.py -D app=<NetRelish.app> -D layout=<layout.json> -D background=<png> NetRelish <out.dmg>
# dmgbuild runs this file as Python with `defines` set from the -D flags.
import json
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
layout = json.load(open(defines["layout"]))  # noqa: F821
app_name = os.path.basename(app)

format = "ULFO"            # lzfse: smaller than zlib, and the OS floor is macOS 27
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: dmgbuild hides one by writing com.apple.FinderInfo onto the bundle,
# which breaks its code signature ("resource fork, Finder information, or similar detritus
# not allowed"; v0.4.2's first run). Finder hides ".app" by default anyway.

# The disk's own icon is the app icon: the mark, never redrawn (manifest §2).
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
# background.png; dmgbuild finds background@2x.png beside it and packs one HiDPI TIFF.
background = defines["background"]  # noqa: F821

# Finder counts the title bar inside the height; without it the footer is cut off.
window_rect = ((200, 140), (layout["width"], layout["height"] + layout["titleBarHeight"]))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = layout["iconSize"]
text_size = layout["textSize"]
icon_locations = {
    app_name: tuple(layout["app"]),
    "Applications": tuple(layout["applications"]),
}
