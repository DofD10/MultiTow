# Changelog – Multi-Vehicle Towing (before: Multi-Vehicle Road Train)

```
========================================================================
              _____   ___  __        __ ___  _   _   ____
             |_   _| / _ \ \ \      / /|_ _|| \ | | / ___|
               | |  | | | | \ \ /\ / /  | | |  \| || |  _
               | |  | |_| |  \ V  V /   | | | |\  || |_| |
               |_|   \___/    \_/\_/   |___||_| \_| \____|

                       M U L T I - V E H I C L E

    ______        ______        ______        ____  _______
   |      |      |      |      |      |      |    ||   |   \__
   |______|-o-o-o|______|-o-o-o|______|-o-o-o|____||___|______|
    (o)  (o)      (o)  (o)      (o)  (o)      (o)        (o)

                           C H A N G E L O G
========================================================================
```

All notable changes to this mod are listed here, newest first.
Version numbers follow the Java part (`MultiTowCore.jar`), which prints its version to the console on start.

Each version lists its changes in these sections (only the ones that apply):

```
+---------------+----------------------------------+
| [+] ADDED     | new features                     |
| [~] CHANGED   | changes to existing behaviour    |
| [!] FIXED     | bug fixes                        |
| [-] REMOVED   | removed features or files        |
+---------------+----------------------------------+
```

New changes go under **Unreleased** until the next version number is assigned.

## [Unreleased]

_Nothing yet._

## [0.16.2] – 2026-11-07 – Chains in Host games (test option)

### [+] ADDED
- **Debug option "Host games: start ZombieBuddy on the hosted server" (off by default, experimental):** for games started with Host, the game starts its own background server, but without ZombieBuddy - so that server had no Java part and chains were off for everybody. With this option the background server also starts with ZombieBuddy, and trains of 3 or more vehicles work in Host games too. The server loads only Java mods you already allowed permanently (it cannot ask, so new or changed JARs are skipped). The option is read from the saved settings when you click Host, so it also works if the options screen was never opened. Find it in Options > DO Utilities > Multi-Vehicle Towing > Show debug options.

## [0.16.1] – 2026-11-07 – Fix: Java part loaded, but basic mode

### [~] CHANGED
- **The Java part now pauses when Multi-Vehicle Towing is not enabled in the loaded save game.** Every save game has its own mod list. If the mod was on in the main menu but not in the save, the Java part kept changing the game's towing although the menus and items of the mod were missing. Now it checks the loaded mod list and stays out of the way; the game tows as usual. The console shows "Java part paused" (and "active again" when you go back to a save with the mod).

### [!] FIXED
- **Wrong version on the DO Utilities page:** the mod still reported itself as 0.15.0, so DO Utilities said "Multi-Vehicle Towing was updated, please restart" although the right version was installed. The mod now reads its version from its own mod.info.
- **Java part running, but the mod stayed in basic mode:** when the game loads the mods only after its start (for example with an empty mod list at start and the mods switched on in the main menu), ZombieBuddy loaded MultiTowCore.jar but the game's Lua never learned its functions until the next restart, so the mod said "Java part not loaded - basic mode". The Java part now registers its Lua functions itself in this case.
- When ZombieBuddy did not offer the function `getJavaModStatus`, the log showed "Object tried to call nil in pcall" (javaRestartNeeded) up to three times at start. The mod now checks first whether ZombieBuddy offers that function. Nothing else changes.

## [0.16.0] – 2026-11-05 – 3D chain

### [+] ADDED
- **3D chain between the vehicles** (Java part, version 0.16.0): a chain is now drawn as a real 3D model (short pieces of 2 links, one after another along the real length of the chain from hitch to hitch, sagging when slack - the links keep their size) instead of a flat picture. Tow bars stay a picture. Needs "3D ground items" in the game options; otherwise (or if the model cannot be drawn) the picture is used as before. Option "Show chains" turns it on and off. Files: `media/models_X/WorldItems/MultiTow_LinkSegment.glb`, `media/textures/WorldItems/MultiTow_LinkSegment.png`, display-only item `Base.MultiTowLinkSegment`.
- **New 3D model for the Heavy Chain with Hook** (the item used for coupling): a coiled chain with two red hooks, on the ground and in the hands, plus a new inventory icon. Only the look of the game item changes (same item, same name). Files: `media/models_X/WorldItems/MultiTow_TowChain.glb`, `media/textures/WorldItems/MultiTow_TowChain.png`, `media/textures/Item_HeavyChain_Hook.png`, script `media/scripts/MultiTow_models.txt`.
- A copy of this changelog in the `42/` folder (`42/CHANGELOG.md`). DO Utilities (1.1.0 and newer) reads it from there and shows it in its "What's new" window and on its "Changelogs" tab, so the changelog in the game is always up to date with this mod. (The game only lets mods read files from `42/` or `common/`, not from the main folder.)

