# Building Aquanode Modular on Linux (Raspberry Pi 5, aarch64)

This fork adds a Linux build to Aquanode Modular. It produces:

| Result | What it is |
|---|---|
| `Aquanode Modular` | Standalone app of the instrument (synth) |
| `Aquanode Modular.lv2` | LV2 plugin of the instrument: played with MIDI, a new patch starts as Oscillator → Audio Out |
| `Aquanode Modular FX.lv2` | LV2 plugin of the effect version: processes incoming audio, a new patch starts as Audio In → Audio Out (optional) |

The instrument and the FX version contain the same modules; only the starting patch and the plugin type differ.

Developed for a Raspberry Pi 5 with Raspberry Pi OS / Debian trixie (64-bit). The original project files (`.jucer`) are untouched; the Linux build lives in `CMakeLists.txt` and the scripts described below.

## Quick start

```bash
cd ~/git
git clone --branch pi5_linux https://github.com/maarthome/aquanode-modular.git
cd aquanode-modular
./build_aquanode.sh
```

That installs the prerequisites, downloads JUCE, and builds the standalone app and the instrument LV2. The results are in `dist-linux-aarch64/`.

## Prerequisites

The build scripts install these automatically with `apt` (they ask for the sudo password). To install them by hand instead:

### Build tools

```bash
sudo apt update
sudo apt install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config git ca-certificates
```

| Package | Needed for |
|---|---|
| `build-essential` | GCC/G++ compiler and make (C++17) |
| `cmake` | Build configuration (3.22 or newer) |
| `ninja-build` | The build runner |
| `pkg-config` | Lets JUCE find the libraries below |
| `git`, `ca-certificates` | Downloading JUCE |

### Libraries (development packages)

```bash
sudo apt install -y --no-install-recommends \
    libasound2-dev libjack-jackd2-dev \
    libfreetype-dev libfontconfig1-dev \
    libx11-dev libxext-dev libxrandr-dev libxinerama-dev libxcursor-dev \
    libxcomposite-dev libxrender-dev \
    libgl1-mesa-dev libegl1-mesa-dev
```

| Package | Needed for |
|---|---|
| `libasound2-dev` | ALSA audio and MIDI |
| `libjack-jackd2-dev` | JACK audio (also used through PipeWire's JACK layer) |
| `libfreetype-dev`, `libfontconfig1-dev` | Text rendering and font lookup |
| `libx11-dev`, `libxext-dev`, `libxrandr-dev`, `libxinerama-dev`, `libxcursor-dev`, `libxcomposite-dev`, `libxrender-dev` | The X11 window and its extensions |
| `libgl1-mesa-dev`, `libegl1-mesa-dev` | OpenGL, used by the JUCE OpenGL module |

### JUCE

JUCE 9.0.5 is required and is not part of this repository. The build scripts download it into the folder `JUCE/`. By hand:

```bash
cd ~/git/aquanode-modular
git clone --depth 1 --branch 9.0.5 https://github.com/juce-framework/JUCE.git JUCE
```

The LV2 and VST3 headers come with JUCE, so no `lv2-dev` package is needed.

### Memory

The build is heavy (289 source files, including a full copy of the Vital synth). On a Pi with 4 GB, use `build_aquanode.sh`, which adds a temporary 6 GB swap file for the duration of the build. It needs about 7 GB of free disk space.

## Building

### Instrument only (standalone app + LV2)

```bash
./build_aquanode.sh
```

### Instrument and FX

```bash
./build_aquanode.sh --fx
```

This roughly doubles the build time, because the FX version is compiled separately.

### FX only

There is no separate switch for this. Build with `--fx`; if the instrument was built before, only the FX part is compiled.

### The two build scripts

| Script | What it does |
|---|---|
| `build_aquanode.sh` | Creates a temporary 6 GB swap file, builds with all cores, removes the swap file afterwards. Accepts the same options as `build_pi.sh`. |
| `build_pi.sh` | The build itself, with 2 jobs by default and no swap file. |

Options, for both scripts:

| Option | Effect |
|---|---|
| `--fx` | Also build Aquanode Modular FX (LV2) |
| `--vst3` | Also build VST3 plugins |
| `--install` | Copy the LV2 bundle(s) to `~/.lv2` after building |
| `--clean` | Delete the build folder first (full rebuild) |
| `--no-apt` | Skip checking and installing packages |
| `--jobs N` | Number of parallel compile jobs (`build_pi.sh` only; `build_aquanode.sh` always uses all cores) |

If the build is killed for lack of memory, continue where it stopped with fewer jobs:

```bash
./build_pi.sh --jobs 2
```

### Building by hand with CMake

```bash
cmake -S . -B build-linux-aarch64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DAQ_BUILD_FX=ON
cmake --build build-linux-aarch64 --parallel 4
```

| CMake option | Default | Effect |
|---|---|---|
| `AQ_BUILD_FX` | `OFF` | Also build the FX version |
| `AQ_BUILD_VST3` | `OFF` | Also build VST3 plugins |
| `AQ_HOST_VST3` | `ON` | Include the module that loads external VST3 plugins |
| `AQ_JUCE_DIR` | `./JUCE` | Location of the JUCE checkout |

## Results

Everything is collected in `dist-linux-aarch64/`:

```bash
ls dist-linux-aarch64/
```

### Use the LV2 on the Pi

```bash
mkdir -p ~/.lv2
cp -a dist-linux-aarch64/*.lv2 ~/.lv2/
```

### Copy the LV2 to a Zynthian

```bash
./copy_lv2_to_zynthian.sh
```

This copies to `root@zynthian:/usr/local/lib/lv2/`. For another address:

```bash
./copy_lv2_to_zynthian.sh root@zynthian.local
```

Rescan the LV2 plugins on the Zynthian afterwards.

### Run the standalone app

```bash
"./dist-linux-aarch64/Aquanode Modular"
```

The app opens an X11 window, so it needs a running desktop session (X11, or Wayland with XWayland).

## Running on a machine that did not build it

The app and the plugins load these libraries at run time. On the build machine they are already present. On another aarch64 machine, install them with:

```bash
sudo apt install -y --no-install-recommends \
    libasound2 libjack-jackd2-0 libfreetype6 libfontconfig1 \
    libx11-6 libxext6 libxrandr2 libxinerama1 libxcursor1 libxi6 libxss1
```

The package names are those of Debian; on trixie `libasound2` is provided by `libasound2t64`. The other machine also needs a C/C++ runtime at least as new as the build machine's, so a build made on trixie may not load on an older Debian release.

## Keeping the fork in sync with the original

```bash
git remote add upstream https://github.com/aquanodemusic/aquanode-modular.git
```

```bash
git fetch upstream
git merge upstream/main
```

The first command is needed only once. The source file list is read from `Aquanode_Modular.jucer` at build time, so files added or removed in the original are picked up automatically.
