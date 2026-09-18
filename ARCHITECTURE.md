# Architecture

## Folder layout

- The root contains the addon manifest, bindings, and six Lua modules loaded in dependency order.
- `Assets` contains the addon icon source PNG and game-ready TGA referenced by the manifest.
- `README.md` links to `AGENTS.md`, which contains usage documentation and repository rules.
- `.pkgmeta` configures the hosted CurseForge packager: addon folder name, manual changelog, and distribution exclusions.
- `CHANGELOG.md` supplies release notes included in the archive; `LICENSE` contains the MIT terms.
- `.local` contains gitignored development checks and temporary files; `dist` contains gitignored release archives.

## Components

- **Layout** defines shared spacing, dimensions, opacity, timing, and the 1.5× maximum enlargement shared by native panels and bag grids.
- **Data** owns SavedVariables initialization, account-wide menu settings, and coalesced refreshes. Native frames own item data, sorting, equipment comparisons, and transaction actions.
- **UI** owns the fullscreen backdrop, invisible safe-area layout frame, proportional panel placement, and fades. No addon header controls or labels are created. Discovery retries share a coalesced backoff scheduler; native panels and bags use the full safe area with the shared enlargement cap.
- **NativeBags** fits separate bag windows to the available area using a uniform scale. It captures and restores anchors and scales and conceals inactive service or inventory surfaces without ending their native sessions. Combined bags retain their native arrangement.
- **Menus** discovers registered native menus and root selectors, manages persistent and session entries, and presents native panels after their handlers run. Merchant selectors use the same discovery contract as generic menus. Nested selectors remain with their owning content.
- **Integration** connects native shortcuts, interaction events, UI isolation, and native gamepad focus. Merchant and trade share dismissal and final-close handling. Bank keeps its native lifecycle adapter.

## State and lifecycle

- Opening a menu captures unrelated visible UI, preserves native panels and item-action dialogs, and presents shared chrome. Isolation fades and content fades retain separate original opacity snapshots.
- Switching menus restores the previous panel geometry and keeps the presentation session alive. Switching service and Inventory tabs changes alpha and mouse input while the native interaction stays open.
- Native panel fitting measures the combined panel and visible native-tab artwork bounds before scaling and centering. On Forever it also measures visible descendant input legends and their prompt containers, including nested footer owners, without invoking any native binding refresh methods. Measured bounds persist for the open panel until its dimensions change or its native layout is restored, preventing temporary prompt visibility changes from shifting or rescaling the menu. Native panel anchor and scale hooks synchronously correct placement with guards against recursive layout. Bag changes schedule coalesced fitting. Periodic discovery catches late registrations and map-addon selectors.
- Closing through Fullscreen Menus dismisses native panels immediately. Native hide callbacks restore presentation immediately; the backdrop fades independently. Final closure clears temporary menu entries, ends interactions, and restores isolated UI.
- Protected restoration waits until combat ends. Unrelated native frames retain their visibility and focus state.
- Reloads do not automatically reopen menus or alter native gamepad focus. Obsolete reopen requests are discarded during SavedVariables initialization.
- Working source and alpha builds include bounded bank lifecycle diagnostics and protected-action captures. Packager alpha markers exclude diagnostics from release builds.

## Native compatibility boundaries

- Bank selector discovery reads the native page-tab pool in bank-type/page order for layout bounds.
- Character discovery reads `ModeTabs.Tabs` frame-name metadata. Character and Player Spells availability is refreshed during navigation. Map discovery includes addon selectors outside Blizzard's managed array.
- Forever uses native gamepad navigation with Fullscreen Menus L2/R2 menu bindings. Main-tab overrides are cleared when the chrome closes; L1/R1 remains native.
- Secondary selectors remain visible in their native panels. Their native input handlers own navigation.
- Forever isolates unrelated UI through alpha only, except for the minimap, which must be hidden to suppress client-rendered markers. Native gamepad focus frames are not hidden or quarantined.
- UI isolation preserves Forever's `SmartNavigation`, `SoftCursor`, and `InputFunctionBindingButton_*` frames so native navigation and Circle/Back bindings stay active.
- UI isolation preserves item dialogs and confirmations. EnhanceQoL bag compatibility retains a narrow adapter for native frame ownership.
- World-space names and enemy nameplates use temporary native display settings during UI isolation. Original values are restored on close and logout, including UI reload; failed restorations remain available for retry. The minimap is captured separately and hidden after its fade so client-rendered player and resource markers disappear; its original visibility and alpha are restored on close.

