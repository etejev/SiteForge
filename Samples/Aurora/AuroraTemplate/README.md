# Aurora editable sample source

`Aurora.siteforge` and its content-addressed resource sidecar are byte-for-byte
copies of the ordinary project authored through SiteForge's installed public
controls. They are not generated model JSON or a flattened website image.

The shared packaged-template loader validates these bytes, reads resources via
ProjectResourceStore, and establishes a fresh document/project with a clean
history boundary. Canonical content and internal references remain ordinary
editable nodes. The source package, its persisted authoring history, and its
resource sidecar are never modified when a user chooses the sample.

The standalone generated coast provenance is in the adjacent Assets README.
The sample includes demonstration editorial copy and a non-production contact
address. It contains no credentials or private user material.