### [!] FIXED
- Vehicles from other mods that have no hitch of their own (for example the semi-trailers of the W900 mod, which only have a king pin): the hitches Multi-Vehicle Towing adds were placed at the height of the vehicle's centre, which can be very high - a vehicle coupled behind such a trailer was pulled upwards. These hitches are now placed at wheel-hub height. Vehicles that already have a hitch (almost all vehicles of the game) are not changed.

## [0.15.0] – 2026-11-01 – Running towed vehicles help

### [+] ADDED
- **Running towed vehicles help:** a towed vehicle whose engine is running drives along when the towing vehicle accelerates (also in reverse), with a set share of its **own** engine power - a strong truck helps more than a small car. No help while braking or when the speed limit holds the train back.
- New option **Running towed vehicles help (%)** in *Gameplay* (0-100 %, default 50, 0 = off). It can only be changed when the **extra engine power** of the towing vehicle is **Off for cars and for trucks/vans**; otherwise it has no effect. Also as sandbox option `AssistPower` for multiplayer (same rule). Needs ZombieBuddy (red without the Java part).

### [~] CHANGED
- Java part (`MultiTowCore.jar`) rebuilt as **0.15.0** (new function `multiTowSetAssist`). ZombieBuddy asks once more for approval - click **Yes**.

## [0.14.0] – 2026-10-30 – New name Multi-Vehicle Towing, options page moved to its own mod (DO Utilities)

### [+] ADDED
- **Restart hint:** if the mod is switched on in the mod list while the game is running, ZombieBuddy loads the Java part, but the game can only use it after a restart. Before, the mod then looked as if ZombieBuddy was missing (options in red, warning "ZombieBuddy is not active"). Now the options page shows an orange note "Restart needed", the setup assistant shows a page "Please restart the game!" and in game a message asks for a restart. Detected with ZombieBuddy's `getJavaModStatus`.

### [~] CHANGED
- **New name: Multi-Vehicle Towing** (before: Multi-Vehicle Road Train). The mod ID `MultiTowRoadTrain` stays the same, so saved options and save games keep working. In game, "Road Train" became **Multi-Tow** (radial menu "Multi-Tow: Attach ...", train display, messages).
- The setup assistant's welcome text pointed to "Options > Road Train"; it now says "Options > DO Utilities".
- **The shared options page of all DofD mods is now the separate mod "DO Utilities" (`DOUtilities`), which this mod requires** (`require=\DOUtilities` in `mod.info`; on Steam it is a required item, so Steam subscribes it automatically). Changes to the page now only need an update of the hub mod instead of every DofD mod.
- Removed from this mod: the hub copy `DofD_Hub_MultiTow.lua`, the card pictures `DofD_Hub_MultiTow.png` / `DofD_Hub_SpeedLoader.png` and the `UI_DofDHub_*` texts - they are all part of DO Utilities now.
- **Less code here:** header images (`DOHUB_IMAGE:` instead of `MULTITOW_IMAGE:`), the collapsible Debug section and the red "needs ZombieBuddy" marks are now done by DO Utilities (hub file v8); this mod only registers what it wants (`debug = ...`, `marks = ...`).
- The tab in *Options* is now called **DO Utilities** (before: "DO Mods"). The setup assistant's hotkey hint says "Options > DO Utilities".
- Only Lua changed: the Java part (`MultiTowCore.jar`) is untouched and still reports 0.12.6, so ZombieBuddy does not ask for approval again.

### [!] FIXED
- The shared options page together with other mods that also change the mod options page, e.g. **Project A-Life** (now in DO Utilities, hub file v7): if such a mod was loaded before the hub, its page could replace ours and its tab appeared several times.
- Hazard lights: the blinking lights no longer go out for a moment when an NPC dies (e.g. Project A-Life). Only the death of your own character switches them off.

