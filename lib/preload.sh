#!/bin/bash
################################################################################
# Luxor Memory Manager Preload Module
# 
# Modular library for detecting and injecting memory managers (TCMalloc, jemalloc, etc.)
# Supports both system libraries and custom Ryoko paths
#
# Usage:
#   source lib/preload.sh
#   load_preload_library "tcmalloc" [fallback_paths]
#   
# Exit Codes:
#   0 = Success (LD_PRELOAD set)
#   1 = Not applicable (skipped, e.g., non-Linux)
#   2 = Library not found
#   3 = Validation failed (glibc incompatibility)
################################################################################

set -o pipefail

# ============================================================================
# PRIVATE: Get glibc version in comparable format
# Output: "234" for glibc 2.34, "236" for 2.36, etc.
# ============================================================================
_get_glibc_version() {
    local raw_version
    raw_version=$(ldd --version 2>/dev/null | awk 'NR==1 {print $NF}')
    
    if [[ -z "$raw_version" ]]; then
        echo "0"
        return 1
    fi
    
    # Convert "2.36" → "236" for numeric comparison
    # Handle edge case: "2.3.6" → "236"
    printf '%s\n' "$raw_version" | sed 's/\.//g'
}

# ============================================================================
# PRIVATE: Validate preload library compatibility with current glibc
# 
# Args: $1 = library path to validate
#       $2 = memory manager name (for logging)
#
# Returns: 0 if valid, 3 if incompatible
# ============================================================================
_validate_preload_library() {
    local lib_path="$1"
    local mm_name="${2:-unknown}"
    
    # Check if library exists
    if [[ ! -f "$lib_path" ]]; then
        echo "[ERROR] Library file not found: $lib_path" >&2
        return 3
    fi
    
    # Get glibc version
    local glibc_ver
    glibc_ver=$(_get_glibc_version)
    
    if [[ $glibc_ver -eq 0 ]]; then
        echo "[WARNING] Could not determine glibc version, proceeding with caution" >&2
        return 0  # Allow it, but warn
    fi
    
    echo "[DEBUG] glibc version: $(( $glibc_ver / 100 )).$(( $glibc_ver % 100 ))" >&2
    
    # glibc < 2.34 requires libpthread support
    if [[ $glibc_ver -lt 234 ]]; then
        if ldd "$lib_path" 2>/dev/null | grep -q 'libpthread'; then
            echo "[INFO] $mm_name linked with libpthread (glibc < 2.34)" >&2
            return 0
        else
            echo "[ERROR] $mm_name NOT linked with libpthread. This will cause 'undefined symbol: pthread_key_create' error" >&2
            return 3
        fi
    else
        # glibc >= 2.34: pthread integrated into libc
        echo "[INFO] $mm_name compatible with glibc >= 2.34 (pthread in libc)" >&2
        return 0
    fi
}

# ============================================================================
# PRIVATE: Search for memory manager library in system paths
#
# Args: $1 = memory manager name (tcmalloc, jemalloc, mimalloc, etc.)
#       $2+ = additional search paths (optional)
#
# Returns: prints full path to library on success
# ============================================================================
_find_preload_library() {
    local mm_name="$1"
    shift
    local custom_paths=("$@")
    
    # Define search patterns per memory manager
    local search_patterns
    case "$mm_name" in
        tcmalloc|lxgptools)
            search_patterns=("libtcmalloc_minimal.so.*" "libtcmalloc.so.*")
            ;;
        jemalloc)
            search_patterns=("libjemalloc.so.*")
            ;;
        mimalloc)
            search_patterns=("libmimalloc.so.*")
            ;;
        *)
            # Generic pattern: lib{name}.so.*
            search_patterns=("lib${mm_name}.so.*")
            ;;
    esac
    
    # Phase 1: Custom paths (Ryoko, /opt, user-provided)
    for custom_path in "${custom_paths[@]}"; do
        if [[ -f "$custom_path" ]]; then
            echo "$custom_path"
            return 0
        fi
    done
    
    # Phase 2: System ldconfig (fastest, if available)
    if command -v ldconfig &>/dev/null; then
        local lib_line
        for pattern in "${search_patterns[@]}"; do
            lib_line=$(PATH=/sbin:/usr/sbin:$PATH ldconfig -p 2>/dev/null | \
                       grep -oP "[^ ]*/\Q${pattern//\*/.*}\E" | head -n 1)
            if [[ -n "$lib_line" ]]; then
                echo "$lib_line"
                return 0
            fi
        done
    fi
    
    # Phase 3: Fallback to manual search in standard paths
    local standard_paths=(
        "/usr/lib"
        "/usr/lib64"
        "/usr/lib/x86_64-linux-gnu"
        "/usr/lib/i386-linux-gnu"
        "/lib"
        "/lib64"
    )
    
    for std_path in "${standard_paths[@]}"; do
        for pattern in "${search_patterns[@]}"; do
            local found
            found=$(find "$std_path" -maxdepth 1 -name "$pattern" 2>/dev/null | head -n 1)
            if [[ -n "$found" ]]; then
                echo "$found"
                return 0
            fi
        done
    done
    
    # Not found
    return 2
}

