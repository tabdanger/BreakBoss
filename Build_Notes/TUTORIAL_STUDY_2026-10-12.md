# User tutorial study — 12 October 2026

## Evidence status

The user requested rhythms from these exact four tutorials. As of the first access attempts, neither video playback nor a transcript has been obtained. The YouTube short-link pages expose the four video titles, and public catalog/search indexes attribute these titles to KXVI. BPM, swing value and hit grid remain unverified. Do not label existing factory rhythms as transcriptions of these videos.

| Video and verified title | Direct watch-page result | Indexed ID search | Verified rhythm |
| --- | --- | --- | --- |
| [The ULTIMATE Guide to Making DRUMS](https://youtu.be/sEYE7_QtZAE) | Online fetch throttled | No results | Unavailable |
| [The NEW Ways To Make FIRE Drums in 2026](https://youtu.be/PI_7fcEddUI) | Online fetch throttled | No results | Unavailable |
| [The GENIUS Behind Travis Scott’s Drums](https://youtu.be/OrvVfDgyjXQ) | Online fetch throttled | No results | Unavailable |
| [The GENIUS Behind WondaGurl’s Production](https://youtu.be/LHRHtQmgpOw) | Online fetch throttled | No results | Unavailable |

The connected web tool returned the literal error `Online fetch throttled` for all four YouTube watch pages. Searches used the exact video IDs. Opening the `youtu.be` short links exposed the titles recorded above, but their readable page bodies contain only a Google sign-in iframe and YouTube footer links. The oEmbed endpoint also returned `Online fetch throttled`. A combined command that included a shell network permission request was aborted before executing its download script; it produced no downloaded media or metadata. The managed runtime reports an enforced unrestricted HTTP policy, but that does not guarantee a particular website is reachable.

## Verified metadata and limited secondary evidence

- **The ULTIMATE Guide to Making DRUMS**: the [public tutorial catalog](https://musicproductiontutorials.co.uk/videos/the-ultimate-guide-to-making-drums) attributes the tutorial to KXVI using Logic Pro. Its indexed description discusses trap, R&B, boom bap and international styles, and tags drum programming, ghost notes, swing and syncopation. The catalog lists a runtime of 88:17. This is a broad catalog description, not a transcript or measured rhythm.
- **The NEW Ways To Make FIRE Drums in 2026**: the [KXVI channel index](https://socialdiscovery.app/en/youtube/channel/kxvi) associates this exact title with KXVI and dates it 10 October 2026. It provides no playable media or rhythm detail.
- **The GENIUS Behind Travis Scott’s Drums**: the [ghost-note catalog](https://musicproductiontutorials.co.uk/genres/hip-hop/techniques/ghost-notes) associates this exact title with KXVI, Logic Pro and runtime 27:33. The category supports only a general ghost-note topic, not precise timing.
- **The GENIUS Behind WondaGurl’s Production**: the [swing catalog](https://musicproductiontutorials.co.uk/genres/rb/techniques/swing) attributes this exact title to KXVI, Logic Pro and runtime 32:55. [Equipboard](https://equipboard.com/items/ebony-systems-e1) also lists the video under KXVI. Neither source establishes the demonstrated note grid.

## Access attempt log

All connected web requests used `mcp__codex_apps__search_service_web_run`, with `system2_search_query` and `open`. No interactive browser capable of playing video or submitting transcript-generator forms was available to this study.

| Request | Result | Evidence obtained |
| --- | --- | --- |
| YouTube watch URLs `/watch?v=<each of the four IDs>` | `Online fetch throttled` | None |
| YouTube short links `https://youtu.be/<each ID>` | Readable title, body only sign-in iframe/footer | Exact titles |
| YouTube oEmbed for `sEYE7_QtZAE` | `Online fetch throttled` | None |
| YouTube timed-text API `https://www.youtube.com/api/timedtext?v=sEYE7_QtZAE&lang=en` and corresponding `OrvVfDgyjXQ` URL | `Online fetch throttled` | No captions |
| `https://youtubetranscript.com/?server_vid2=<each ID>` | `not accessible via this tool` | No captions |
| Same transcript endpoint with `&lang=en` for `sEYE7_QtZAE` and `OrvVfDgyjXQ` | `not accessible via this tool` | No captions |
| `https://youtubetranscript.com/` | Loads generic page saying captions are loading | Form only, no target video transcript |
| `https://tactiq.io/tools/youtube-transcript` | Loads generic generator and input form | No target video transcript; connected reader cannot submit the form |
| `https://www.scribetube.com/` | Returned unrelated gambling landing page | No usable tutorial evidence |
| Exact IDs and exact titles with transcript/caption search terms, including Tactiq, Glasp, Scribetube and YouTube-Transcript domain filters | No indexed target transcripts | None |
| `https://glasp.co/youtube/p/the-ultimate-guide-to-making-drums`, `/the-genius-behind-travis-scotts-drums`, `/the-genius-behind-wondagurls-production` | `not accessible via this tool` | None |
| `https://www.youtubesummaries.com/music/sEYE7_QtZAE`, `/music/OrvVfDgyjXQ`, `/music/LHRHtQmgpOw` | `not accessible via this tool` | None |
| `https://pickscribe.com/v/<each ID>` and `https://pickscribe.com/en/v/<each ID>` | `not accessible via this tool`; exact-title site searches empty | No target transcripts. Search did expose a different KXVI Mike Dean tutorial transcript, which was not used as evidence for these four tutorials. |
| Tutorial catalog detail pages for Ultimate and Travis | Empty readable page body on direct open; searchable summary snippets available | Limited metadata/summary above |
| Catalog detail page for WondaGurl | Timeout fetching | No transcript |
| Catalog detail page for newest 2026 drums title | `not accessible via this tool` | None |
| `https://sonixaudio.framer.website/drum-mastery` and `https://kxvi.com/` | `not accessible via this tool` | None |
| Default sandbox shell oEmbed request | `Operation not permitted` | None |
| Two shell requests with additional network permission | Held until aborted; download script did not execute | No downloaded media or metadata |

No login, private endpoint, payment restriction or proxy policy was bypassed. The failure descriptions above do not establish that the video itself is private or lacks captions; they describe this environment’s access results.

## Required follow-up evidence

To reproduce the tutorial rhythms, obtain a playable video/audio excerpt covering the sequencer demonstration, a transcript with the demonstrated BPM/grid, or screenshots of the piano roll with BPM visible. The evidence must show timing and instrument roles; metadata alone cannot establish a drum pattern.

## Implementation status

This note records research only. No Swift source or pattern data is changed by this study. Until source evidence becomes available, the requested tutorial-specific rhythms remain pending.
