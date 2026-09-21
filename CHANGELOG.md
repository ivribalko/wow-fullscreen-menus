# Changelog

## Unreleased

- Used native screen projection to fit and place both actors within their visible regions, correcting off-screen placement.
- Placed conversation models in one native scene with a shared camera and collision-bound ground plane; fit opening poses without changing zoom during rotation.

- Used native camera orientation and NPC creature-display loading, with polled actor readiness and bounded projection diagnostics.

- Added horizontal right-stick rotation of the conversation NPC model.

- Added occasional contextual emotes to NPC and player models when interaction menus open or change, with a cooldown and automatic return to standing.

- Added native animated NPC and player copies in fixed left/right positions behind conversation and service menus, independent of Voiceover.

- Routed mailbox and inventory through shared service panes, preserving native focus during inbox loading and controller navigation and clearing the backdrop on mail dismissal.

- Supported native spellbook Bind and Edit Action Bar commands over the fullscreen spellbook, preserving menu placement and scale while leaving editor controls native.

- Displayed only Character after selecting it from the gamepad wheel, preserving native trigger navigation to inventory.

- Restored fullscreen presentation for visible menus after native interaction callbacks, including quest lists returning after quest completion.

- Suspended fullscreen menu presentation during native Edit Mode and restored menu placement and surrounding UI when editing starts.

- Restored saved menu placement after native repositioning, keeping quest rewards centered after Continue without refitting.

- Reserved space for the map's gamepad footers at opening, including hidden focus variants, to keep bottom prompts inside the safe area without later refitting.

- Fitted menus and inventory once per menu type, ignoring content and size changes until switching menus or reopening.

- Avoided redundant scale and anchor updates that disturb native game menu button text during periodic layout refreshes.

- Preserved the opening quest conversation's scale and position when switching between the quest list and quest details.

- Updated the displayed addon name to Fullscreen Menus.

- Kept open menu positioning and scale stable when native gamepad prompts hide for the inventory More menu.

- Renamed the addon, package, saved variables, and slash command to FullscreenMenus.

- Added a small top inset to native menu and inventory bag positioning.

- Targeted WoW Forever exclusively; removed Retail compatibility, ConsolePort integration, unused selector controls, bank metadata, reload reopening, and frame quarantine code.

- Left Forever merchant bag closing to the native merchant handler, avoiding duplicate bag and gamepad focus teardown from addon close events.

- Hid the minimap after its fade to suppress client-rendered markers, restoring its visibility when menus close.

- Hid enemy nameplates, including names and health bars, during UI isolation and restored the original display setting afterward.

- Included the minimap itself in UI isolation so player and resource markers fade with the surrounding UI.

- Removed addon menu headers, labels, and pin controls; centered native content across the full safe area.

- Removed the Show Native / Show Modified and Reload header buttons.

- Mirrored matching end caps for symmetric borders and reduced horizontal padding while retaining a minimum width for short labels.

- Included rounded end-cap widths when sizing short labels such as Pin, preventing overlapping borders.

- Preserved the native artwork proportions of rounded tab and button ends at the padded header height.

- Matched right-side actions to the tab artwork and hover states and increased vertical label padding across header controls.

- Hid overhead NPC, player, and minion names with unrelated UI and restored their original settings on close or logout.

- Removed the transparent-frame delay and chrome teardown when switching between NPC quest lists and quest details.

- Kept NPC quest lists and quest details under the Quests label and preserved the backdrop during their transition.

- Excluded the loot pickup popup from fullscreen menu presentation.

- Auto-hid the top-left gamepad legend during fullscreen menus and restored it on close.

- Capped native menu and inventory bag enlargement at 1.5×.

- Included Forever native gamepad legends in menu scaling bounds so bottom-left hints remain inside the safe area.

- Routed Forever L2/R2 directly to native menu bindings and native focus navigation instead of addon menu-opening callbacks that triggered an interact-target block.

- Audited native UI interactions against Forever 1.60.1.69893 and centralized native handler calls with combat guards.
- Made Forever bag, service, and discovered-menu callbacks observe native visibility without repeating native open/close operations.
- Synchronized service/Inventory presentation with native gamepad focus and fitted combined inventory as one panel.
- Deferred protected fade restoration and controller-binding cleanup until combat ends; kept native closing out of Forever fade timers.

- Disabled automatic menu reopening after developer reload on Forever beta to avoid invoking native gamepad focus updates from an addon timer.

- Kept native frame visibility intact during Forever UI isolation to avoid protected gamepad focus callbacks.

- Changed the developer Reload button to call `C_UI.Reload()` directly while retaining menu restoration.

- Preserved Forever beta native gamepad navigation and input buttons during UI isolation so Circle/Back can close inventory.
- Documented Retail controller support through ConsolePort and Forever beta support through native gamepad navigation.
- Disabled ConsolePort integration and L1/R1 overrides on Forever while retaining L2/R2 main-tab switching and hints.

## 0.1.0-beta.1

- Automatic CurseForge packaging from Git tags.
- Shared support for Retail 12.1.0 and Forever beta 1.60.1.
- Native Character side-tab and bank-page navigation on Forever.
- Refreshed Character and Player Spells availability during navigation.
- Fullscreen native menus, pinnable tabs, fitted inventory, and optional ConsolePort navigation.

In-game acceptance testing on both clients is pending.
