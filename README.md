# Compass Crew

**See your party on your compass and maps.** Compass Crew puts every group member on the [Wayfinder](https://www.curseforge.com/wow/addons/wayfinder) compass banner, your minimap and your world map, so you always know where your friends are and which way to turn.

Built for **World of Warcraft: Forever**.

## Features

- **Your party on Wayfinder's compass**, as class icons, target markers (star, skull, …) or portraits
- **Members behind you** stay pinned to the compass edges, so you never lose track of anyone
- **Stacking:** members close together combine into one icon with a count, instead of piling on top of each other
- **Distance and ETA** under each icon, matching Wayfinder's own readout and following its settings
- **Steady icons:** positions are smoothed, so icons don't jitter when you walk side by side
- **Members elsewhere** (another continent, or inside a dungeon or raid) show as small icons under the compass, with their zone on hover
- **Minimap and world map** icons in the same style. Hover one for the member's name and distance
- **Dead members** are greyed out, so you can find who needs a resurrection
- Members right next to you are left off the compass, to keep it clear in towns
- Lightweight: per-frame work only touches real group members, and icons only redraw when something changes

## Screenshots

<!-- Replace each placeholder with an image, e.g. ![Compass with party members](screenshots/compass.png) -->

**Party members on the compass**

_Screenshot coming soon._

**A stack of nearby members, with distance and ETA**

_Screenshot coming soon._

**Members elsewhere, under the compass**

_Screenshot coming soon._

**Minimap and world map icons**

_Screenshot coming soon._

**Settings**

_Screenshot coming soon._

## Settings

Open them from **Esc > Options > AddOns > Compass Crew**, or type `/crew`.

**Icons**
- **Icon style:** class icon (default), target marker with class icon fallback, target marker only, or player portrait
- **Icon size:** 10–40 px (default 25, the height of Wayfinder's compass), with a live preview
- **Shrink icons for members farther away** (off by default): full size within 25 yards, half size at 250 yards
- **Show distance and ETA under icons** (off by default). Each line also follows Wayfinder's own *Show distance* and *Show ETA* settings

**Members**
- **Pin members behind you to the compass edges** (on)
- **Stack members who are close together** (on)
- **Hide members right next to you** (on): within 10 yards
- **Show members who are elsewhere** (on)
- **Grey out dead members** (on)
- **Show raid members** (off): everyone in a raid, not just your party

**Maps**
- **Show members on the minimap** (on): members out of range sit on the minimap's edge
- **Show members on the world map** (on)
- **Map icon size:** default 25 px

## Commands

- `/crew` (or `/compasscrew`): open the settings
- `/crew debug`: show what Compass Crew sees for each party member (marker, position, compass placement, stacking). Please include it with bug reports.

## Works with

- **[Wayfinder](https://www.curseforge.com/wow/addons/wayfinder)** (required): Compass Crew adds its icons through Wayfinder's public API and follows its distance and ETA settings.
- **[OpenMap](https://www.curseforge.com/wow/addons/openmap)** (optional): adds a "Compass Crew party icons" switch to OpenMap's menu. On OpenMap's seamless map, the icons show over the zone under the view, like Blizzard's own group dots. OpenMap's own "Party and raid members" dots can be turned off in its menu if you only want Compass Crew's.

## Known limitations

- Group members can't be placed inside dungeons and raids, on the compass or the maps: the game hides other players' positions from addons there. They reappear when you're back outside.
- Members on another continent show in the "elsewhere" row rather than on the compass.
- Portraits only appear once the game has loaded that player's model, so a far-away member's portrait can be blank until you get closer.

## Credits

- Icon inspired by [Wayfinder](https://www.curseforge.com/wow/addons/wayfinder)'s, by Wyomarus (MIT license). Source in `art/`.
- Map pins use [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons)-Pins by Nevcairiel (BSD license), added to `Libs` when the addon is packaged.

## License

MIT. See [LICENSE](LICENSE).
