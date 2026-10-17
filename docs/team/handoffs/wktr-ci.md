# Handoff: wktr-ci (researcher)

State: research note written, not committed (lead commits). Base: main at 227c357.
- Note: `research/notes/2026/10-17-wktr-on-github-actions.md`. Read its §0 first, then §4.

Finding: WebKit's CI bucket serves prebuilt iOS-simulator release builds, including WKTR and `libWebCoreTestSupport`,
per trunk revision, with no auth:
`s3-us-west-2.amazonaws.com/minified-archives.webkit.org/ios-simulator-26-x86_64-arm64-release/<rev>.zip`
(324039@main = 315 MB). They are built with Xcode 26.5 against the iOS 26.5 runtime, which matches GitHub `macos-26`
and the iOS 26.5 runtime on this Mac. GTK and WPE zips exist under `archives.webkit.org/{gtk,wpe}-x86_64-release/`
and need `ghcr.io/igalia/wkdev-sdk:<.wkdev-sdk-version>`.

Conventions followed:
- WebKit citations are `path:line@862f17d`; extra sparse paths were added to that clone via `refs-fetch.mjs --paths`.
- Probes were read-only: S3 HEAD and range GETs, the build.webkit.org API, and the ghcr manifest.
- Helper scripts (zip listing over HTTP range) are in the session scratchpad, not the repo. Re-create them from the
  note if needed: read the central directory from the zip's last 70 KB.

Open items:
- Nothing was run end to end. The first real test is the note's §4 steps 1-3 on this Mac.
- Unverified: webkitpy picking the 27.1 SDK on this Mac; real free disk on the free macOS label; GTK `:hover` after
  scroll.
- Plan and work-graph edits are proposed in the note's last section and not applied (plan-editor's job).
