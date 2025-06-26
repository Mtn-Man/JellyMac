#!/bin/bash

# JellyMac/bin/handle_magnet_link.sh
# Handles adding a magnet link to the Transmission torrent client.
# This script is specifically designed for use with 'transmission-remote'.
# Utilizes functions from lib/common_utils.sh.

# --- Strict Mode & Globals ---
set -euo pipefail # Enable strict mode for better error handling

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)" # Assumes lib is one level up from bin

#==============================================================================
# TEMPORARY FILE MANAGEMENT
#==============================================================================
# Global array to track temporary files created during script execution
_SCRIPT_TEMP_FILES_TO_CLEAN=()

# Function: _cleanup_script_temp_files
# Description: Cleans up temporary files created during script execution
# Parameters: None
# Returns: None
# Side Effects: Removes all tracked temporary files and clears the tracking array
_cleanup_script_temp_files() {
    # shellcheck disable=SC2128 # We want to check array length
    # shellcheck disable=SC2317 
    if [[ ${#_SCRIPT_TEMP_FILES_TO_CLEAN[@]} -gt 0 ]]; then
        log_debug_event "Torrent" "EXIT trap: Cleaning up temporary files (${#_SCRIPT_TEMP_FILES_TO_CLEAN[@]})..."
        local temp_file_to_clean
        for temp_file_to_clean in "${_SCRIPT_TEMP_FILES_TO_CLEAN[@]}"; do
            if [[ -n "$temp_file_to_clean" && -e "$temp_file_to_clean" ]]; then
                rm -f "$temp_file_to_clean"
                log_debug_event "Torrent" "EXIT trap: Removed '$temp_file_to_clean'"
            fi
        done
    fi
    # shellcheck disable=SC2317
    _SCRIPT_TEMP_FILES_TO_CLEAN=()
}
# Trap for this script's specific temp files.
trap _cleanup_script_temp_files EXIT SIGINT SIGTERM

#==============================================================================
# LIBRARY SOURCING AND CONFIGURATION
#==============================================================================

# --- Source Libraries ---
# shellcheck source=../lib/logging_utils.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/logging_utils.sh"
# Configuration is now inherited from the parent shell (jellymac.sh)
# shellcheck source=../lib/common_utils.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/common_utils.sh" # For find_executable, record_transfer_to_history, play_sound_notification

# --- Configuration Loading ---
# This script is designed to inherit its configuration from the main jellymac.sh
# script. The following block allows for standalone execution (e.g., for testing)
# by loading the configuration if it hasn't been loaded already.
# We check for JELLYMAC_PROJECT_ROOT, which is a reliable indicator.
if [[ -z "${JELLYMAC_PROJECT_ROOT:-}" ]]; then
    export JELLYMAC_PROJECT_ROOT
    JELLYMAC_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
    
    # shellcheck source=../lib/parsing_utils.sh
    # shellcheck disable=SC1091
    source "${LIB_DIR}/parsing_utils.sh"
    
    CONFIG_PATH="${JELLYMAC_PROJECT_ROOT}/Configuration.txt"
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error_event "Torrent" "CRITICAL: Configuration.txt not found for standalone execution."
        exit 1
    fi
    
    _parse_and_export_config "$CONFIG_PATH"

    # Initialize logging variables for standalone execution
    # These are normally set by jellymac.sh
    # shellcheck disable=SC2034
    LAST_LOG_DATE_CHECKED=""
    # shellcheck disable=SC2034
    CURRENT_LOG_FILE_PATH=""
    case "$(echo "${LOG_LEVEL:-INFO}" | tr '[:lower:]' '[:upper:]')" in
        "DEBUG") SCRIPT_CURRENT_LOG_LEVEL=4 ;;
        "INFO")  SCRIPT_CURRENT_LOG_LEVEL=3 ;;
        "WARN")  SCRIPT_CURRENT_LOG_LEVEL=2 ;;
        "ERROR") SCRIPT_CURRENT_LOG_LEVEL=1 ;;
        *)       SCRIPT_CURRENT_LOG_LEVEL=3 ;;
    esac
    export SCRIPT_CURRENT_LOG_LEVEL
fi

# --- Log Level & Prefix Initialization ---
# The SCRIPT_CURRENT_LOG_LEVEL (and _log_to_current_file function) will be inherited from the parent (jellymac.sh)

#==============================================================================
# MAGNET LINK PROCESSING FUNCTIONS
#==============================================================================

# Function: main
# Description: Main entry point for magnet link processing - validates magnet URL format,
#              connects to Transmission daemon, and adds magnet link to download queue
# Parameters:
#   $1 - Magnet URL to process (must start with magnet:?xt=urn:btih:)
# Returns: 
#   0 - Success (link added or duplicate handled)
#   1 - Failure (invalid format, connection error, or processing error)
# Side Effects: Adds magnet link to Transmission, records history, sends notifications

