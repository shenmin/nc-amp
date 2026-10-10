# Changelog

## 1.7.5 - 2026-10-10

- Resume on launch: nc-amp reopens the last track at the saved position and continues playing automatically (a track that was paused at exit comes back paused at that position). The shuffle order continues where it left off.
- The resume point is saved on exit, on every track or play-state change, every 30 s while playing, and when Windows logs off, shuts down or restarts, so a crash or a killed process still resumes close to where it stopped. Playlist and settings files are written atomically.
- The current track is remembered by its path, so it survives playlist edits; if its file no longer exists, the next track in the order plays. A saved position within 2 s of the end starts the next track. If the playlist changed outside nc-amp, the shuffle order is rebuilt starting with the current track.
- Files passed on the command line or to the running instance still take priority over resuming. With no output device at start-up, playback resumes at the saved position as soon as a device appears.

## 1.7.4 - 2026-10-10

- "Add folders" now uses the modern Windows folder picker and lets you select several folders at once (Ctrl/Shift-click); every selected folder is added recursively, with the same shuffle and auto-play behaviour as before.
- The picker is owned by the player window, follows the system DPI, and Windows remembers the last folder used in it; the old single-folder dialog is used only as a fallback when the modern picker is unavailable.
- Menu items renamed to "Add folders...".

## 1.7.3 - 2026-10-10

- Winamp-style value readout: while the volume or balance slider is dragged (or the volume is changed with the mouse wheel), the LCD title line shows "Volume: 50%" or "Balance: Center" / "Balance: 30% Left" / "Balance: 30% Right"; the song title returns about 1 s after release.
- Volume and balance apply in real time during the drag; the engine ramps gain changes smoothly across each audio buffer, so there are no clicks or zipper noise.

## 1.7.2 - 2026-10-10

- Audio output follows the Windows default device: when a new default appears mid-playback (e.g. Bluetooth earbuds taken out of the case), when the default changes, or when the current endpoint stops or disappears, the device is reopened on the current default and playback continues at the same position. Previously playback could keep going silently to the old endpoint.
- If no output device exists at start-up, nc-amp keeps retrying every 2 s instead of staying silent until restarted; a stuck stream (no audio callbacks for 2 s) is also recovered.
- Detailed audio diagnostics in the `NCAMP_LOG` log: backend, endpoint name and id, all playback endpoints, client and device format / channels / sample rate / period, device notifications, reopen events, and every 3 s the peak level actually written to the device.

## 1.7.1 - 2026-10-10

- Bitrate readout shows the real average kbps as a plain number up to 4 digits (e.g. 953 for FLAC, 1411 for WAV) instead of abbreviating values above 999 as "1M".
- Bitrate is computed over the audio data only: ID3v2 / ID3v1 / APE tags, embedded cover art, FLAC metadata blocks, Ogg header pages and non-audio MP4 atoms no longer inflate it; CBR MP3s show their exact frame-header bitrate (e.g. 320).
- Playlist: a row cut off by the bottom of the list is drawn at its normal position and clipped to the frame; a thin sliver is left empty instead of showing glyph fragments.

## 1.7.0 - 2026-10-10

First open-source release (GPL-3.0-or-later).

- New audio engine `ncaudio` built only from open-source components: miniaudio (output, MP3 / FLAC / WAV), stb_vorbis (Ogg Vorbis), libopus + opusfile + libogg (Opus) and the Windows Media Foundation decoder (M4A / AAC). The proprietary BASS library and its plug-ins are gone.
- Real-time spectrum computed by our own 1024-point Hann-windowed FFT on the output.
- Tag reader rewritten to parse ID3v1 / ID3v2, FLAC and Ogg Vorbis comments and MP4 atoms directly from the file.
- Sample-accurate seeking in Ogg Vorbis and fast seeking in MP3.
- About box shows the licence and the project URL.

## 1.6.6

- Single instance: a second start forwards its files to the running copy (or just brings it to the front).

## 1.6.5

- New app icon: 'nc' in IBM Plex Mono Medium, slimmer bezel, larger LCD face, hand-hinted small sizes.
- Playlist title left-aligned like the main window; removed "Always on top".

## 1.6.4

- Tray menu: no bold default item.

## 1.6.3

- Own tray icon implementation (Shell_NotifyIconW v4, per-monitor-v2 window): native system-font menu and DPI-correct icon.

## 1.6.2

- Removed the minimize button; shade glyph points up / down; all menus are native Windows menus.
- No taskbar button; notification-area icon with playback menu.

## 1.6.1

- Main and playlist title bars share one height at every DPI and size; shaded bars line up exactly.

## 1.6

- Shade mode redesigned: title-bar-high bar with mini transport buttons, time and seek strip; independent playlist shade.
