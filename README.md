# Centering Raid Profile

A Warcraft add-on that automatically sets up and centers a Blizzard Raid Profile on a specified point on your screen.

**There are no plans to rebuild this for Dragonflight or for The War Within.**  Blizzard initially included this functionality in 10.0 (Dragonflight Pre-patch), but for entirely unknown reasons, they disabled it in 10.0.2 (Dragonflight Launch).  Since then, I have run into tainting issue after tainting issue, and I don't have enough spare time to figure out further alternatives to implementing this functionality.  Given the state of Blizzard's updated UI, it's likely that this feature cannot exist unless either Blizzard reverts their change they made in 10.0.2 or they address the mountain of tainting issues in the new UI.

This repository is being left up as a historical artifact in case I or others wish to take lessons from this code in working with WoW and Lua.

## Usage

When you first load into the game, a raid profile is created called "Centering Raid Profile", which will have its position automatically centered on screen.  The default position should place the raid frames in between your character model on screen and the extra action button area when you are at maximum zoom.

A number of functions and options are available under the `/crp` console command:

Use `/crp status` to verify the add-on is running.

Use `/crp anchorpoint center|top` to change the anchor point used for centering the raid container. 

Use `/crp anchorx` with a number between 0.15 and 0.85 to change the horizontal position of the anchor point.  For example: `/crp anchorx 0.50`

Use `/crp anchory` with a number between 0.15 and 0.85 to change the vertical position of the anchor point.  For example: `/crp anchory 0.30`

Use `/crp allprofiles on|off` to change whether the add-on centers only the raid container for it's raid profile or for _all_ raid profiles.

Use `/crp debug on|off` to enable/disable debug output.

## Limitations

Note that due to Blizzard's restrictions, the automatic positioning will not occur while you are in combat.  Additionally, this add-on is strictly a hobby project, so I've limited the scope of this positioning to only work with the "Keep Groups Together" option turned on (and the add-on will enforce this setting).

Aside from the limitations above, all other raid profile options are available for you to change.

## Known Issues

While I do support centering horizontal groups, Blizzard's support of horizontal groups in their own raid frames is inconsistent and wonky.  In particular, groups will overflow next to each other even if they have extra room defined within the container space (which you can see by unlocking the raid container).  This is entirely a Blizzard issue and entirely out of my control.  If you notice this overflow behavior, a UI reload (i.e. using the `/reload` console command) should remedy the unnecessary overflow in most situations.
