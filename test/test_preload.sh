#!/bin/bash
################################################################################
# Luxor Engine - Preload Module Test Suite
# 
# Tests for lib/preload.sh module
# Validates: glibc detection, library discovery, fallback chains, integration
################################################################################

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test environment setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRELOAD_MODULE="$SCRIPT_DIR/lib/preload.sh"

# ============================================================================
# HELPERS
# ============================================================================

_test_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test: $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

_assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo -e "  Expected: '$expected'"
        echo -e "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

_assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Evaluate the condition
    if eval "[[ $condition ]]"; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (condition: $condition)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

_assert_false() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! eval "$condition"; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (expected condition to be false)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}
_assert_command_exists() {
    local command="$1"
    local message="${2:-Command/function should exist}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if type "$command" &>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}
_skip_test() {
    local message="$1"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}⊘ SKIP${NC}: $message"
}

# ============================================================================
# TEST SUITE 1: Module Loading
# ============================================================================

test_module_loading() {
    _test_header "Module Loading and Initialization"
    
    # Check if preload module exists
    _assert_true "-f '$PRELOAD_MODULE'" "Preload module file exists"
    
    # Check if module is readable
    _assert_true "-r '$PRELOAD_MODULE'" "Preload module is readable"
    
    # Source module in subshell
    output=$(bash -c "source '$PRELOAD_MODULE' && echo \$PRELOAD_MODULE_LOADED" 2>&1)
    _assert_equals "1" "$output" "Module sets PRELOAD_MODULE_LOADED flag"
}

# ============================================================================
# TEST SUITE 2: glibc Detection
# ============================================================================

test_glibc_detection() {
    _test_header "glibc Version Detection"
    
    # Load module for testing
    source "$PRELOAD_MODULE"
    
    # Test _get_glibc_version function exists
    _assert_command_exists "_get_glibc_version" "Function _get_glibc_version exists"
    
    # Get glibc version
    local glibc_ver
    glibc_ver=$(_get_glibc_version)
    
    # Validate glibc output is numeric
    if [[ $glibc_ver =~ ^[0-9]+$ ]]; then
        _assert_true "true" "glibc version is numeric: $glibc_ver"
    else
        _assert_true "false" "glibc version is numeric: $glibc_ver"
    fi
    
    # Validate glibc is within reasonable range (200-250 = 2.00-2.50)
    if [[ $glibc_ver -gt 0 && $glibc_ver -lt 300 ]]; then
        _assert_true "true" "glibc version in reasonable range: $glibc_ver"
    else
        _assert_true "false" "glibc version in reasonable range: $glibc_ver"
    fi
    
    # Display system glibc for reference
    local actual_glibc
    actual_glibc=$(ldd --version 2>/dev/null | awk 'NR==1 {print $NF}')
    echo "  System glibc: $actual_glibc (normalized: $glibc_ver)"
}

# ============================================================================
# TEST SUITE 3: Library Discovery
# ============================================================================

test_library_discovery() {
    _test_header "Library Discovery"
    
    source "$PRELOAD_MODULE"
    
    # Test that _find_preload_library function exists
    _assert_command_exists "_find_preload_library" "Function _find_preload_library exists"
    
    # Test 1: Search for tcmalloc in system
    local tcmalloc_found
    tcmalloc_found=$(_find_preload_library "tcmalloc" 2>/dev/null)
    
    if [[ -n "$tcmalloc_found" ]]; then
        echo "  Found tcmalloc at: $tcmalloc_found"
        _assert_true "-f '$tcmalloc_found'" "Found tcmalloc path is valid file"
        if [[ "$tcmalloc_found" =~ libtcmalloc ]]; then
            _assert_true "true" "Found path contains 'libtcmalloc'"
        else
            _assert_true "false" "Found path contains 'libtcmalloc'"
        fi
    else
        _skip_test "TCMalloc not installed on system (OK for macOS/Windows)"
    fi
}

# ============================================================================
# TEST SUITE 4: Fallback Chain Logic
# ============================================================================

test_fallback_chain() {
    _test_header "Fallback Chain (3-Phase Search)"
    
    source "$PRELOAD_MODULE"
    
    # Test Phase 1: Custom paths (mock)
    local temp_lib
    temp_lib=$(mktemp)
    
    # Test finding mock library with custom path
    result=$(_find_preload_library "tcmalloc" "$temp_lib" 2>/dev/null)
    _assert_equals "$temp_lib" "$result" "Phase 1: Found custom mock path"
    
    # Clean up mock
    rm -f "$temp_lib"
    
    # Test Phase 2: ldconfig (if available)
    if command -v ldconfig &>/dev/null; then
        echo "  ldconfig available: running Phase 2 tests"
        result=$(_find_preload_library "libc" 2>/dev/null)
        if [[ -n "$result" ]]; then
            _assert_true "true" "Phase 2: ldconfig search returned result"
        else
            _assert_true "false" "Phase 2: ldconfig search returned result"
        fi
    else
        _skip_test "ldconfig not available"
    fi
}

