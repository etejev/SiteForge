# SF-AUTHORING-084 — Direct Image insertion from Quick Open

Status: SOURCE IMPLEMENTED — VERIFICATION DEFERRED.

Bounded `SF-0205-002/003/004/006/008`, `SF-0405-002/004/005/006`,
`SF-0801-002/003`, and `SF-0802-002/004` are exercised in source. A current-
project asset search row has distinct Select in Assets and Insert Image native
buttons. Insert revalidates its stable AssetID and active insertion
availability, then calls the pre-existing Image insertion command. A failed
command restores the previous scene-only asset selection. No image byte, local
path, extra canonical property, or alternate command enters the document.

`testNativeAssetOrganizationSearchFavoriteUndoAndReopenJourney` was extended
with visible Quick Open Insert, one rendered Image, exact Undo/Redo, and a
retained screenshot. The new assertions have not run. Previously observed
075–083 UI results do not verify this slice. The standard asset management
and Image authoring tests remain applicable at the deferred integration gate.

Excludes remote assets, automatic import, cross-project search, and release
acceptance. The normatively broader modules remain Partial.
