# Centering Raid Profile

A Warcraft add-on that automatically sets up and centers a Blizzard Raid Profile on screen.  Please note: this is strictly a hobby project, and I will likely not be providing much support, if any.  If you come across this, use at your own risk.

## Usage

When you first load into the game, a raid profile is created called "Centering Raid Profile", which will have its position automatically centered on screen.  The default position should place the raid frames in between your character model on screen and the extra action button area when you are at maximum zoom.

A number of functions and options are available under the `/crp` console command:

Use `/crp status` to verify the add-on is running.

Use `/crp centerx` with a number between 0.15 and 0.85 to change the horizontal position of the raid container.  For example: `/crp centerx 0.50`

Use `/crp centery` with a number between 0.15 and 0.85 to change the vertical position of the raid container.  For example: `/crp centery 0.30`

Use `/crp debug on|off` to enable/disable debug output.

## Limitations

Note that due to Blizzard's restrictions, the automatic positioning will not occur while you are in combat.  Additionally, this add-on is strictly a hobby project, so I've limited the scope of this positioning to only work with the "Keep Groups Together" option turned on (and the add-on will enforce this setting).

Aside from the limitations above, all other raid profile options are available for you to change.