# ============================================================================
# TEST SUITE 5: Validation Logic
# ============================================================================

test_validation_logic() {
    _test_header "Library Validation (glibc Compatibility)"
    
    source "$PRELOAD_MODULE"
    
    _assert_command_exists "_validate_preload_library" "Function _validate_preload_library exists"
    
    # Find a real library to test validation
    local test_lib
    test_lib=$(find /lib* /usr/lib* -name "libc.so*" -type f 2>/dev/null | head -n 1)
    
    if [[ -n "$test_lib" ]]; then
        echo "  Testing with: $test_lib"
        
        # Validate should return 0 for libc
        _validate_preload_library "$test_lib" "test_lib" > /dev/null 2>&1
        local result=$?
        if [[ $result -eq 0 || $result -eq 1 ]]; then
            _assert_true "true" "Validation returns 0 (valid) or 1 (warning)"
        else
            _assert_true "false" "Validation returns 0 (valid) or 1 (warning)"
        fi
    else
        _skip_test "Could not find test library"
    fi
}

# ============================================================================
# TEST SUITE 6: Load Preload Library (Integration)
# ============================================================================

test_load_preload_library() {
    _test_header "Integration: load_preload_library Function"
    
    source "$PRELOAD_MODULE"
    
    _assert_command_exists "load_preload_library" "Function load_preload_library exists"
    
    # Test 1: Disabled via NO_PRELOAD
    echo "  Subtest 1: NO_PRELOAD flag"
    (
        export NO_PRELOAD=1
        load_preload_library "tcmalloc" > /dev/null 2>&1
        result=$?
        [[ $result -eq 1 ]] && echo "    ✓ Correctly skipped with NO_PRELOAD" || echo "    ✗ Should skip with NO_PRELOAD"
    )
    
    # Test 2: Non-Linux OS
    echo "  Subtest 2: OS filtering"
    (
        export OSTYPE="darwin21.6.0"
        export NO_PRELOAD=""
        load_preload_library "tcmalloc" > /dev/null 2>&1
        result=$?
        [[ $result -eq 1 ]] && echo "    ✓ Correctly skipped on macOS" || echo "    ✗ Should skip on macOS"
    )
    
    # Test 3: LD_PRELOAD already set
    echo "  Subtest 3: LD_PRELOAD already set"
    (
        export OSTYPE="linux-gnu"
        export NO_PRELOAD=""
        export LD_PRELOAD="/some/existing/preload.so"
        load_preload_library "tcmalloc" > /dev/null 2>&1
        result=$?
        [[ $result -eq 1 ]] && echo "    ✓ Correctly skipped when LD_PRELOAD exists" || echo "    ✗ Should skip when LD_PRELOAD exists"
    )
}

# ============================================================================
# TEST SUITE 7: Environment Handling
# ============================================================================

test_environment_variables() {
    _test_header "Environment Variable Handling"
    
    source "$PRELOAD_MODULE"
    
    # Test PRELOAD_DEBUG flag
    echo "  Subtest 1: Debug logging"
    output=$(
        export OSTYPE="darwin"
        export PRELOAD_DEBUG=1
        load_preload_library "tcmalloc" 2>&1
    )
    if [[ "$output" =~ DEBUG || "$output" =~ INFO ]]; then
        _assert_true "true" "Debug flag produces verbose output"
    else
        _assert_true "false" "Debug flag produces verbose output"
    fi
    
    # Test legacy NO_TCMALLOC flag (backward compatibility)
    echo "  Subtest 2: NO_TCMALLOC backward compatibility"
    (
        export NO_TCMALLOC=1
        export OSTYPE="linux-gnu"
        load_preload_library "tcmalloc" > /dev/null 2>&1
        result=$?
        [[ $result -eq 1 ]] && echo "    ✓ NO_TCMALLOC flag respected" || echo "    ✗ NO_TCMALLOC should be respected"
    )
}

# ============================================================================
# TEST SUITE 8: Error Handling
# ============================================================================

test_error_handling() {
    _test_header "Error Handling and Exit Codes"
    
    source "$PRELOAD_MODULE"
    
    # Test invalid memory manager name
    echo "  Subtest 1: Invalid memory manager"
    (
        export OSTYPE="linux-gnu"
        export NO_PRELOAD=""
        export LD_PRELOAD=""
        load_preload_library "" > /dev/null 2>&1
        result=$?
        [[ $result -eq 3 ]] && echo "    ✓ Returns exit code 3 for invalid name" || echo "    ✗ Should return 3 for invalid name"
    )
    
    # Test library not found
    echo "  Subtest 2: Library not found"
    (
        export OSTYPE="linux-gnu"
        export NO_PRELOAD=""
        export LD_PRELOAD=""
        load_preload_library "nonexistent_lib_xyz123" > /dev/null 2>&1
        result=$?
        [[ $result -eq 2 ]] && echo "    ✓ Returns exit code 2 for library not found" || echo "    ✗ Should return 2 for not found"
    )
}

