# Centering Raid Profile

A Warcraft add-on that automatically sets up and centers a Blizzard Raid Profile on screen.  Please note: this is strictly a hobby project, and I will likely not be providing much support, if any.  If you come across this, use at your own risk.

## Usage

When you first load into the game, a raid profile is created called "Centering Raid Profile", which will have its position automatically centered on screen.  The default position should place the raid frames in between your character model on screen and the extra action button area when you are at maximum zoom.

Use `/crp status` to verify the add-on is running.

Use `/crp debug on|off` to enable/disable debug output.

Use `/reload` if the Blizzard Raid Frames break while using this add-on.

## Limitations

Note that due to Blizzard's restrictions, the automatic positioning will not occur while you are in combat.  Additionally, this add-on is strictly a side project, so I've limited the scope of this positioning to only work with the "Keep Groups Together" option turned on (and the add-on will enforce this setting).

Aside from the limitations above, all other raid profile options are available for you to change.

## TO-DO

- [x] Fixing centering, including border.  Possibly use actual frame or group size instead of calculating it yourself in order to automatically account for the borders?
- [x] Support auto-updating based on changes to the raid profile (specifically frame width/height; see thread for suggestions: https://us.forums.blizzard.com/en/wow/t/retail-event-for-detecting-changes-to-raid-profile/977588).
- [x] Basic support for horizontal groups.  (Note: Horizontal groups looks ugly to me in a raid, but someone might want it.  It's also mostly low effort to develop.)
- [ ] Support switching between horizontal and vertical at a specific group size (i.e. if more than 4 groups, switch from horizontal to vertical).
- [ ] Implement saved variables for positioning, and UI to adjust the center anchor.
- [ ] Adjust position based the visibility of groups.
- [ ] Test behavior with pets and main tanks/assists.
- [ ] Add feature to always show double sized debuffs (and buffs if possible).
