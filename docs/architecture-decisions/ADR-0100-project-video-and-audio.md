# ADR-0100 — Project video and audio (local files, poster, native controls, captions)

- Status: Proposed (implemented as an unverified Code Forge candidate; awaiting Codex verification)
- Date: 2026-11-26
- Owners: Product / Engineering
- Decision source: OD-045 (approved by the owner 2026-11-26 1:30 PM EST); OD-100 (open, size limit)
- Requirements: SF-0803-001 … SF-0803-008

## Context

OD-045: video and audio are local assets with a poster image and native
controls, with no transcoding. Authoring never unexpectedly autoplays audio
(SF-0803 acceptance criteria). No new node kind: every `NodeKind` switch
stays unchanged.

## Decision

- `MediaAsset`: `AssetID` identity (never shared with an `ImageAsset`),
  `resourceID`, `displayName`, `originalFilename`, `format`, `byteCount`,
  `contentHash`, and an optional `language` (captions only; a BCP 47 tag such
  as `en` or `pt-BR`, omitted when absent, never null). Exact keys. Formats:
  `mp4` `video/mp4`, `webm` `video/webm`, `mp3` `audio/mpeg`, `m4a`
  `audio/mp4`, `ogg` `audio/ogg`, `wav` `audio/wav`, `vtt` `text/vtt`
  (captions). At most 500 files; ids, resources and hashes are unique; each
  file is at most 16 MB, the existing project-resource limit (OD-100).
- `CanonicalDocument.mediaAssets`: optional key written only when not empty
  (null or `[]` refused), like `fontAssets`. Still document schema 27; a schema
  26 file with media is refused. Copied by template creation, compared by
  `ProjectComparer` ("Video and audio files") and included in
  `sameUncomparedContent`, and restored by snapshot restore (whose files must
  be available).
- One command `setMediaAssets(SetMediaAssetsCommand)`
  (`document.mediaAssets.set`, "Edit Video and Audio", persisted-history
  schema 4) replaces the list. All edits go through `MediaAssetEditing.prepare`,
  which refuses removing a file that an Image still plays. Bytes are installed
  with `installingProjectResource` and stay in the project after removal, so
  Undo is exact. `ProjectImageResourceSnapshot` carries media bytes to builds.
- Placement is the Image's media mode: optional node properties
  `content.media.v1.assetID`, `captionsAssetID`, `loop`, `muted` and
  `autoplay` (`CanonicalMediaPlayback`). The Image's own image is the video's
  poster and what the canvas shows; nothing plays on the canvas. Absent
  settings mean off and are not written; an authored `false` stays authored,
  and the Inspector shows "Off (default)" or "On/Off (set on this Image)".
  Closed key set; the file must be video or audio in this project; captions
  only for video; `autoplay` only for muted video (sound never starts by
  itself). Changes are one grouped undoable edit through
  `MediaPlaybackEditing.prepare`; turning media off keeps the Image.
- Paste into another project drops playback whose file the destination lacks
  (a missing captions file drops only the captions). Media references are
  document-level asset IDs, so the in-project copy paths keep them unchanged.
- Import (`MediaImportWorker`): signatures only, no decoding: ISO BMFF `ftyp`
  (M4A by brand or `.m4a`; QuickTime `qt` brands refused), EBML with DocType
  `webm` (other Matroska refused), `OggS`, `RIFF…WAVE`, `ID3` or an MPEG audio
  frame sync in an `.mp3`, and UTF-8 `WEBVTT` text. A known extension with the
  wrong contents is "damaged"; other types are "unsupported". Original bytes
  are kept. Replace File keeps the entry's identity, name and language, so
  every Image keeps playing it; it is also the recovery for missing bytes.
- Output: `StaticBuildCompiler` copies only files that output Images
  (including collection item pages) play or caption with, as
  `assets/<sha>.<ext>`, after `StaticAssetExportPlanner` checks the signature
  matches the declared type. A missing or damaged file is a blocking
  `media-missing` / `media-invalid` error; a video without captions is a
  `media-video-no-captions` warning. Messages carry no names or text.
- HTML: `<video>` or `<audio>` with `controls preload="metadata"`, optional
  `loop` and `muted`, video `playsinline` and `poster` (the Image's verified
  image path), `autoplay` only for muted video, `aria-label` from the Image's
  alt text, one `<source>` with the type, a default captions `<track>` with
  `srclang`/`label`, and fallback text. No verified file means no source URL
  (`data-siteforge-media-state="missing"`).
- Preview's loopback server returns media types, `Accept-Ranges: bytes`, and
  single-range `206` / `416` replies (Safari needs them to play media).

## Consequences

- No transcoding, streaming, thumbnails from video frames, waveform or canvas
  playback. Files over 16 MB are refused with a plain message (OD-100).
- The Inspector, Video & Audio sheet and every finding expose the same
  capability to keyboard and VoiceOver.

## Review amendment (lane RB, 2026-11-26)

- `MediaPlaybackEditing.prepare` validates the edited document itself: a
  single property change (for example switching a captioned video to audio)
  is not validated by its command availability, so it was accepted by
  `prepare` and only refused later by the session.
- Video & Audio… is also in the Site menu; menu and Assets button share
  `isProjectMediaPresented` (`presentProjectMedia`, `canManageProjectMedia`,
  which stays enabled during an import so its progress stays visible). The
  sheet is presented once at the workspace root.
- Media import, replace, rename/language, removal and Image playback edits
  append `MediaAssetDiagnosticRecord`s (`media-import`, `media-replace`,
  `media-update`, `media-remove`, `media-playback`; SF-0803-002/004/005).
- New-project resources (`ProjectCreationResources.validate`, packaged
  template loading) require every font and media file the document lists,
  not only images (`ProjectCreationResources.storedFiles`).
- The "assets-unused" information finding also counts video, audio and
  captions files that no Image plays.

## Verification amendment (lane V08, 2026-11-26)

- SF-0803-007: playback validation, usage counts, export candidates and
  findings on 100 and 10,000-object documents (half of them Images that play
  a captioned video) stay within safety bounds
  (`testMediaFontAndSVGChecksStayWithinBoundsOnStandardAndLargeFixtures`).
- OD-100 stays open; the 16 MB per-file limit (recommended default) remains
  in force.
- Still not built: UI tests (they need measured entries in
  `scripts/ci-ui-timings.txt` from a run on the Mac).