## [0.13.5] – 2026-10-28 – The "DO Mods" page updates itself

### [~] CHANGED
- **The "DO Mods" hub file is now delivered under its own name per mod** (`DofD_Hub_MultiTow.lua` here, `DofD_Hub_SpeedLoader.lua` in the Speed Loader mod). Before, both mods shipped the same file under the same path and the game loaded only ONE copy - the one of the mod that happened to load last, even if it was older. Now every copy runs, and **the newest copy of all installed mods wins**. So a new look or a new mod card only has to be published in one mod; it takes effect as soon as that mod is installed next to the others.
- Mods now register themselves in a shared list (`DofDRegistry`) instead of calling the hub directly, so it does not matter whether the hub or the mod loads first. The hub reports itself in `console.txt` (`[DofDHub] hub file v5 is active`).
- "DO Mods" page: the colour of the mouse-over highlight changed from pink (C4005D) to yellow-green (CFFF04). The text on the "Back" and "Workshop page" buttons turns dark while the mouse is over them (readability).
- Only Lua changed: the Java part (`MultiTowCore.jar`) is untouched and still reports 0.12.6.

## [0.13.0] – 2026-10-27 – Options on the new "DO Mods" page

### [+] ADDED
- New options page **DO Mods** (Options screen): shows one card per mod by DofD, with its preview image. A click on an installed mod opens its options on the same page (with a Back button); a click on a mod you do not have opens its Workshop page. The page code (`DofD_Hub.lua`) is the same file in all mods by DofD.
- Hub images `DofD_Hub_MultiTow.png` and `DofD_Hub_SpeedLoader.png` and the hub texts in the translations (EN, DE).

### [~] CHANGED
- The road train options moved from their own tab "Road Train" to the "DO Mods" page. All options, defaults and saved values are unchanged.
- The setup assistant's hotkey hint now says "Options > DO Mods".
- Only Lua changed: the Java part (`MultiTowCore.jar`) is untouched and still reports 0.12.6.

## [0.12.6] – 2026-10-26 – Fix for errors in the options menu

### [~] CHANGED
- The Java part (`MultiTowCore.jar`) was rebuilt only for the new version number - its behaviour is unchanged. ZombieBuddy asks once more for approval.

### [!] FIXED
- Errors "Tried to call nil" in `MultiTow_Options.lua` every time the options menu was built (main menu and in game). The red marking of the options that need ZombieBuddy assumed that every option has a normal control; the hotkey option (and options changed by other mods such as NeatUI Game Options) do not. The marking now checks each option first and skips what it cannot handle, and one failing option no longer stops the others. The hiding of the Debug section got the same protection.

## [0.12.5] – 2026-10-26 – ZombieBuddy optional, basic mode, warning page

### [~] CHANGED
- **ZombieBuddy is now optional.** The mod no longer requires it (`require=\ZombieBuddy` removed from `mod.info`). Without ZombieBuddy the mod runs in a **basic mode**: the game's normal towing of two vehicles, plus cargo weight, extra fuel use, noise and the train display (without the stress line). The mod's own radial menu entries (chains from the 3rd vehicle, tow bar, hazard lights) are hidden in basic mode, because without the Java part a third vehicle would break the first link and a tow bar would only be a rope. The message on game start now says "basic mode".
- The Java part (`MultiTowCore.jar`) was rebuilt only for the new version number - its behaviour is unchanged. Because the file is new, ZombieBuddy asks once more for approval.

### [+] ADDED
- Options that need ZombieBuddy are written in **red** in Options > Road Train and in the setup assistant when the Java part is missing, with a red hint line at the top of General. Marked: Require hook, chain sounds, visible chains, hazard style and scope, link stress display (option, key, key mode, near display), remarks, speed unit, link wear, automatic hazard lights, the train display lines Stress and Condition, and for cars and trucks: maximum vehicles, extra power, train brake and both speed limits.
- Debug option "Mark options that need ZombieBuddy in red": preview of the red marking even when ZombieBuddy works.
- Setup assistant: if the Java part is not loaded (ZombieBuddy not running, or `MultiTowCore.jar` not allowed), the assistant now starts with a red warning page. It lists in short points what does not work without ZombieBuddy and how to fix it. A crossed-out zombie face (new image `media/ui/MultiTow_NoZombieBuddy.png`) is shown at the top right, and a short looping clip of a road train at the bottom (26 frames in `media/ui/MultiTow_Demo/`, played by the mod because the game cannot show GIF files; they are only loaded when the warning page is shown). The normal pages follow after it.
- New section **Debug** at the very bottom of Options > Road Train. Its first option "Show debug options" reveals the options below it; without it they are hidden:
  - "Show setup assistant on next start" (moved here from General).
  - "Show ZombieBuddy warning in setup assistant": opens the assistant the next time you are in the main menu and shows the warning page even when ZombieBuddy works. It switches itself off after you confirm or skip the assistant.
  The setup assistant skips the Debug section.

