' Screen — the base every screen extends.
'
' The screen contract (documented in this header, previously source/core/Screen.bs)
' is now a real component, declared once and implemented here with defaults:
'
'   function SetStores(storeHost as object, - binds the data layer to the screen.
'                        scene as object)     Only a NODE crosses a component
'                                           boundary by reference: as a callFunc
'                                           argument, a callFunc return or a
'                                           declared interface field, Roku copies
'                                           an associative array and drops every
'                                           function member, and a bsc class
'                                           instance is exactly that. So a store
'                                           instance can never be handed over, and
'                                           each attempt at it died on device with
'                                           &hf4 "Member function not found in
'                                           BrightScript Component or interface".
'                                           What arrives instead is the StoreHost
'                                           NODE (one reference, the mechanism the
'                                           pairing task already uses through its
'                                           declared taskNode field), and what
'                                           comes back over callFunc is plain data
'                                           only: strings, numbers, booleans, arrays
'                                           and assoc arrays of records. m.stores
'                                           holds that one node under a per-store
'                                           alias, so a call site reads
'                                           m.stores.addons.callFunc("AddonsGetAll")
'                                           and gets data, never a live object.
'                                           A bind that comes up short reports the
'                                           failing hop to the Scene, which paints
'                                           it (see SetStores).
'   function OnEnter(params as object)    - called when the screen is pushed or
'                                           restored; params is invalid when it is
'                                           only being uncovered by a pop.
'   function OnExit()                     - called when the screen is popped.
'   function OnBackPressed() as boolean   - true means the screen swallowed Back
'                                           (e.g. a backdrop or dialog inside it);
'                                           false lets the stack pop the screen —
'                                           the default, so a screen that handles
'                                           no back-press edge just pops.
'   function BlurFocus()                  - drop any inline focus the screen holds
'                                           (chips, secondary lists) so a blurred
'                                           node never eats OK/arrow keys again.
'                                           No-op by default; screens that hold
'                                           secondary focus override it.
'
' Screens that implement a lifecycle function keep their override in their own
' script (and declare it in their own interface, mirroring how every screen
' worked before this base existed); these defaults answer the calls a screen
' never overrides. This file touches nothing but m.stores and platform globals,
' so it resolves from any screen's scope with no cross-file dependencies.

' The store hand-off is the one thing every screen depends on, and every way it
' can fail looks the same from the outside: an empty grid and a "0 add-ons"
' subtitle, with no crash and nothing in the log. That is exactly how two
' shipping bugs hid here, so a bind that comes up short reports the failing hop
' to the Scene, which owns the one painted strip that shows it. An empty reason
' clears this screen's fault.
'
' BrightScript print is that channel, but it is not the only one: the strip is
' also where a fault outlives the screen that produced it. A print line is only
' read by whoever is attached to the console at the time; the strip stays on the
' device, so it is what survives a bug found after the fact. Hence both.
'
' The reason strings name the hop, because the three causes need different
' fixes: no host node reached this screen, the host did not answer, or the store
' answered with nothing.
function SetStores(storeHost as object, scene as object) as void
    ' The data layer's owner arrives as a NODE, which is the one thing Roku passes
    ' between components by reference. What comes back over callFunc is plain
    ' data only. m.stores therefore holds one node under a per-store alias: the
    ' alias names the store being asked, the node is the host that answers, and
    ' no store instance is ever in flight to be copied into a data-only shape.
    m.stores = invalid
    if storeHost <> invalid then
        m.stores = {
            addons: storeHost
            auth: storeHost
            episodes: storeHost
            library: storeHost
            settings: storeHost
            time: storeHost
            watch: storeHost
        }
    end if

    ' Every way this hand-off can fail looks identical from the outside — an
    ' empty grid, a "0 add-ons" subtitle, no crash, nothing in the device log —
    ' and that silence is what hid three shipping bugs. So the bind probes the
    ' whole path end to end (node arrived, host answered, forwarder exists, store
    ' returned data) and names the hop that came up short. A missing or
    ' misspelled forwarder is the failure this design introduces, and it is the
    ' one worth catching here rather than as an empty screen.
    fault = ""
    if m.stores = invalid then
        fault = "store fault: no store host reached this screen"
    else
        installed = m.stores.addons.callFunc("AddonsGetAll")
        if installed = invalid then
            fault = "store fault: the store host did not answer AddonsGetAll"
        else if installed.Count() = 0 and m.stores.auth.callFunc("AuthGetSession") <> "stremio" then
            ' A guest session's GetAll() always returns the two built-in seeds, so
            ' an empty list means the store is live but empty — a data fault, not a
            ' hand-off fault, and worth saying out loud rather than leaving a
            ' bare "0 add-ons" the user cannot interpret.
            '
            ' Deliberately NOT raised for a stremio session. AddonsStore hides the
            ' built-in seeds there (only what the account syncs in counts), so an
            ' empty list is the NORMAL state between launch and the collection
            ' landing, and a screen can bind inside that window. Reporting it
            ' anyway named the wrong subsystem: a stremio relaunch whose
            ' collection sync had failed was reported as "the store is live but
            ' reports no add-ons", which reads as a hand-off fault and sent the
            ' investigation at StoreHost instead of at a request that never
            ' arrived. The sync reports its own outcome now (MainScene.
            ' onAddonSyncResult), so the two cannot be confused again.
            fault = "store fault: the store is live but reports no add-ons"
        end if
    end if

    ' Two nodes, both handed over by the Scene and both passed by reference: the
    ' host to read data through, the Scene to report a failed bind to. The Scene
    ' owns the fault strip because it owns the cross-cutting UI and the palette;
    ' a screen painting its own would need a color literal it deliberately does
    ' not depend on. Each is checked separately — a screen that got the host but
    ' not the Scene can still read data, and should say so rather than go quiet.
    if scene <> invalid then scene.callFunc("ReportStoreFault", fault, fault <> "")
end function

function OnEnter(params as object) as void
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

function BlurFocus() as void
end function