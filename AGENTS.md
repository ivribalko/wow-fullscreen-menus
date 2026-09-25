# Fullscreen Menus

Fullscreen Menus is designed for playing World of Warcraft Forever on a TV, making menus easier to read from the couch. It enlarges and centers native menus, fits inventory bags to the screen, and places them over a dark fullscreen backdrop while hiding unrelated UI.

Open Character, Player Spells, the map, bags, and other supported menus with the usual shortcuts. Native controller navigation, keyboard shortcuts, mouse controls, and item actions remain available. Closing menus restores the normal game UI.

## Compatibility

- Supports WoW Forever beta 1.60.1 (`16001`).
- **Forever beta:** Controller navigation uses WoW's native gamepad support, including Circle/Back to close inventory. Native navigation, cursor, input buttons, and menu-local hints remain active during fullscreen menus. The top-left gamepad legend fades out while menus are open and returns when they close. L2/R2 uses native bindings to switch supported main tabs and native focus navigation for open panels. Menus without a matching Forever binding remain mouse-accessible and are skipped by trigger navigation. L1/R1 navigation remains native.
- Native keyboard shortcuts and mouse controls work on Forever.
- Fullscreen Menus disables the EnhanceQoL bag module while preserving unrelated settings. If that module has already initialized, a chat message requests a UI reload; the addon never reloads automatically. To return to EnhanceQoL Bags, disable Fullscreen Menus and re-enable its bag module.
- In-game acceptance testing on Forever is pending.

## Installation

Place the `FullscreenMenus` folder in the client's `Interface/AddOns` directory and enable Fullscreen Menus in the AddOns list. Restart the client if a newly installed folder does not appear.

Source and alpha builds include diagnostic captures. Packaged beta and release downloads omit them.

## Using the addon

Open bags, Character, Player Spells, or the map with the usual game shortcuts. Fullscreen Menus retains native content, item actions, equipment previews, statistics, and transaction confirmations.

- **Presentation:** No addon menu labels, tabs, pin controls, or debug buttons are displayed. Open menus with native shortcuts; existing controller routing remains available.
- **Native selectors:** Use native mouse controls and gamepad navigation. Trade has no secondary selectors.
- **Spellbook action bars:** Use the native Bind and Edit Action Bar commands. The spellbook keeps its fullscreen position and scale while the native action-bar editor is open. Native binding, moving, clearing, paging, and Back controls remain available; addon trigger shortcuts resume when the editor closes.
- **Gamepad wheel:** Selecting Character displays Character alone. The accompanying native inventory stays concealed until trigger navigation selects it; R2 remains available to switch to inventory.
- **Inventory and services:** Bank, merchant, mailbox, and player-trade interactions use separate service and inventory views. Switching views preserves the interaction and trade offer. On Forever beta, the visible view follows native gamepad focus, and selecting a view focuses its registered native panel. Each view uses the full available content area. The mailbox retains native inventory focus until inbox loading selects the mail pane.
- **Conversation models:** Gossip, quest, trainer, and merchant interactions display the NPC on the left and your character on the right, in fixed screen-relative positions behind menus. Merchant/inventory switching preserves their placement. Both copies use the same model scale and shared camera distance, preserving relative sizes. Both copies occupy one native model scene with a single camera, field of view, and scale. Body collision bounds place them on the scene’s shared ground plane; render bounds fit their opening angles inside the left and right screen regions. NPC appearances use the native creature-display loader, while the player uses native dressed-unit loading. Rotation keeps the opening zoom fixed and may clip at the edges. Models use current unit appearances, with a randomly chosen NPC gesture whenever interaction prose changes. English text cues rank up to five close matches from 31 expressive animations; explicit narrated actions take priority and unmatched text uses neutral talking or nodding. Chat-only emotes have no model animation. NPC gestures bypass the chance gate and cooldown; the player retains a 35% chance of a contextual gesture and a three-second cooldown. Models return to standing after three seconds; exact world movement or emote synchronization is unavailable. Move the right stick (R3) left or right to rotate the NPC model; its angle persists across conversation pages and resets when the interaction closes or the NPC changes. Rotation keeps the shared zoom fixed; some edge clipping is allowed. Models do not intercept input and hide after the interaction closes. This feature works independently of Voiceover. The addon remembers the last NPC and first greeting for the current UI session. Returning to that greeting or reopening the same NPC keeps both displayed models idle; talking to another NPC resets the memory. Subsequent dialogue keeps its contextual gestures. Unchanged prose and inventory/view switches do not retrigger NPC gestures. Text matching reads visible gossip and quest prose and trainer greeting text when available; service panels without prose do not invent dialogue. While a model loads, only the latest visible text is retained. Other locales use neutral gestures unless their text matches an English cue.
- **Item windows and focus:** Item reading uses fullscreen presentation while inactive menus stay concealed. Returning focus restores fullscreen placement. Stack splitting and transaction confirmations retain native dialog behavior.
- **Closing:** Press Escape, native Circle/Back on Forever beta. Closing ends active bank, merchant, mail, or trade interactions. Merchant, mail, and trade dismissal also closes inventory bags and the backdrop. Closing the last inventory bag during a merchant interaction also closes the merchant.