## [0.12.1] – 2026-10-25 – First Steam Workshop release

### [~] CHANGED
- New artwork for the three header images (General, Cars, Trucks and vans) in the options menu and the setup assistant.
- Hazard lights now blink at the front and the rear of each vehicle, like real ones. European: orange front and rear. American: red at the rear, orange at the front. Where the rear of one vehicle and the front of the next meet, only one light is used.
- Smaller reach of the blinking lights (red rear and amber front 1 tile in the American style, orange 2 tiles in the European style), so the red rear light no longer shines onto the front and mixes with the amber front blinker.

### [!] FIXED
- Error "Object tried to call nil in extraFuel" (MultiTow_Fuel.lua): the game also updates the fuel of vehicles far away as simplified "virtual" vehicles, which have no couplings. These are now skipped.
- Hazard lights: the red tail/brake lights of towed vehicles did not visibly blink (only the orange light did). The American style now also adds a blinking red light at the rear (like the orange one of the European style), which works independently of how the vehicle model is drawn. The mod also switches the vehicle's own brake light switch in the rhythm, and writes a short check to the console after 5 seconds of blinking (how often the game redraws the vehicle's lights) for troubleshooting.
- After coupling two vehicles, the vehicle you sat in could not be driven (no reaction to WASD). When you take the wheel of the *towed* vehicle while nobody sits in the towing one, the game turns the link around so that your vehicle tows. The mod rejected this as a "loop" (every frame), and the game then ignored your input. Now the link is turned around like in vanilla; chain/tow bar, wear condition and hazard lights move along. In the middle of a longer train this is not possible (a vehicle would get two trailers); there the attempt is ignored quietly instead of filling the log.
- Error every second while hazard lights blink in the European style ("Object tried to call nil", MultiTow_Hazard.lua). The list of vehicles near the player now comes from the Java part, because the game's vehicle list could not be used from Lua (probably changed by an optimisation mod). If the orange light ever fails again, it switches itself off with one message instead of repeating the error.
- Errors on game start ("UnknownFormatConversionException") from the "Cargo weight" choices. A plain "%" in a text confuses the game's text formatting; all texts now write it as "%%" like the game itself, and the cargo choices use translation keys.
- Setup assistant: long option names (e.g. "Require Heavy Chain Hook from the 3rd vehicle on") stuck out of the window on the left. The label column now adapts to the longest name and the window gets wider if needed.

## [0.12.0] – 2026-10-25 – Train display, wear, cargo weight, setup assistant, visible chains, hazard lights

### [+] ADDED
- **Train display**: a small window while you sit in a vehicle that is part of a train (option "Show train display while driving", on by default, personal setting).
  - Shows: number of vehicles (and limit), speed (and speed limit, highlighted when too fast), the most strained link as a green-to-red bar,
    the most worn link, the total weight and the fuel of the towing vehicle with the extra fuel use.
  - Every line can be switched off on its own.
  - Position: free (drag it with the mouse, the position is remembered) or at one of the 4 corners or 4 sides of the screen.
- New options section **Gameplay** with:
  - **Link wear** (Off, Low, Normal, High, Very high; default Normal). Links wear out while driving, much faster under heavy load or hard jerks.
    Chains wear about three times faster than tow bars. At 0 % the link snaps (hook links drop chain and hook, tow bars drop a broken tow bar).
    A tow bar keeps its condition when detached and starts from it when coupled again. Real trailers do not wear.
  - **Cargo weight** (Off, 25 %, 50 %, 75 %, 100 %; default 100 %). That share of everything in trunks, seats and glove boxes adds to the weight of the vehicles in a train and is updated every 2 seconds.
    Off = the game's own calculation, which only updates when a vehicle is loaded.
