extends Resource
## Policy Resource — edit in Godot: Project Settings, Beatrix AntiCheat dock, or open this `.tres` in the Inspector.

@export_group("Paths (customization)")
@export var failsafe_scene_path: String = "res://addons/beatrix_anticheat/scenes/failsafe.tscn"
@export var halt_scene_path: String = "res://addons/beatrix_anticheat/scenes/halt.tscn"
@export var dev_panel_scene_path: String = ""

@export_group("General")
@export var enabled: bool = true
@export var check_interval_frames: int = 30
@export var reaction_on_violation: int = 0
@export var violation_cooldown_sec: float = 0.35
@export var max_violations_per_minute: int = 30
@export var rate_limit_clamps_reaction: bool = true

@export_group("Build / environment")
@export var block_debug_in_export: bool = true
@export var require_release_feature: bool = false
@export var license_baseline_substring: String = ""

@export_group("Anti-debug")
## When true and the process looks launched from the Godot editor (separate game window, `--remote-debug`, etc.),
## timing / pause / OS-debugger heuristics are skipped so F5 play stays usable. Ship release builds are unchanged.
@export var relax_anti_debug_for_editor_launched_run: bool = true
@export var timing_probe_enabled: bool = true
@export var timing_probe_max_usec: int = 750_000
## Second micro-benchmark; large wall-clock gap between back-to-back runs often indicates breakpoints / single-step.
@export var anti_debug_dual_timing_pairs: bool = true
@export var anti_debug_dual_timing_ratio_max: float = 12.0
@export var anti_debug_dual_timing_slow_usec: int = 400_000
## If the main window is focused but _process gaps exceed this (ms), flag (breakpoints pause the game loop).
@export var anti_debug_focus_pause_check: bool = true
@export var anti_debug_focus_pause_max_ms: int = 3500
## Try OS-level debugger attachment flag when the engine exposes it (platform-dependent).
@export var anti_debug_os_attached_check: bool = true

@export_group("Anti-tamper")
## If the singleton script has a `resource_path`, it must contain this substring (empty = skip). Skipped in editor; often empty after export.
@export var tamper_singleton_path_substring: String = "beatrix_anticheat"
## Compare MD5 of the policy file on disk to catch swapped `.tres` (set both; path comes from project setting / loader).
@export var tamper_verify_policy_file_md5: bool = false
@export var tamper_expected_policy_md5: String = ""

@export_group("Command line")
@export var cmdline_scan_enabled: bool = false
@export var banned_cmdline_substrings: PackedStringArray = PackedStringArray([
	"cheat",
	"trainer",
	"debug=yes",
	"--debug-collisions",
])

@export_group("Environment variables")
@export var env_scan_enabled: bool = false
@export var suspicious_env_var_names: PackedStringArray = PackedStringArray([
	"HTTP_PROXY",
	"GODOT_DEBUG",
])

@export_group("Time / speed")
@export var time_sync_check: bool = true
@export var max_tick_skew_ms: float = 400.0
@export var max_negative_delta_frames: int = 3
@export var suspicious_delta_scale: float = 4.0

@export_group("Physics / frame correlation")
@export var physics_desync_check: bool = false
@export var max_physics_process_divisor: int = 3

@export_group("Scene & tree")
@export var scene_sanity_paths: PackedStringArray = PackedStringArray(["AntiCheat"])
@export var max_scene_tree_node_count: int = 0
@export var guard_group_name: String = ""
@export var min_nodes_in_guard_group: int = 0

@export_group("Input")
@export var input_sanity: bool = true
@export var max_actions_per_frame: int = 48
@export var macro_detection_enabled: bool = false
@export var macro_identical_press_threshold: int = 14

@export_group("Process scan (Cheat Engine, debuggers, etc.)")
@export var process_scan_enabled: bool = false
@export var process_scan_interval_sec: float = 50.0
@export var process_use_unix_ps: bool = true
@export var suspicious_process_substrings: PackedStringArray = PackedStringArray([
	"cheatengine",
	"cheatengine-x86_64",
	"cheatengine-i386",
	"cheat engine",
	"ceserver",
	"artmoney",
	"gameconqueror",
	"scanmem",
	"xenos",
	"injector.exe",
	"pinject",
	"reclass",
	"x64dbg",
	"x32dbg",
	"ollydbg",
	"ida64",
	"ida32",
	"windbg",
	"devenv",
	"dnspy",
	"ilspy",
	"processhacker",
	"httpdebugger",
	"fiddler",
	"hollowshunter",
	"systeminformer",
])

@export_group("In-process module / DLL scan (injectors)")
## Detects DLLs mapped into this process (Cheat Engine VEH/Hooks, Frida, etc.). Windows: PowerShell. Linux: /proc/self/maps. macOS: lsof.
@export var injector_module_scan_enabled: bool = false
@export var use_only_trusted_directory: bool = false
@export var trusted_directories: PackedStringArray = PackedStringArray([
	OS.get_executable_path().get_base_dir(),
	"c:/system32/"
])
@export var use_startup_dll_only: bool = false
## Delay trusting the DLL snapshot until this many seconds have passed (mitigates pre-launch injection).
@export var startup_dll_warmup_sec: float = 2.0
var startup_dll = []
var _startup_dll_captured_at_sec: float = -1.0
@export var injector_module_scan_interval_sec: float = 45.0
@export var suspicious_module_substrings: PackedStringArray = PackedStringArray([
	"cheatengine",
	"cheat engine",
	"speedhack",
	"vehdebug",
	"dbk64",
	"dbk32",
	"ce-",
	"\\ce\\",
	"/ce/",
	"frida",
	"frida-gum",
	"easyhook",
	"easyhook32",
	"easyhook64",
	"minhook",
	"scripthook",
	"scripthookv",
	"megadumper",
	"xenos",
	"sharpinject",
	"assemblyinject",
])

@export_group("Integrity (loose files)")
@export var integrity_enabled: bool = false
@export var integrity_paths: PackedStringArray = PackedStringArray()
@export var integrity_expected_md5: PackedStringArray = PackedStringArray()

@export_group("User data file (user://)")
@export var user_data_guard_enabled: bool = false
@export var user_data_relative_path: String = ""
@export var user_data_expected_md5: String = ""
@export var user_data_missing_is_violation: bool = false

@export_group("Window / focus (optional)")
@export var focus_loss_hard_cap_sec: float = 0.0

@export_group("Runtime diagnostics (optional)")
## If true, loads the lightweight Status/Log overlay (Ctrl+Shift+F12). Configure policy in the Godot Editor dock / Inspector instead.
@export var in_game_dev_overlay_enabled: bool = false
@export var dev_menu_allow_in_release: bool = false
@export var dev_menu_password: String = "change-me-in-shipping-build"