# ============================================================================
# TEST SUITE 9: Ryoko Integration Points
# ============================================================================

test_ryoko_integration() {
    _test_header "Ryoko Integration Readiness"
    
    source "$PRELOAD_MODULE"
    
    # Test RYOKO_PRELOAD_PATH custom path
    echo "  Subtest 1: RYOKO_PRELOAD_PATH support"
    (
        export OSTYPE="linux-gnu"
        export PRELOAD_DEBUG=1
        export RYOKO_PRELOAD_PATH="/opt/ryoko/libs/libtcmalloc.so.4"
        
        # Create mock Ryoko library
        mkdir -p /tmp/luxor_test/ryoko/libs
        touch /tmp/luxor_test/ryoko/libs/libtcmalloc.so.4
        
        # Test finding custom path
        result=$(_find_preload_library "tcmalloc" "/tmp/luxor_test/ryoko/libs/libtcmalloc.so.4" 2>&1)
        [[ "$result" == "/tmp/luxor_test/ryoko/libs/libtcmalloc.so.4" ]] && \
            echo "    ✓ RYOKO_PRELOAD_PATH correctly found" || \
            echo "    ✗ RYOKO_PRELOAD_PATH not working"
        
        # Cleanup
        rm -rf /tmp/luxor_test
    )
    
    # Check that Ryoko variables are documented
    _assert_true "-f '$SCRIPT_DIR/webui-user.sh.example'" "webui-user.sh.example exists"
    
    if [[ -f "$SCRIPT_DIR/webui-user.sh.example" ]]; then
        if grep -q "RYOKO_PRELOAD_PATH" "$SCRIPT_DIR/webui-user.sh.example"; then
            _assert_true "true" "RYOKO_PRELOAD_PATH documented in webui-user.sh.example"
        else
            _assert_true "false" "RYOKO_PRELOAD_PATH documented in webui-user.sh.example"
        fi
    fi
}

# ============================================================================
# TEST SUITE 10: End-to-End
# ============================================================================

test_end_to_end() {
    _test_header "End-to-End: webui.sh Integration"
    
    # Check that webui.sh sources preload module
    _assert_true "-f '$SCRIPT_DIR/webui.sh'" "webui.sh exists"
    
    if grep -q "source.*lib/preload.sh" "$SCRIPT_DIR/webui.sh"; then
        _assert_true "true" "webui.sh sources lib/preload.sh"
    else
        _assert_true "false" "webui.sh sources lib/preload.sh"
    fi
    
    if grep -q "load_preload_library" "$SCRIPT_DIR/webui.sh"; then
        _assert_true "true" "webui.sh calls load_preload_library"
    else
        _assert_true "false" "webui.sh calls load_preload_library"
    fi
    
    # Verify prepare_tcmalloc is simplified
    local prepare_tcmalloc_lines
    prepare_tcmalloc_lines=$(grep -A 20 "^prepare_tcmalloc()" "$SCRIPT_DIR/webui.sh" | wc -l)
    _assert_true "$prepare_tcmalloc_lines -lt 25" "prepare_tcmalloc is simplified (< 25 lines)"
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

main() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Luxor Engine - Preload Module Test Suite     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Module: $PRELOAD_MODULE${NC}\n"
    
    # Verify module exists
    if [[ ! -f "$PRELOAD_MODULE" ]]; then
        echo -e "${RED}ERROR: Preload module not found at $PRELOAD_MODULE${NC}"
        exit 1
    fi
    
    # Run all tests
    test_module_loading
    test_glibc_detection
    test_library_discovery
    test_fallback_chain
    test_validation_logic
    test_load_preload_library
    test_environment_variables
    test_error_handling
    test_ryoko_integration
    test_end_to_end
    
    # Print summary
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo "Total Tests Run:  $TESTS_RUN"
    echo -e "Passed:           ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:           ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped:          ${YELLOW}$TESTS_SKIPPED${NC}"
    
    local pass_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        pass_rate=$(( (TESTS_PASSED * 100) / TESTS_RUN ))
    fi
    
    echo -e "Pass Rate:        ${GREEN}$pass_rate%${NC}\n"
    
    # Exit code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}\n"
        return 0
    else
        echo -e "${RED}✗ SOME TESTS FAILED${NC}\n"
        return 1
    fi
}

# Run main
main "$@"
