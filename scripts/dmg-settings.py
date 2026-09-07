# SPDX-License-Identifier: GPL-2.0-or-later
"""Finder layout only; application contents and signature are preserved by dmgbuild."""
import os
application = defines['app']
appname = os.path.basename(application)
format = 'UDZO'
filesystem = 'HFS+'
files = [application]
symlinks = {'Applications': '/Applications'}
icon = os.path.join(application, 'Contents', 'Resources', 'AppIcon.icns')
background = defines['background']
window_rect = ((160, 100), (720, 558))
icon_locations = {appname: (200, 264), 'Applications': (520, 264)}
icon_size = 104
text_size = 13
label_pos = 'bottom'
arrange_by = None
grid_offset = (0, 0)
scroll_position = (0, 0)
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
default_view = 'icon-view'
hide_extension = [appname]
