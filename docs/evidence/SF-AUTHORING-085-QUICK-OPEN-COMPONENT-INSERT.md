# SF-AUTHORING-085 — Direct component insertion from Quick Open

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded `SF-0205-002/003/004/006/008`, `SF-0901-002/004/005/006`, and
`SF-0902-002` apply. The Quick Open definition row now has independent Reveal
in Components and Insert Instance buttons. Insert revalidates the current-
document PageID and active insertion parent, invokes the existing component
registry/placement command, and dismisses only after a revision change. No
instance is created from a search result merely by opening or revealing it.

The existing real-app component search/reveal source journey now includes a
second insertion, canvas object adoption, Undo/Redo, and screenshot. These new
assertions were not run. The previously observed reveal-status accessibility
failure also received a visible, named navigator status; its corrected source
assertion likewise awaits the later integration gate.

Excludes cross-project libraries, new component-definition creation rules,
variant/slot authoring, and release acceptance. `SF-0901/0902` remain Partial.