- Both gameplay options also exist as sandbox options for servers.
- The tow bar now has a condition (0-100 %). A worn tow bar can be repaired: right-click, Repair. Needs a blowtorch and Welding level 2, material: 1 small sheet metal or 2 scrap metal. A broken tow bar stays scrap.
- Lua functions `multiTowLinkStress(vehicle)` and `multiTowSnapLink(vehicle)`.
- **Visible chains and tow bars**: the link between two coupled vehicles is drawn as a chain or a tow bar (option "Show chains and tow bars", General, on by default, personal setting).
  - A loose chain sags, a tight one is straight; a faint shadow lies on the ground below. Darker at night.
  - It is a picture drawn on top of the vehicles (not hidden behind them). Pictures: `media/textures/MultiTow_LinkChain.png` and `MultiTow_LinkBar.png` (128x32, repeat seamlessly), can be replaced.
  - Prepared for a later 3D model: the drawing is split into link geometry (`LinkGeometry`) and an exchangeable drawing style (`LinkStyle`); Lua `multiTowSetLinkStyle(0/1/2)` already accepts 2 = 3D model, which falls back to the picture until a model exists.
- **Hazard lights** for towed vehicles.
  - Switch them on and off in the vehicle radial menu (V) as driver of the towing vehicle (new icons).
  - Option "Switch on hazard lights automatically" (Gameplay, on by default, also a sandbox option): coupling switches them on.
  - Option "Hazard lights style" (General, personal): Off, American (tail and brake lights flash red) or European
    (they flash too, plus a blinking orange light at the rear that tints the ground and the rear; the game has no orange rear lamps).
  - Option "Hazard lights on" (General, personal): last vehicle only or all towed vehicles.
  - Uses the battery of the towing vehicle; the on/off state is stored on the towing vehicle and seen by all players.
- **Setup assistant**: on the first start of the mod, a window in the main menu walks through all options page by page
  (General, Gameplay, Train display, Cars, Trucks and vans) with Back / Next, and saves them on Confirm.
  - Pointing at an option shows its explanation in an info box at the bottom.
  - Options that don't apply right now are greyed out (e.g. the km/h slider when mph is selected).
  - "Skip" keeps the current settings. The assistant does not appear again after Confirm or Skip.
  - New option "Show setup assistant on next start" (General) brings it back once.
  - The pages are built from the options menu itself, so new options appear there automatically.