# --- Pre-flight Checks & Variable Setup ---
#==============================================================================
# ARGUMENT VALIDATION
#==============================================================================
if [[ $# -ne 1 ]]; then
    log_error_event "Torrent" "Usage: $SCRIPT_NAME <magnet_url>"
    exit 1
fi
MAGNET_URL="$1"
log_debug_event "Torrent" "Processing URL: ${MAGNET_URL:0:100}..."

#==============================================================================
# CONFIGURATION AND DEPENDENCY VALIDATION
#==============================================================================
# Check essential configuration variables (expected to be inherited from parent)
if [[ -z "$TRANSMISSION_REMOTE_HOST" ]]; then 
    log_error_event "Torrent" "CRITICAL: TRANSMISSION_REMOTE_HOST is not set."
    exit 1
fi

if [[ -z "${STATE_DIR:-}" ]]; then
    log_error_event "Torrent" "CRITICAL: STATE_DIR is not set. Cannot create temp files."
    exit 1
fi

# Locate the transmission-remote executable
TRANSMISSION_REMOTE_EXECUTABLE=$(find_executable "transmission-remote" "${TORRENT_CLIENT_CLI_PATH:-}")

if [[ -z "$TRANSMISSION_REMOTE_EXECUTABLE" ]]; then
    log_error_event "Torrent" "CRITICAL: 'transmission-remote' executable not found."
    log_error_event "Torrent" "Please install 'transmission-cli' (brew install transmission-cli) and check TORRENT_CLIENT_CLI_PATH in config."
    exit 1
fi

# Check for existence of download archive file if configured
if [[ -n "${DOWNLOAD_ARCHIVE_MAGNET:-}" ]]; then
    archive_dir=$(dirname "$DOWNLOAD_ARCHIVE_MAGNET")
    if [[ ! -d "$archive_dir" ]]; then
        if ! mkdir -p "$archive_dir"; then
            log_warn_event "Torrent" "Failed to create archive directory: '$archive_dir'. Archive will not be used."
            DOWNLOAD_ARCHIVE_MAGNET="" # Unset to prevent further errors
        else
            log_debug_event "Torrent" "Created directory for magnet download archive: $archive_dir"
        fi
    fi
fi

# --- Main Logic ---

#==============================================================================
# CONSTRUCT TRANSMISSION-REMOTE COMMAND
#==============================================================================
# Build the command arguments array
declare -a cmd_args=("$TRANSMISSION_REMOTE_HOST")

# Add authentication if provided in the config
if [[ -n "$TRANSMISSION_REMOTE_AUTH" ]]; then 
    cmd_args+=("--auth" "$TRANSMISSION_REMOTE_AUTH")
fi

# Add the magnet URL
cmd_args+=("--add" "$MAGNET_URL")

#==============================================================================
# PROCESS MAGNET LINK AND HANDLE DOWNLOAD ARCHIVE
#==============================================================================
log_user_progress "Torrent" "🧲 Processing magnet link..."

# Extract magnet hash for archive checking (infohash)
# This is a robust way to check for duplicates
MAGNET_HASH=""
if [[ "$MAGNET_URL" =~ xt=urn:btih:([^&]+) ]]; then
    MAGNET_HASH="${BASH_REMATCH[1]}"
    # Normalize to uppercase for consistency if needed, though most are already
    MAGNET_HASH=$(echo "$MAGNET_HASH" | tr '[:lower:]' '[:upper:]' | cut -c 1-40)
    log_debug_event "Torrent" "Extracted magnet hash: $MAGNET_HASH"
else
    log_warn_event "Torrent" "Could not extract magnet hash from URL. Duplicate check may be unreliable."
fi

# Prevent re-adding torrent if already in archive
if [[ -n "$DOWNLOAD_ARCHIVE_MAGNET" && -n "$MAGNET_HASH" && -f "$DOWNLOAD_ARCHIVE_MAGNET" ]]; then
    if grep -q "^magnet $MAGNET_HASH$" "$DOWNLOAD_ARCHIVE_MAGNET" 2>/dev/null; then
        log_user_info "Torrent" "🔄 Magnet link already processed (found in archive). Skipping."
        exit 0
    fi
fi

#==============================================================================
# EXECUTE COMMAND AND PROVIDE USER FEEDBACK
#==============================================================================
log_user_info "Torrent" "📡 Connecting to Transmission..."

set +e # Temporarily disable exit on error to capture output
transmission_output=$("$TRANSMISSION_REMOTE_EXECUTABLE" "${cmd_args[@]}" 2>&1)
transmission_exit_code=$?
set -e # Re-enable exit on error

if [[ "$transmission_exit_code" -eq 0 && "$transmission_output" =~ "success" ]]; then
    log_user_complete "Torrent" "🧲 Torrent added to queue"
    log_user_info "Torrent" "📊 Track progress at: http://$TRANSMISSION_REMOTE_HOST/transmission/web/"
    
    # Record to history and archive
    record_transfer_to_history "Magnet: ${MAGNET_HASH}" || log_warn_event "Torrent" "History record failed."
    if [[ -n "$DOWNLOAD_ARCHIVE_MAGNET" && -n "$MAGNET_HASH" ]]; then
        echo "magnet $MAGNET_HASH" >> "$DOWNLOAD_ARCHIVE_MAGNET"
        log_debug_event "Torrent" "Recorded magnet hash to archive: $DOWNLOAD_ARCHIVE_MAGNET"
    fi
    
    # Send desktop notification on success if enabled
    if [[ "${ENABLE_DESKTOP_NOTIFICATIONS:-false}" == "true" ]]; then
        send_desktop_notification "JellyMac: Torrent Added" "Sent to Transmission: ${MAGNET_HASH}"
    fi
    
    log_user_complete "Torrent" "✅ Magnet link processing completed successfully"
    exit 0
else
    log_error_event "Torrent" "❌ Failed to add torrent."
    log_error_event "Torrent" "Transmission-remote exit code: $transmission_exit_code"
    log_error_event "Torrent" "Output: $transmission_output"
    
    # Send desktop notification on failure if enabled
    if [[ "${ENABLE_DESKTOP_NOTIFICATIONS:-false}" == "true" ]]; then
        send_desktop_notification "JellyMac: Torrent Error" "Failed to add: ${MAGNET_HASH}" "Basso"
    fi
    
    # Sound notification for error
    play_sound_notification "task_error" "Torrent"
    exit 1
fi