Open or close native inventory bags with:

```text
/fullscreenmenus
```

The native alias opens the same inventory view:

```text
/fullscreenmenus native
```

## Appearance

The map's native fullscreen mode retains native sizing and positioning while keeping the addon backdrop and UI isolation. Circle/Back closes the fullscreen map through the native map-toggle binding. Returning to the windowed map starts a fresh addon fit and restores native Back behavior.

Fullscreen presentation is suspended during native Edit Mode. Entering Edit Mode restores menu and bag placement and the surrounding UI; menus use fullscreen presentation again when opened after leaving Edit Mode.

Menu layout is measured once when a menu type opens. Content, prompt visibility, panel dimensions, and UI size changes do not trigger refitting while that menu remains open. Switching menu types or closing and reopening allows fresh fitting. Quest lists, quest details, and quest rewards share the opening conversation’s scale and top-left position until the conversation closes. Native repositioning restores the saved placement without refitting.

Native panels and their visible selectors scale proportionally and center in the full UI safe area. Menu and bag enlargement is capped at 1.5×; smaller available areas still reduce the scale to fit. Forever scaling includes visible native gamepad legends below menus, keeping bottom-left prompts inside the safe area. Separate bags fit into a uniformly scaled grid in descending bag ID order, with the backpack last. Combined bags keep their native item arrangement and fit as one panel.

An 80% black backdrop covers the game viewport, while native content stays inside the UI safe area. Menus, the backdrop, and unrelated UI use short fades when opening or closing; tab switches are immediate. Forever closes native menus immediately instead of invoking their close handlers from a fade timer. Closing restores native placement and previously visible UI. Open menus retain their enlarged layout and backdrop when combat starts. All supported native menus and inventory bags retain the fullscreen backdrop in combat. Unprotected frames also receive fullscreen fitting; protected frames retain their native or previously fitted geometry until combat ends. Combat skips hiding unrelated UI and changing world-name/nameplate settings. Protected changes and saved-setting restoration wait until combat ends. On Forever beta, unrelated UI is faded without hiding or reparenting native frames, preserving native gamepad focus callbacks.

Registered native menus are discovered automatically. Opening and interaction callbacks recheck visible menus after native handlers finish, restoring fullscreen presentation if a quest completion or other interaction clears it. Periodic discovery also recovers visible menus missing their presentation. Nested selectors remain part of their parent menu. The loot pickup popup, tutorial bubbles, incidental popups, and forbidden frames are excluded from automatic presentation. Combat presentation skips protected frames.

## Development

See [ARCHITECTURE.md](ARCHITECTURE.md) for the module layout and component interactions, and [CHANGELOG.md](CHANGELOG.md) for release notes.

Forever keeps its settings in its WTF directory. Keep SavedVariables, error captures, temporary files, and generated archives outside tracked source.

Use the native `/reload` command to reload the UI. Reopen menus through their normal shortcuts after reloading.

