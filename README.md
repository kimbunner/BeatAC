# BeatAC

A lightweight **anti-cheat system for Godot Engine games**, with modular detection and runtime protection.

> ⚠️ This project is experimental. Expect bugs.

---

## ✨ Features

- **Time-skew detection** — Detects speedhacking via wall-clock vs engine-time comparison
- **DLL/Module injection scanning** — Identifies unauthorized injected modules with warmup window protection
- **Anti-debug heuristics** — Timing probes, pause-gap detection, OS debugger checks
- **Process scanning** — Detects running cheat tools and suspicious processes
- **Tamper detection** — Verifies script integrity and policy file signatures
- **Command-line scanning** — Blocks suspicious launch arguments
- **Configurable policies** — Editor dock for real-time configuration and policy management
- **Built with Godot GDScript** — Lightweight, portable, extensible

---

## 📦 Requirements

- Godot Engine (4.0+)
- Windows OS (for DLL/module scanning; other platforms partially supported)
- Basic knowledge of Godot and game development

---

## 🚀 Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/kimbunner/BeatAC.git
cd BeatAC
```

### 2. Configure the Policy

- Open the project in Godot
- Find the **Beatrix AntiCheat** dock on the left panel
- Set `beatrix_ac/config_path` to point to your custom config resource (or leave empty for defaults)
- Click "Open policy in Inspector" to edit detection thresholds and enable/disable checks

### 3. Integrate into your game

The anticheat runs as an autoload singleton (`AntiCheat`). Violations can trigger:
- Custom reactions (log, halt, notify server, etc.)
- Rate-limited to prevent spam
- Full session tracking for audit trails

---

## 🔐 Detection Methods

### Time-Skew Guard
- Compares engine-frame time against wall-clock time
- Detects speedhacking (Cheat Engine VEH, time manipulation)
- Warmup period during startup to avoid false positives

### DLL/Module Injection (Windows)
- Snapshots trusted DLLs at startup (with configurable warmup)
- Detects Cheat Engine, Frida, minhook, and other injectors
- Path validation filters pre-launched injections
- Uses PowerShell `Get-Process -Modules` query

### Anti-Debug
- Dual timing probes with ratio thresholds (detects single-step/breakpoints)
- Window focus + frame gap checks (pause detection)
- Optional OS-level debugger attachment flag
- Editor-aware: disables in `--remote-debug` mode for F5 play

### Process Scanner
- Detects running instances of Cheat Engine, trainers, memory editors
- Configurable substring patterns for custom tools

---

## 📁 Project Structure

```
addons/beatrix_anticheat/
├── plugin.gd                  # Main plugin entry point
├── core/
│   ├── anticheat_director.gd  # Core detection engine
│   ├── anticheat_config.gd    # Policy defaults & export groups
│   └── beatrix_obf.gd         # XOR obfuscation helper
├── components/
│   └── input_watch_node.gd    # Input tracking (experimental)
├── editor/
│   ├── beatrix_ac_dock.gd     # Inspector dock UI
│   └── beatrix_ac_dock.tscn   # Dock scene
├── scenes/
│   ├── failsafe.tscn          # Failsafe trigger scene
│   ├── halt.gd / halt.tscn    # Game halt handler
└── ui/
    ├── dev_ac_panel.gd        # In-game developer panel
    └── dev_ac_panel.tscn      # Dev panel UI
```

---

## ⚙️ Configuration

All settings are in `anticheat_config.gd` with `@export` decorators. Edit them in the Inspector or create custom `.tres` policy files:

- **General**: Enabled, check intervals, violation reactions, rate limits
- **Anti-Debug**: Timing thresholds, pause detection, editor relaxation
- **Anti-Tamper**: Script path validation, MD5 verification
- **Command Line**: Banned substrings (cheat, trainer, debug flags)
- **Module Scanning**: Trusted directories, DLL snapshot warmup, suspicious substrings
- **Process Scanning**: Banned process patterns

---

## 🛡️ Recent Improvements

See [CHANGES.md](CHANGES.md) for recent updates including:
- Fixed time-skew detection with editor-aware bypass
- DLL warmup window + path validation against pre-launch injection
- Config auto-creation with proper defaults
- Directory auto-creation for custom config paths
- Deferred UI initialization for editor plugin safety

---

## ⚖️ License

See [LICENSE](LICENSE)
