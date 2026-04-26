# Changelog

## Recent Improvements & Fixes

### Core Detection Fixes

#### 1. **Time-Skew Detection Re-enabled** (anticheat_director.gd)
- **Issue**: Time-skew detection was disabled with a `pass` statement, allowing speedhacking to go undetected
- **Fix**: Enabled the violation callback and added editor-aware bypass
- **Impact**: Speedhacks (Cheat Engine VEH, time manipulation) are now properly detected in release builds
- **Code**: Lines 446-452 in `anticheat_director.gd`
  - Added `Engine.is_editor_hint()` check to skip during editor testing
  - Removed blocking `pass` statement
  - Violation now fires when `max_tick_skew_ms` is exceeded

#### 2. **DLL Warmup Window & Path Validation** (anticheat_director.gd, anticheat_config.gd)
- **Issue**: Pre-launch DLL injections (before game start) were captured in the snapshot and became trusted baseline
  - Exploitable via: launcher wrappers, AppInit_DLLs, LD_PRELOAD, DLL hijacking
- **Fix**: 
  - Added `startup_dll_warmup_sec` (default 2.0 seconds) to delay enforcement
  - Added `_filter_dlls_by_trusted_paths()` to validate DLL locations during snapshot
  - DLLs from untrusted paths are excluded from baseline if `use_only_trusted_directory` is enabled
- **Impact**: Pre-injection attacks are now caught after the warmup window expires
- **New Config Options**:
  - `startup_dll_warmup_sec: float = 2.0` — Grace period before snapshot is enforced
  - `_startup_dll_captured_at_sec` — Tracks when snapshot was taken

### Editor Plugin Fixes

#### 3. **Config Auto-Creation with Defaults** (beatrix_ac_dock.gd)
- **Issue**: Custom config paths created empty arrays and missing @export defaults
- **Fix**: Added `_create_default_config()` function that instantiates anticheat_config.gd script and saves with all defaults
- **Impact**: 
  - New configs automatically have all array defaults (suspicious_module_substrings, banned_cmdline_substrings, etc.)
  - No need to manually copy example_ac_config.tres
- **Behavior**:
  - "Open policy in Inspector" now auto-creates missing configs with defaults
  - Initial config_path setup also uses the new function

#### 4. **Directory Auto-Creation** (beatrix_ac_dock.gd)
- **Issue**: Saving to non-existent directories failed silently
- **Fix**: Added `_ensure_dir_exists()` helper to recursively create parent directories
- **Impact**: Users can set config_path to `res://my/custom/config/path.tres` without pre-creating directories

#### 5. **Deferred UI Initialization** (beatrix_ac_dock.gd)
- **Issue**: Editor plugin meta was not yet set when `_ready()` called, causing "dock missing editor plugin meta" error
- **Fix**: 
  - Deferred UI setup with `call_deferred(&"_setup_ui")`
  - Added retry logic in `_setup_ui()` if meta not yet available
- **Impact**: Dock loads cleanly without errors on plugin initialization

#### 6. **Config Path Resolution Fix** (anticheat_director.gd)
- **Issue**: Config loading always fell back to example_ac_config.tres instead of script defaults
- **Fix**: Removed example_ac_config.tres from fallback chain
- **New Priority**:
  1. Project setting `beatrix_ac/config_path` (if configured)
  2. `ac_config.tres` (if exists)
  3. Script defaults from anticheat_config.gd

---

## Summary of Files Modified

| File | Changes |
|------|---------|
| `core/anticheat_director.gd` | Re-enabled time-skew violation; added DLL warmup window; updated config path resolution |
| `core/anticheat_config.gd` | Added warmup config variables; removed example config fallback |
| `editor/beatrix_ac_dock.gd` | Auto-creation with defaults; directory auto-creation; deferred UI init; meta retry logic |

---

## Testing Checklist

- [ ] Time-skew detection fires on Cheat Engine speedhack
- [ ] DLL injection detected after 2-second warmup (or configured duration)
- [ ] Custom config paths auto-create with all defaults populated
- [ ] Non-existent directories are created automatically
- [ ] Editor dock loads without meta errors
- [ ] Policy edits persist when saved to custom paths

---

## Migration Notes

**For existing projects:**
- No action required; configs continue to work
- To benefit from auto-creation, delete old empty custom configs and let them regenerate
- Review `startup_dll_warmup_sec` if you customize DLL detection settings