# ============================================================================
# PUBLIC: Main function - Load preload library
#
# Args:
#   $1 = memory manager name (tcmalloc, jemalloc, mimalloc)
#   $2... = additional search paths (optional)
#
# Environment:
#   NO_TCMALLOC (legacy) = skip all preload
#   NO_PRELOAD = skip all preload (Ryoko)
#   LD_PRELOAD = if already set, skip (respect user override)
#   PRELOAD_DEBUG = set to 1 for verbose logging
#
# Returns:
#   0 = LD_PRELOAD set successfully
#   1 = Skipped (not applicable)
#   2 = Library not found
#   3 = Validation failed
# ============================================================================
load_preload_library() {
    local mm_name="${1}"
    shift
    local extra_paths=("$@")
    
    # Preconditions: only on Linux
    if [[ "${OSTYPE}" != "linux"* ]]; then
        [[ "${PRELOAD_DEBUG}" == "1" ]] && echo "[DEBUG] Not Linux (${OSTYPE}), skipping preload" >&2
        return 1
    fi
    
    # Skip if disabled
    if [[ -n "${NO_PRELOAD}" ]] || [[ -n "${NO_TCMALLOC}" ]]; then
        echo "[INFO] Preload disabled by NO_PRELOAD or NO_TCMALLOC" >&2
        return 1
    fi
    
    # Skip if already set
    if [[ -n "${LD_PRELOAD}" ]]; then
        echo "[WARNING] LD_PRELOAD already set to: ${LD_PRELOAD}. Skipping." >&2
        return 1
    fi
    
    # Validate memory manager name
    if [[ -z "$mm_name" ]]; then
        echo "[ERROR] Memory manager name not provided" >&2
        return 3
    fi
    
    echo "[INFO] Attempting to load preload library: $mm_name" >&2
    
    # Search for library
    local lib_path
    lib_path=$(_find_preload_library "$mm_name" "${extra_paths[@]}")
    local find_result=$?
    
    if [[ $find_result -ne 0 ]]; then
        echo "[ERROR] Could not locate library for: $mm_name" >&2
        echo "[HINT] Install: sudo apt install lib${mm_name} (Debian/Ubuntu)" >&2
        return 2
    fi
    
    # Validate library
    _validate_preload_library "$lib_path" "$mm_name"
    local validate_result=$?
    
    if [[ $validate_result -ne 0 ]]; then
        return $validate_result
    fi
    
    # SUCCESS: Export LD_PRELOAD
    export LD_PRELOAD="$lib_path"
    echo "[SUCCESS] LD_PRELOAD set to: $lib_path" >&2
    return 0
}

# ============================================================================
# HELPER: Show preload status
# ============================================================================
show_preload_status() {
    if [[ -n "${LD_PRELOAD}" ]]; then
        echo "[INFO] LD_PRELOAD active: ${LD_PRELOAD}"
        echo "[INFO] Verification:"
        ldd --version 2>/dev/null | head -n 1
        echo ""
    else
        echo "[WARNING] LD_PRELOAD not set"
    fi
}

# Mark as sourced (allow detection in parent scripts)
PRELOAD_MODULE_LOADED=1