Alpha builds retain up to 128 bank lifecycle and inventory-routing snapshots in the character's `bankDiagnostics` SavedVariables entry. These record event names, interaction types, and UI state without player or item data. Source and alpha builds also retain up to 32 Fullscreen Menus protected-action blocks in `blockedActions`, including the action name, combat state, menu mode, and Lua stack. Source and alpha builds also retain up to 16 numeric model projection snapshots in `modelProjectionDiagnostics`, including the shared camera, actor bounds and positions, and native projected ground coordinates without unit identities or item data. Source and alpha builds also retain up to 16 model-loading snapshots in `modelLoadingDiagnostics`, recording loader acceptance, actor readiness, measurement, and fit status without unit identities. A UI reload persists these captures. Diagnostic code are enclosed in `--@alpha@` / `--@end-alpha@` packager markers and excluded from packaged beta and release builds. Zipping raw source retains development behavior.

### Validation

After an explicitly requested launch or reload:

- Open and close bags independently and during bank, merchant, and player-trade interactions. Check service/Inventory switching, bank selectors, repair, buyback, money, trade acceptance, and transaction confirmations.
- Check bag fitting at different UI sizes and restoration on close and combat.
- Check Character equipment, preview, statistics, Reputation, Currency, Player Spells, Map, and discovered menus.
- Check mouse and controller navigation, Escape, and Back.
- Verify unrelated UI restores correctly and item-action dialogs remain usable. Inspect persisted error captures and debug logs for Lua errors and blocked actions.

## Releases

CurseForge's repository integration packages pushed tags. [`.pkgmeta`](.pkgmeta) defines the archive layout and changelog; the manifest uses `@project-version@` for tag-based versioning.

- Connect the repository to the CurseForge project and select tag-only packaging. Configure the webhook using the [automatic packaging instructions](https://support.curseforge.com/support/solutions/articles/9000197281). Store its token in the integration settings, never in repository files.
- Update `CHANGELOG.md` before tagging. Use `MAJOR.MINOR.PATCH-beta.NUMBER` for Beta, `MAJOR.MINOR.PATCH` for Release, and tags containing `alpha` for Alpha. Avoid `rc`, which is not a CurseForge prerelease classification.
- Complete in-game acceptance checks on Forever before a Release tag. Keep the manifest interface number aligned with Forever and verify the published file's game-version labels.
- Commit the intended source revision and push its tag only with manual confirmation. CurseForge packages that revision, substitutes the version, processes alpha markers, and submits the archive for publication and moderation.

The archive contains one `FullscreenMenus` folder supporting Forever. Repository documentation, tooling, source artwork, temporary files, and generated archives are excluded. Release notes come from `CHANGELOG.md`, rather than commit messages.

## Maintenance and license

This is an owner-maintained project. External pull requests are not accepted.

The project is licensed under the [MIT License](LICENSE). World of Warcraft and third-party addon names belong to their respective owners. References to game-provided artwork and APIs do not grant rights to those external assets.

## Repository Rules

- Follow the global Codex rules in addition to these repository-specific instructions.
- Enclose all debug logs and diagnostic code, including calls, hooks, timers, state, and cleanup, in `--@alpha@` / `--@end-alpha@` markers. Verify marker usage against [CurseForge's packaging requirements](https://support.curseforge.com/support/solutions/articles/9000197910-repository-keyword-substitutions) so diagnostics run only in source and alpha builds and are commented out in packaged beta and release builds.
- Retain useful alpha-only diagnostics after troubleshooting when needed.
- Always reuse shared spacing constants for layout gaps instead of duplicating literal spacing values.
- Target the installed Forever beta interface version; use native handlers for inventory actions and retain native transaction confirmations.
- Search WoW UI source when needed: https://github.com/Gethe/wow-ui-source
- Keep category and discovery logic independent of rendering, and document each module's purpose.
- Use native item textures, the native player-model preview, and simple shapes; do not add generated artwork.
- Keep runtime data, personal information, and local temporary files out of Git.
- Keep README.md as a relative symlink to AGENTS.md; maintain the component overview in ARCHITECTURE.md.
- Obtain explicit manual confirmation before every commit and every push.
- Do not launch WoW, build applications, or take screenshots without an explicit request or approval.
