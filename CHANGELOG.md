# Changelog

## 2.0.1 - 2026-10-11

- Fixed: switching the output device could show a "Microsoft Visual C++ Runtime Library - Assertion failed!" dialog (miniaudio.h, `ma_device_get_state(pDevice) == ma_device_state_starting`), and could also leave nc-amp hanging ("Not Responding"). Both had one cause: the audio device was torn down while its audio thread was still stopping on its own after the old device went away. miniaudio's teardown marks the device as gone without waiting for that thread, and the thread could then overwrite the mark with "stopped". It then woke up believing it had been asked to start. With assertion checks built in, this showed the dialog; without them, the teardown waited forever for a thread that had started again. miniaudio's own automatic stream routing could also stop and restart the same device from a system thread while nc-amp was reopening it.
- The device is now always stopped (and its audio thread finished) before it is torn down. Every device open, stop, close and reopen happens on one dedicated audio engine thread, never inside an audio callback or a device notification, and never on the window's thread. The window only passes requests to it, so even a device driver that hangs cannot freeze the player; a watchdog logs a device operation that takes longer than 3 s. The audio callback never waits for the engine: if the decoder is briefly busy (a track change, a seek or a rebuild), it plays a few milliseconds of silence. A device found in the middle of starting or stopping is retried a moment later instead of being torn down.
- miniaudio's automatic stream routing is turned off. nc-amp follows the Windows default output device itself (checked every 0.5 s) together with the device notifications. Auto-pause still happens once for every real device change.
- The engine is built as release code: the C libraries' assertion checks are compiled out, so no runtime "Assertion failed" dialog can appear. The build fails if any assertion call remains. The exe no longer contains build-machine paths.
- Shade mode: the collapsed main window has a volume slider where the seek strip was, with the same size and look. Click, drag or use the mouse wheel to change the volume live (smoothed, no clicks). While it changes, and for about a second after, "Volume: NN%" is shown in an LCD-styled popup like the song-title tooltip, centred under the slider's thumb. The slider stays in step with the main window's volume slider. The song-title tooltip still appears over the empty parts of the bar, but not over the slider. Seeking in shade mode is still possible with the ← / → keys.
- New test modes for NCAMP_TEST_DEVICE: stress (random rapid device changes, removals, failures, rate changes and stalls) and hang (a device driver that blocks for 6 s while stopping).

## 2.0.0 - 2026-10-11

- The audio engine is now linked directly into nc-amp.exe. Earlier versions carried it as ncaudio.dll inside the exe and unpacked it to the temp folder (%TEMP%\nc-amp_engine_...) at every start. nc-amp is now a true single-file program: it writes no DLL anywhere and loads only Windows system libraries. Start-up no longer depends on a writable temp folder, and no stale engine folders are left behind.
- Playback, formats (MP3, FLAC, OGG Vorbis, Opus, M4A/AAC, WAV), the spectrum analyser, seeking, device switching and auto-pause, and resume work exactly as in 1.7.8. The exe is about 36 KB smaller.
- Folders left in the temp folder by earlier versions are not used any more and can be deleted.
- Fixed: the automatic pause on an output device change worked only the first time. Later changes, such as earbuds going back into the case and coming out again, did not pause. Windows reports one Bluetooth connect or disconnect as several device changes. Each one restarted a 10 s "same change" window, even the changes it skipped, so after the first pause later real changes were often taken as part of it. Now every real device change while playing pauses. Only the changes within 3 s of an automatic pause count as the same change (e.g. the earbuds switching from the headset to the stereo profile), and later changes do not extend that window. New test mode for NCAMP_TEST_DEVICE: repeat.

## 1.7.8 - 2026-10-10

- Playback pauses automatically when the output device changes while playing: headphones or earbuds unplugged or turned off, Bluetooth earbuds connecting, or the Windows default output switching to another device. It works like a phone pausing when the headphones come out. nc-amp still switches to the new default device; the song stays at its position, the LCD shows the paused state, and Play continues on the new device. The paused state is saved at once, so a restart stays paused.
- Only a real change of device pauses. Recoveries that bring back the same device keep playing: a stopped or interrupted device, a stuck stream, or the same device returning at another sample rate. So does a device appearing when there was none at start-up, as when auto-resuming at launch with no device yet.
- A burst of changes within 10 s counts as one change (e.g. Bluetooth earbuds switching from the headset to the stereo profile), so there is only one pause. If Play is pressed while the device settles, playback keeps going on the final device. If playback was already paused or stopped, the device switches silently.
- Every automatic pause is logged (NCAMP_LOG) with its reason and the old and new device. New test modes for NCAMP_TEST_DEVICE: change, remove, reroute, stuck and rate.

## 1.7.7 - 2026-10-10

- Fixed: some MP3 files never ended. The time ran on past the duration (e.g. 30:33 on a 3:33 song) while the song repeated from the beginning, and the next track never started. This affected MP3 files without a Xing/Info header. The player asked for the track length several times per screen refresh, and for such files the decoder answers by rescanning the whole file and seeking back. In the last fraction of a second of some files, typically ones ending in an APE/ID3v1 tag, that seek-back fails. The failure left the decoder believing it was at the start, and the next length query moved the stream back there. The length is now measured once when a track is opened (and again when the decoder is rebuilt for a new output device), so the file is no longer rescanned during playback. A seek that fails near the end of a track now ends the track.
- Playback never runs past the known length: the engine stops there and the next track in the shuffle order starts. As a safety net, the player also advances if the position reaches the length and stays there, or if the engine stops on its own. The time readout and the seek bar are clamped to the track length; if the engine cannot tell the length, the duration from the playlist is used.
- The log (NCAMP_LOG) records every track end, with position, length and reason, and every advance, with the next track and its place in the shuffle order.

## 1.7.6 - 2026-10-10

- When the main window is collapsed (shade mode), hovering the empty part of the bar shows the current song title in a tooltip styled like the LCD: pale green LCD background, dark LCD text, a thin soft outline in a slightly darker shade of the same green, and equal padding on all four sides with the text vertically centred. It uses the system UI font, about 1 pt smaller than the standard tooltip size, at the monitor's DPI; padding, border and wrap width (long titles wrap at about 480 px) scale with the DPI. The text follows track changes while it is shown. Buttons, time and seek strip show no tooltip, nothing is shown when no track is loaded, and the expanded window is unchanged.

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