### [~] CHANGED
- Options menu order: the new Gameplay section comes right after General (also in the server's sandbox options).

### [!] FIXED
- Changing the link stress hotkey in the options menu caused an error ("attempted index of non-table" in MainOptions.lua). The game looks up mod key bindings by their text key but compares it with the translated label; the mod now works around this.

## [0.11.0] – 2026-10-21 – Train brake, tow bar, noise, speed limit, fuel

### [+] ADDED
- **Train brake**: when the towing vehicle brakes, the towed vehicles brake along. New slider "Train brake (%)" for cars and for trucks/vans:
  0 = towed vehicles don't brake (vanilla), 100 = as hard as if someone were braking in each of them. Default: 50.
- **Tow bar** (new item "Tow Bar" with its own icon): a rigid link instead of a chain. It keeps a fixed distance of about 1 m and does not stretch.
  - Can be used for any two vehicles, also for a plain 2-vehicle tow (not for real trailers, they already have a fixed drawbar).
  - New radial menu entries "Attach with tow bar" and "Detach, returns tow bar" with their own icon. The entry only appears when you carry a tow bar.
  - The tow bar is used up when coupling and returned when detaching.
  - Trade-off for the rigid link: if it breaks while driving, it is gone. Only a "Broken Tow Bar" drops, which is scrap metal (can be smelted, nothing else).
  - Recipe "Make Tow Bar": 2x Iron Bar, no requirements. **Placeholder** recipe (`Base.IronRod` does not exist in Build 42.21).
- **Noise**: a moving train makes noise at every link that attracts zombies. Chains are loud (about 20-40 tiles depending on speed), tow bars much quieter (about 8-15 tiles).
  Option "Noise attracts zombies" for cars and for trucks/vans (on by default).
- **Speed limit** for trains with 3 or more vehicles: above it the engine gets no more throttle, well above it the towing vehicle brakes gently.
  - New option "Speed unit" (km/h or mph) in the General section.
  - Each section has a km/h slider (0-150) and an mph slider (0-95); only the slider of the selected unit can be changed. 0 = no limit (default).
- **Extra fuel use** for the towing vehicle from the 3rd vehicle on, for cars and for trucks/vans:
  - Mode Off (default), Even (the percentage is added once per additional vehicle) or Exponential (grows faster with every additional vehicle).
  - Slider "Extra fuel per vehicle (%)", default 20. Example with 4 towed vehicles: Even = 1.6x, Exponential = 1.73x.
- All new settings also exist as sandbox options for multiplayer servers.
- Lua functions `multiTowConfigureTrain(brakeCar%, brakeTruck%, speedCarKmh, speedTruckKmh)` and `multiTowIsBarLink(vehicle)`.

### [~] CHANGED
- The link stress band of a tow bar shows how far the bar is pushed or pulled away from its length, not rope stretch.
- Coupling with an item (hook or tow bar) uses one shared routine for singleplayer and the server. The vehicle remembers which item was used, so the right item comes back when detaching or drops when the link snaps.
- Message "%1 returned" now names the returned item (hook or tow bar).

## [0.10.5] – 2026-10-21

### [+] ADDED
- Signing of the Java part for ZombieBuddy is prepared (signing key and script). The signature file is not shipped yet: ZombieBuddy 2.3.4 cannot read the author key from the Steam profile ("platform encoding not initialized"), so a signed JAR would be blocked. It will be shipped once the key is in ZombieBuddy's known authors list.

### [~] CHANGED
- Translation files are now grouped and sorted (separated by blank lines), in the same order for every language:
  options menu, header images, General section, Cars/Trucks sections, in-game messages, remarks with limit, remarks without limit.

## [0.10.0] – 2026-10-21

### [+] ADDED
- Hotkey for the link stress bands (default: K, changeable in the options menu).
- Option "Hotkey mode": **Hold** shows the bands only while the key is held down, **Toggle** switches them on and off with each press (with a short message above the character).
  The hotkey also works when "Show link stress" is off, and is ignored while typing in the chat.
- Option "Show link stress near vehicles" (on by default): when you are on foot within about 2 m of a link, its band is shown automatically, fading in from 2.5 m.
- Option "Remarks when coupling" (on by default): after coupling, the character comments on the train above their head (only visible to you).
  - With a vehicle limit: 4 stages that sound more and more strained the closer the train gets to the limit, up to "no more".
  - Without a limit: 6 stages of increasingly sarcastic remarks about the length of the train (2, 3, 4, 5-6, 7-9, 10+ vehicles).
  - 10 texts per stage in English and German, picked at random, never the same one twice in a row.
- Lua functions `multiTowSetShowLinksNear(on)` and `multiTowSetLinkNearDistance(metres)`.

## [0.9.0] – 2026-10-21

### [+] ADDED
- Option "Show link stress" (General section, off by default, personal setting): every link between two vehicles is drawn as a band. Green = relaxed, yellow = under load, red = close to snapping.
  Stress is the larger of the force on the link (compared to the game's snapping limit) and how far a rope link is stretched.
- Lua functions `multiTowSetShowLinks(on)` and `multiTowSetLinkTuning(ropeStart, ropeRange)` (for fine-tuning the band colours while testing).

### [~] CHANGED
- The three chain sounds (`MultiTowAttach.ogg`, `MultiTowDetach.ogg`, `MultiTowSnap.ogg`) were replaced by silent placeholder files. The final sounds will be added later under the same file names.

## [0.8.0] – 2026-10-20 – Multiplayer foundation (untested)

First groundwork for multiplayer. Singleplayer behaves exactly as in 0.7.1.
Multiplayer requires ZombieBuddy and the mod's Java part on the server **and** on every client.

### [+] ADDED
- The server now decides who is coupled to whom. Clients only send coupling and detaching requests.
- Server-side checks before coupling: distance, free hitches, no loops, maximum train length, Heavy Chain Hook.
- The Heavy Chain Hook is now taken, returned or dropped on the server, so inventories stay in sync.
- Sandbox options for servers (page "Multi-Vehicle Road Train"): enable, hook requirement, and separate maximum length and extra engine power for cars and for trucks/vans. 0 = unlimited.
- Handshake on login: the client asks whether the server runs the Java part. If not, a warning is shown and the Road Train menu entries are hidden.
- Chain sounds and "link snapped" messages are sent by the server to all players nearby.
- New messages for refused couplings (train too long, mod disabled on the server, coupling not possible).
- Lua function `multiTowNetRole()` returns "server", "client" or "sp".

### [~] CHANGED
- The Java part is now active on dedicated servers and multiplayer clients, not only in singleplayer.
- Detaching in multiplayer only separates the one link between two vehicles. Vanilla would split the chain on every client.
- In multiplayer, a single client (the driver's) simulates the physics of the whole chain. Vanilla only hands over the directly coupled vehicle.
- Other players now see every vehicle of a chain move. Vanilla only moved the first towed vehicle.
- In multiplayer the rules come from the server's sandbox options. The personal options menu only controls chain sounds there.
- Shared helper functions moved from `client/MultiTow_Utils.lua` to `shared/MultiTow_Common.lua`, so the server can use them. `client/MultiTow_Utils.lua` is now only a placeholder.
- Translation guide mentions the new `Sandbox.json`.

## [0.7.1] – 2026-10-20

### [~] CHANGED
- New artwork for the three header images in the options menu.
- All console, log and ZombieBuddy texts are now in English. `mod.info` name and description are in English.
- Header images in the options menu are now real image elements, so the options below them are no longer covered.

## [0.7.0] – 2026-10-20

### [+] ADDED
- Chain sounds for coupling, detaching and a separate sound when a link snaps.
- Option "Chain sounds" (on/off) in the General section.
- Header images above the General, Cars and Trucks sections of the options menu.

## [0.6.0] – 2026-10-20

### [+] ADDED
- Separate settings for cars and for trucks/vans: maximum vehicles in a train and extra engine power.
  The type of the towing vehicle (first vehicle of the train) decides which settings apply.
  Trucks are vehicles whose script name contains truck, van, pickup, bus, ambulance, lorry, semi or tractor.
- Options menu split into the sections General, Cars and Trucks and vans.
- Mod icon, poster for the in-game mod list, and a Workshop preview image.

## [0.5.1] – 2026-10-20

### [~] CHANGED
- Java package renamed to the neutral name `multitow` (no personal names in the mod).
- The Java sources are no longer kept inside the mod folder.

## [0.5.0] – 2026-10-20

### [+] ADDED
- The Heavy Chain Hook is now consumed when coupling a third or further vehicle. Detaching gives it back to the player.
- If a hook-paid link snaps while driving, a Heavy Chain and a Large Hook drop on the ground.
- Recipe "Make Heavy Chain Hook" (Heavy Chain + Large Hook) without any requirements.
- Dedicated Road Train entries in the vehicle radial menu with their own icon. Entries show whether a hook is used or returned.

## [0.4.0] – 2026-10-20

### [+] ADDED
- Option "Require Heavy Chain Hook from the 3rd vehicle on" (off by default). The hook only had to be carried at this point.

### [~] CHANGED
- Extra engine power is now one selection: Off, 1.5x, 2x, 2.5x, 3x, Automatic.
- The vanilla coupling menu is hidden for third and further vehicles, so the rules cannot be bypassed.

## [0.3.0] – 2026-10-20

### [+] ADDED
- Options menu in its own tab: enable mod, maximum vehicles in a train (3 to 8 or unlimited), extra engine power.
- Translations in separate files (English and German), plus a guide for translators.

### [!] FIXED
- After loading a save, the link between the first and second vehicle was lost.

## [0.2.0] – 2026-10-20

### [+] ADDED
- Extra engine power for the towing vehicle when it pulls more than one vehicle.

### [!] FIXED
- The middle vehicle of a chain steered erratically.

## [0.1.1] – 2026-10-20

### [!] FIXED
- The Java patches were not applied (they were in a sub-package that ZombieBuddy ignores), so the front link was lost when coupling.

## [0.1.0] – 2026-10-20

### [+] ADDED
- First Java part (`MultiTowCore`, loaded via ZombieBuddy): a vehicle can be towed and tow another vehicle at the same time, so chains of three or more vehicles are possible.

## Before 0.1.0

- Lua-only prototype. Chains of more than two vehicles were not stable, because the game only allows one towing link per vehicle.
