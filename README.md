# Johnny Castaway — native macOS screensaver

A faithful native Swift 6 port of the 1992 Sierra/Dynamix
*Johnny Castaway* screensaver, packaged as a macOS `.saver` bundle.

The original 16-colour pixel art is rendered via Metal with
nearest-neighbour scaling, driven by a clean-room reimplementation of
Sierra's TTM/ADS bytecode interpreter, scene scheduler, walk-graph
pathfinder, and 11-day story arc.

![Johnny Castaway screensaver running behind the macOS lock screen](Docs/screenshot-v1.1.png)

*The screensaver running on macOS 26 Tahoe — Johnny resting under
the palm tree on a moonlit night, with the lock-screen overlay
showing it's a genuine `.saver` bundle.*

> **No Sierra data is included.** This repository contains only the
> reimplemented engine and renderer. To run the screensaver you must
> supply your own `RESOURCE.MAP`, `RESOURCE.001`, and `sound*.wav`
> files — see [Getting the data files](#getting-the-data-files) below.

---

## Status

**v1.3-premium** — feature-complete, highly optimized and stable. Tested on macOS Sonoma, Sequoia, and Tahoe on Apple Silicon. This premium fork introduces CRT retro-rendering, battery optimization, HUD clock overlay, remastered audio, and critical process-lifecycle/audio-leak fixes.

Highlights:

- **Full TTM/ADS Bytecode Interpreter**: Covers every opcode the canonical scripts exercise.
- **Scene Scheduler**: Paces day-of-story advancement, holiday detection (Christmas, Halloween, etc.), and night/day cycles.
- **Walk-Graph Pathfinder**: Efficient A* pathfinding.
- **Persistent Progress**: The 11-day story arc is persisted across screensaver activations.
- **Intro Wipe Transitions**: Cycle transitions on startup.
- **Configure Sheet**: Customize animation speed, force specific story days or holidays, toggle graphics fidelity, and enable/disable premium features.
- **Comprehensive Testing Suite**: 104 engine unit tests and 11 renderer tests.

Premium Enhancements (v1.3-premium):

- **Retro CRT Filter**: Curved tube barrel warping, vignette, scanlines, and vertical phosphor subpixel mask (aperture grille) for authentic analog display.
- **1-Second Smooth Fade-In**: Avoids harsh visual pops when starting.
- **Digital Clock HUD Overlay**: Pixellated retro clock overlay at the bottom right.
- **Smart Battery Saving**: Drops frame updates to ~3 FPS if the MacBook runs on battery under 20% charge.
- **Remastered Audio Option**: Toggle between original 1992 low-fidelity audio and modern remastered high-fidelity WAV files (with seamless fallback).
- **macOS Sonoma/Sequoia/Tahoe Host Defenses**: Correctly registers both `legacyScreenSaver` and `WallpaperLegacyExtension` processes. Runs an invisibility frame watchdog (exits process on 10s of invisibility) and an 8-second emergency exit watchdog to guarantee background processes and audio terminate instantly on dismissal.


---

## Installation

### Pre-packaged Installation

We provide two pre-compiled packages on the [Releases](https://github.com/giattijunior/johnny-castaway-macos-screensaver/releases) page:

- **`JohnnyScreenSaver-embedded.zip` (Recommended - Self-contained)**: This version includes all the Sierra game resources (`RESOURCE.MAP`, `RESOURCE.001`, and sound files) pre-embedded inside the bundle. It works immediately out-of-the-box with **zero configuration** or folder setup required.
- **`JohnnyScreenSaver.zip` (Lightweight)**: This contains only the screensaver engine and renderer (requires you to select your own external folder containing the Sierra resources).

#### Steps to install:
1. Download either ZIP file from the [Releases](https://github.com/giattijunior/johnny-castaway-macos-screensaver/releases) page.
2. Unzip the file to extract `JohnnyScreenSaver.saver`.
3. Move `JohnnyScreenSaver.saver` into your user Screen Savers directory: `~/Library/Screen Savers/`.
4. Since the bundle is ad-hoc signed (and not signed with an Apple Developer ID), strip Gatekeeper's quarantine flag so macOS allows it to load:

   ```sh
   xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/JohnnyScreenSaver.saver
   ```

5. Open **System Settings → Screen Saver** and select **JohnnyScreenSaver**.
6. (Optional) Click **Screen Saver Options...** to customize premium settings (CRT filter, clock overlay, battery saving, speed, etc.). If you chose the self-contained version, the options folder setup will be bypassed automatically!


### Build from Source

Requires Xcode 16+ (Swift 6 toolchain) on Apple Silicon.

```sh
git clone https://github.com/giattijunior/johnny-castaway-macos-screensaver.git
cd johnny-castaway-macos-screensaver
bash Apps/JohnnyScreenSaver/Scripts/build-saver.sh --install --reload
```

The build script compiles the release target, codesigns the bundle, installs it to `~/Library/Screen Savers/`, and kills any running screensaver extensions so your changes apply immediately.


---

## Getting the data files

The screensaver requires the original `RESOURCE.MAP` and
`RESOURCE.001` from the 1992 Sierra/Dynamix release; sound is
optional. Copy the files into a folder of your choosing, then point
the configure sheet at that folder.

For reference, the canonical files have these md5 hashes:

| File name    | size (bytes) | md5                              |
| ------------ | ------------ | -------------------------------- |
| RESOURCE.MAP |          —   | 374e6d05c5e0acd88fb5af748948c899 |
| RESOURCE.001 |          —   | 8bb6c99e9129806b5089a39d24228a36 |
| sound0.wav   |        10768 | 53695b0df262c2a8772f69b95fd89463 |
| sound1.wav   |        11264 | 35d08fdf2b29fc784cbec78b1fe9a7f2 |
| sound2.wav   |         1536 | f93710cc6f70633393423a8a152a2c85 |
| sound3.wav   |         7680 | 05a08cd60579e3ebcf26d650a185df25 |
| sound4.wav   |         5120 | be4dff1a2a8e0fc612993280df721e0d |
| sound5.wav   |         3072 | 24deaef44c8b5bb84678978564818103 |
| sound6.wav   |        15872 | eb1055b6cf3d6d7361e9a00e8b088036 |
| sound7.wav   |        15360 | cab94bace3ef401238daded2e2acec34 |
| sound8.wav   |         2560 | 39515446ceb703084d446bd3c64bfbb0 |
| sound9.wav   |         3584 | f86d5ce3a43cbe56a8af996427d5c173 |
| sound10.wav  |        20480 | 5b8535f625094aa491bf8e6246342c77 |
| sound12.wav  |         5632 | 8c173a95da644082e573a0a67ee6d6a3 |
| sound14.wav  |        11776 | e064634cfb9125889ce06314ca01a1ea |
| sound15.wav  |         3072 | b3db873332dda51e925533c009352c90 |
| sound16.wav  |         7680 | 2eabfe83958db0cad77a3a9492d65fe7 |
| sound17.wav  |         4608 | 2497d51f0e1da6b000dae82090531008 |
| sound18.wav  |        14336 | 994a5d06f9ff416215f1874bc330e769 |
| sound19.wav  |         3584 | 5e9cb5a08f39cf555c9662d921a0fed7 |
| sound20.wav  |         7680 | 80e7eb0e0c384a51e642e982446fcf1d |
| sound21.wav  |         5120 | 1a3ab0c7cec89d7d1cd620abdd161d91 |
| sound22.wav  |         1536 | a0f4179f4877cf49122cd87ac7908a1e |
| sound23.wav  |         2048 | 52fc04e523af3b28c4c6758cdbcafb84 |
| sound24.wav  |         9728 | 5a6696cda2a07969522ac62db3e66757 |

`sound11.wav` and `sound13.wav` are intentionally absent from the
canonical set; the engine silently skips them.

> **Note on the RESOURCE.MAP / RESOURCE.001 hashes:** the values
> above are empirically verified against a working install of this
> project (and they agree with the Go port's README).

The screensaver will not run without `RESOURCE.MAP` and
`RESOURCE.001`. Sound files are optional. The sound files have been
extracted by the JCOS project and made available at
<https://github.com/nivs1978/Johnny-Castaway-Open-Source/tree/master/JCOS/Resources>.

This repository contains no Sierra data files, takes no position on
where users obtain them, and provides no copies. The data files
remain Sierra/Dynamix intellectual property.

---

## How it works

```
RESOURCE.MAP / RESOURCE.001
        │
        ▼
JohnnyResources       parser: archive, palette, bitmap, TTM/ADS scripts
        │
        ▼
JohnnyEngine          interpreter: TTM threads, ADS scheduler,
                                   scene scheduler, walk graph,
                                   island/holiday state
        │
        ▼
JohnnyMetalRenderer   R8Uint indexed framebuffer + 16-entry palette LUT
                      shader, fractional-scale letterbox to fill the screen
        │
        ▼
JohnnyScreenSaver     ScreenSaverView host, configure sheet,
(.saver bundle)       resource folder onboarding, AVAudioPlayer sink
```

`JohnnyDebugApp` is a SwiftUI host that drives the same engine for
QA — frame scrubber, thread inspector, scene picker, force-date
controls.

---

## Resolution & Scaling Modes

The original Johnny Castaway pixel art is rendered at a native resolution of **640x480 (4:3 aspect ratio)**. Modern widescreen monitors have different aspect ratios (e.g. 16:9, 16:10, 21:9). To handle this elegantly, our Metal renderer offers two scaling modes:

- **Fit (Keep Background)**: Renders the full 640x480 game frame in the center. The remaining screen space is filled with a vertical deep-ocean/crepúsculo gradient background (navy blue to indigo) rendered in real-time.
- **Fill (Fullscreen Cropped)**: Crops the original game scene proportionally to cover 100% of the screen. In a standard 16:9 monitor, this crops approximately 12.5% of the sky and 12.5% of the deep sea, resulting in a seamless fullscreen look without any distortion.

---

## Configure Sheet Options

Open the **Screen Saver Options...** in System Settings to customize the screensaver. All settings are stored in a unified JSON database to prevent multi-process clobbering:

| Option | Key | Default | Description |
| :--- | :--- | :--- | :--- |
| **Resource folder** | `ResourceFolderPath` | (unset) | Folder containing original Sierra resources (automatically bypassed in the self-contained package). |
| **Enable sounds** | `SoundEnabled` | Off | Toggle sound playback (plays on the primary display only). |
| **Use remastered audio** | `UseRemasteredAudio` | Off | Attempts to load high-fidelity custom audio files from the `remastered` subdirectory (with fallback to original audio). |
| **Scaling mode** | `ScalingMode` | Fit | Toggle between **Fit** (letterbox with gradient background) and **Fill** (cropped fullscreen). |
| **Enable retro CRT filter** | `CrtFilterEnabled` | Off | Enables barrel distortion (curved CRT bezel), scanlines, vignette, and an aperture-grille phosphor subpixel mask. |
| **Show retro digital clock** | `ClockOverlayEnabled` | Off | Displays a retro digital clock overlay (`HH:mm:ss`) in the bottom-right corner. |
| **Optimize battery on low charge** | `BatterySavingEnabled` | On | Limits frame updates to ~3 FPS if running on battery power below 20%. |
| **Animation speed** | `AnimationSpeed` | 1.0× | Pacing speed multiplier (0.5×, 1.0×, 1.5×, 2.0×). |
| **Story day** | `ForceStoryDay` | Auto | Overrides and pins the story progression to any day from 1 to 11 (temporary; does not overwrite persistent progress). |
| **Force holiday** | `ForceHoliday` | Off | Overrides calendar date to force holiday triggers (Halloween, Christmas, New Year, St. Patrick's). |
| **Engine fidelity** | `FidelityMode` | Fixed | **Fixed**: Go-port engine corrections. **Raw**: Original C/SDL2 jc_reborn engine behavior. |
| **Show debug overlay** | `ShowDebugOverlay` | Off | Renders a real-time HUD with active threads, opcodes covered, frame rate, and current story day. |


---

## Acknowledgements

Firstly, please let me give credit to **Shawn Bird**, **Jeff Tunnell** and the **Dynamix team** who designed and produced the Johnny Castaway characters and code I've spent so much time watching.

This project stands on a long chain of prior reverse-engineering
work. None of it would have been possible without the people below;
many thanks to all of them.

Direct sources used by this Swift port:

- **`jc_reborn`** — the C/SDL2 port whose canonical TTM/ADS opcode
  interpretations, scene-scheduling logic, and resource-format
  decoding this engine follows. The vast majority of the
  algorithmic decisions in `JohnnyEngine` trace back to this
  project's analysis.
  <https://github.com/jno6809/jc_reborn>
- **`Johnny-Castaway-2026-Public`** — a Go/Raylib port whose
  source-level comments resolved several edge cases in our
  implementation (in particular the `DRAW_SPRITE` slot-index
  semantics that, when corrected, restored the sleep-Z animation,
  the visitor boat, and the walk-behind-the-palm-tree depth
  effect).

`jc_reborn` itself thanks the following people, and so do we — each
layer benefited from the prior:

- **Hans Milling** (aka `nivs1978`), author of the JCOS project —
  the original parsing/decoding of the data-file formats and the
  first understanding of many TTM/ADS instructions.
  <https://github.com/nivs1978/Johnny-Castaway-Open-Source> ·
  <http://nivs.dk/jc/>
- **Alexandre Fontoura** (aka `xesf`), author of the `castaway`
  JavaScript port.
  <https://github.com/xesf/castaway> ·
  <https://castaway.xesf.net/viewer/>
- **The Sierra Chest website** — comprehensive Johnny Castaway
  reference material, screenshots, and video captures used as
  cross-reference during development.
  <http://sierrachest.com/index.php?a=games&id=255&title=johnny-castaway>

And, indirectly via JCOS, thanks to:

- **Jeff Tunnel** — for help getting in contact with the original
  developers.
- **Kevin and Liam Ryan** — assistance with information about the
  resource files.
- **Jaap** — help in finding the format of the resource files.
- **Gregori** — assistance with the Lempel-Ziv decompression.
- **Guido** — author of the xBaK project that led to understanding
  the TTM and ADS commands.

The data files remain Sierra/Dynamix intellectual property; this
project provides no copies and takes no ownership claim over them.

---

## Development

The architecture follows the original plan in phases 0–6 plus visual and audio polish. Tests are split per-package:


- `Packages/JohnnyEngine/Tests/` — engine logic (103 tests)
- `Packages/JohnnyMetalRenderer/Tests/` — letterbox geometry (11 tests)
- `Packages/JohnnyResources/Tests/` — bitmap/archive parsing

Pull requests welcome, but please note this is a hobby project and
review cadence is best-effort.

---

## Known Limitations & Design Choices

- **`STAND.ADS` long ambient cycle**: Some idle scenes form a self-sustaining `IF_LASTPLAYED` chunk graph that the original Sierra cut short via wall-clock pacing pressure we do not reproduce. We bound this with an 8000-tick watchdog (~10 minutes worst case). See commit `f797d0c` for details.
- **Audio Sample Rate**: Sound plays at its native 1992 sample rate, reproducing the original game audio perfectly. The remastered toggle allows using higher quality custom audio files if placed in the `remastered` folder.


---

## Licence

[MIT](LICENSE) for the source code in this repository. The Sierra
data files are not covered and are not redistributed.