## Forever source audit

Audited against [Forever 1.60.1.69893](https://github.com/Gethe/wow-ui-source/tree/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069/Interface/AddOns). The mirror contains Blizzard Lua/XML and generated API declarations; it cannot reproduce the client's C++ taint enforcement.

| Surface | Native contract and addon handling |
| --- | --- |
| Bag shortcuts and service events | `ContainerFrame_OnShow` / `ContainerFrame_OnHide` broadcast to the gamepad focus manager. Forever post-hooks adopt resulting visibility without replaying open/close operations. Service presentation preserves the native interaction. |
| Requested menu navigation | `Integration:CallNative` invokes the original native handler through `securecallfunction` on Forever, with a combat guard. A captured L2/R2 failure proves this wrapper alone does not prevent the native interact-target block; trigger navigation therefore uses native bindings directly. It passes native functions directly, not addon closures. It does not authorize restricted functions or repair previously tainted native state. |
| Gamepad focus | `FrameControlsManager:FocusFrame` selects an already registered native panel. A post-hook on `RefreshFocus` schedules presentation updates after native focus settles, including open main menus and service/Inventory panes. Observed focus updates do not call the focus handler again. Fullscreen Menus does not change the native binding stack or replace Circle/Back handlers. |
| Protected interact target | `MainActionBarFrame:UpdateInteractIcons` calls `SetPreferredGamepadInteractTarget`; generated API metadata marks it restricted. Input-binding changes and popup focus can reach this call. Fullscreen Menus never calls, replaces, or suppresses it. Persisted failures in this path establish attribution, but not the original taint source. |
| L2/R2 and L1/R1 | Forever L2/R2 maps directly to native commands from `Bindings_Camelot.xml`, or Blizzard's existing trigger input buttons for adjacent open panels. It never calls the addon's menu-opening callback. Unsupported pinned menus are skipped. Service L2/R2 and all Forever L1/R1 remain native. Cleanup deferred by combat runs at `PLAYER_REGEN_ENABLED`; no bindings are installed on `UIParent`. |
| Character, Player Spells, Map, discovered menus | Addon-requested native opening and closing use the shared call boundary. Discovery callbacks on Forever only change presentation, leaving native panel lifecycle ownership intact. |
| Bank, merchant, trade, inventory actions | Native item handlers and transaction confirmations remain unchanged. Bank page tabs retain native handlers; no purchases or trade acceptance are automated. |
| Layout and isolation | Only anchors, scale, opacity, and inactive-pane mouse state are changed. Combined bags fit as a single panel. Forever isolation does not hide/reparent unrelated native frames; cursor, input-button, scrollbar-hint, and pickup-cursor frames are preserved. The top-left persistent gamepad legend participates in alpha-only isolation and restoration. |
| Closing and combat | Forever native dismissal runs immediately; addon backdrop fades can continue separately. Native actions and protected restoration are deferred or skipped during combat. |
| Reload | Native reloads leave menu reopening to user input. No addon reload helper or automatic reopen timer is installed. |

Relevant source: [gamepad action bars](https://github.com/Gethe/wow-ui-source/blob/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069/Interface/AddOns/Blizzard_GamepadActionBars/MainActionBarFrame.lua), [native focus manager](https://github.com/Gethe/wow-ui-source/blob/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069/Interface/AddOns/Blizzard_GamepadSharedUtility/FrameControlsManager.lua), [container lifecycle](https://github.com/Gethe/wow-ui-source/blob/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua), [restricted target API](https://github.com/Gethe/wow-ui-source/blob/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069/Interface/AddOns/Blizzard_APIDocumentationGenerated/TargetScriptDocumentation.lua), and [reload wrapper](https://github.com/Gethe/wow-ui-source/blob/4d5d706b8e01c5ebe01c8dd9b7a07151d8d37069/Interface/AddOns/Blizzard_SharedXML/InterfaceUtil.lua).

## Distribution

Forever loads the Lua modules through a manifest targeting interface `16001`. The CurseForge repository webhook packages pushed tags into a single ZIP with the Forever manifest. The hosted packager replaces `@project-version@` with the tag, processes alpha markers, and applies `.pkgmeta` exclusions. Release notes come from `CHANGELOG.md`; repository and machine-specific files are excluded.

## Verification boundaries

Static checks and mocked lifecycle checks cover module loading, menu navigation, interaction cleanup, and presentation restoration. Native rendering, secure actions, addon compatibility, and physical controller navigation require in-game acceptance checks.
