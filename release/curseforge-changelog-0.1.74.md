# 0.1.74

Local beta layout fix. No public tag or upload.

- Fixed section headings overlapping the active quest and XP lines after introducing the navigator scroll area. The clickable headers were still parented to the original frame while quest rows used scroll-body coordinates.
- Moved each heading and its label as a unit into the scroll body so they share positioning and clipping with their list.
- Reserved measured heading height plus explicit spacing before the first quest row, including wrapped German labels and larger fonts.
- Left-aligned the current-objective caption.
- Added regression checks for heading/row parentage, clipping hierarchy and measured spacing. The parentage test reproduced the defect before the correction.

Reload after updating from 0.1.73. In-game visual confirmation of the corrected layout is pending; the provided screenshot was used without screen/window access.
