#!/bin/bash
#==============================================================================
# JellyMac/lib/scanning_utils.sh
#==============================================================================
# Provides dedicated background scanning functionalities for JellyMac.
# This script is intended to be launched in the background by jellymac.sh.
#
# Responsibilities:
# - Monitors clipboard for YouTube links and adds them to the YouTube queue.
# - Monitors clipboard for magnet links and launches the magnet handler.
# - Watches the DROP_FOLDER for new media files/folders and launches processor.
#==============================================================================

# --- Script Setup ---
# Ensure this script knows its own directory and the project root
_SCANNING_UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC2034 # JELLYMAC_PROJECT_ROOT is used by sourced scripts
JELLYMAC_PROJECT_ROOT="$(dirname "$_SCANNING_UTILS_SCRIPT_DIR")" # Use dirname for clarity and linter compatibility

# --- Source Essential Libraries ---
# These scripts expect JELLYMAC_PROJECT_ROOT to be set and exported.
# The main jellymac.sh script should ensure all necessary variables (including SCRIPT_CURRENT_LOG_LEVEL)
# and configurations are exported into the environment for this background script.

if [[ -f "${JELLYMAC_PROJECT_ROOT}/lib/logging_utils.sh" ]]; then
    # shellcheck source=lib/logging_utils.sh
    # shellcheck disable=SC1091
    source "${JELLYMAC_PROJECT_ROOT}/lib/logging_utils.sh"
else
    echo "FATAL: scanning_utils.sh: logging_utils.sh not found. Exiting." >&2
    exit 1
fi

if [[ -f "${JELLYMAC_PROJECT_ROOT}/lib/common_utils.sh" ]]; then
    # shellcheck source=lib/common_utils.sh
    # shellcheck disable=SC1091
    source "${JELLYMAC_PROJECT_ROOT}/lib/common_utils.sh"
else
    log_fatal_event "ScanningLoop" "common_utils.sh not found. Exiting."
    exit 1
fi

if [[ -f "${JELLYMAC_PROJECT_ROOT}/lib/youtube_utils.sh" ]]; then
    # shellcheck source=lib/youtube_utils.sh
    # shellcheck disable=SC1091
    source "${JELLYMAC_PROJECT_ROOT}/lib/youtube_utils.sh"
else
    log_fatal_event "ScanningLoop" "youtube_utils.sh not found. Exiting."
    exit 1
fi

# --- Local State Variables for Scanning ---
LAST_CLIPBOARD_CONTENT_SCANNER_YT=""
LAST_CLIPBOARD_CONTENT_SCANNER_MAGNET=""

# --- Logging Prefix ---
_SCANNER_LOG_PREFIX="Scanner"

# --- Function Definitions ---

# Function: _scan_clipboard_for_youtube
_scan_clipboard_for_youtube() {
    if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" != "true" || -z "${PBPASTE_CMD}" ]]; then
        return
    fi

    local current_cb_content
    current_cb_content=$("$PBPASTE_CMD" 2>/dev/null || echo "CLIPBOARD_READ_ERROR")

    if [[ "$current_cb_content" == "CLIPBOARD_READ_ERROR" ]]; then
        log_trace_event "$_SCANNER_LOG_PREFIX" "Clipboard read error (YouTube scan)."
        return
    fi

    if [[ "$current_cb_content" != "$LAST_CLIPBOARD_CONTENT_SCANNER_YT" && -n "$current_cb_content" ]]; then
        LAST_CLIPBOARD_CONTENT_SCANNER_YT="$current_cb_content"
        local trimmed_cb; trimmed_cb="$(echo -E "${current_cb_content}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        case "$trimmed_cb" in
            https://www.youtube.com/watch?v=*|https://youtu.be/*)
                log_debug_event "$_SCANNER_LOG_PREFIX" "YouTube link detected: ${trimmed_cb:0:70}..."
                _add_youtube_to_queue "$trimmed_cb" # From youtube_utils.sh
                ;;
        esac
    fi
}

# Function: _scan_clipboard_for_magnet
_scan_clipboard_for_magnet() {
    if [[ "${ENABLE_CLIPBOARD_MAGNET:-false}" != "true" || "${ENABLE_TORRENT_AUTOMATION:-false}" != "true" || -z "${PBPASTE_CMD}" ]]; then
        return
    fi

    local current_cb_content
    current_cb_content=$("$PBPASTE_CMD" 2>/dev/null || echo "CLIPBOARD_READ_ERROR")

    if [[ "$current_cb_content" == "CLIPBOARD_READ_ERROR" ]]; then
        log_trace_event "$_SCANNER_LOG_PREFIX" "Clipboard read error (Magnet scan)."
        return
    fi

    if [[ "$current_cb_content" != "$LAST_CLIPBOARD_CONTENT_SCANNER_MAGNET" && -n "$current_cb_content" ]]; then
        LAST_CLIPBOARD_CONTENT_SCANNER_MAGNET="$current_cb_content"
        local trimmed_cb; trimmed_cb="$(echo -E "${current_cb_content}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if [[ "$trimmed_cb" == magnet:* ]]; then
            log_user_info "$_SCANNER_LOG_PREFIX" "Magnet link detected: ${trimmed_cb:0:70}..."
            if [[ -n "$HANDLE_MAGNET_SCRIPT" && -x "$HANDLE_MAGNET_SCRIPT" ]]; then
                "$HANDLE_MAGNET_SCRIPT" "$trimmed_cb" &
            else
                log_error_event "$_SCANNER_LOG_PREFIX" "Magnet handler script not found or not executable: $HANDLE_MAGNET_SCRIPT"
            fi
        fi
    fi
}

# Function: _scan_drop_folder
_scan_drop_folder() {
    if [[ -z "$DROP_FOLDER" || ! -d "$DROP_FOLDER" ]]; then
        log_trace_event "$_SCANNER_LOG_PREFIX" "Drop folder not configured or not found: $DROP_FOLDER"
        return
    fi

    find "$DROP_FOLDER" -maxdepth 1 -mindepth 1 -print0 | while IFS= read -r -d $\'\\0\' item_path; do
        local item_name
        item_name=$(basename "$item_path")

        if [[ "$item_name" == .* || "$item_name" == "desktop.ini" || "$item_name" == "Thumbs.db" || "$item_name" == ".DS_Store" ]]; then
            log_trace_event "$_SCANNER_LOG_PREFIX" "Skipping hidden/system item in drop folder: $item_name"
            continue
        fi
        
        # Rely on is_file_stable from common_utils.sh
        if ! is_file_stable "$item_path"; then
            log_debug_event "$_SCANNER_LOG_PREFIX" "Item in drop folder not yet stable: $item_name. Skipping for now."
            continue
        fi

        # Basic check to see if a lock file for this item already exists (from process_media_item.sh)
        # This is a simple way to avoid re-triggering for items already being processed.
        # process_media_item.sh should create a lock like: ${STATE_DIR}/processing_$(basename "$item_path").lock
        local item_basename; item_basename=$(basename "$item_path")
        local potential_lock_file="${STATE_DIR}/processing_${item_basename}.lock"
        if [[ -f "$potential_lock_file" ]]; then
            log_trace_event "$_SCANNER_LOG_PREFIX" "Item '$item_basename' appears to be already processing (lock file found). Skipping."
            continue
        fi
        
        # Check if item was recently seen in this scan cycle using a proper array loop
        local found_in_recently_seen=false
        for seen_item in "${RECENTLY_SEEN_DROP_ITEMS[@]}"; do
            if [[ "$seen_item" == "$item_path" ]]; then
                found_in_recently_seen=true
                break
            fi
        done
        if [[ "$found_in_recently_seen" == "true" ]]; then
            log_trace_event "$_SCANNER_LOG_PREFIX" "Item '$item_basename' recently seen in this scan cycle. Skipping."
            continue
        fi
        RECENTLY_SEEN_DROP_ITEMS+=("$item_path")


        log_user_info "$_SCANNER_LOG_PREFIX" "New stable item detected in drop folder: $item_name"
        if [[ -n "$PROCESS_MEDIA_ITEM_SCRIPT" && -x "$PROCESS_MEDIA_ITEM_SCRIPT" ]]; then
            "$PROCESS_MEDIA_ITEM_SCRIPT" "$item_path" &
            sleep 1 # Small delay to allow lock file creation and prevent rapid succession
        else
            log_error_event "$_SCANNER_LOG_PREFIX" "Media processor script not found or not executable: $PROCESS_MEDIA_ITEM_SCRIPT"
        fi
    done
}

# --- Main Scanning Loop ---
log_info_event "$_SCANNER_LOG_PREFIX" "Background scanner started. PID: $$"

# Trap for cleanup on exit
trap '_scanner_cleanup' SIGINT SIGTERM EXIT
_scanner_cleanup() {
    log_info_event "$_SCANNER_LOG_PREFIX" "Background scanner stopping (PID: $$)."
}

RECENTLY_SEEN_DROP_ITEMS=() # Initialize array for drop folder items seen in current cycle

while true; do
    if [[ -z "$SCRIPT_CURRENT_LOG_LEVEL" || -z "$STATE_DIR" || -z "$JELLYMAC_PROJECT_ROOT" ]]; then
        # Use echo as logging might not be fully set up if these are missing
        echo "FATAL: scanning_utils.sh: Essential environment variables missing (SCRIPT_CURRENT_LOG_LEVEL, STATE_DIR, or JELLYMAC_PROJECT_ROOT). Exiting." >&2
        exit 1
    fi

    log_trace_event "$_SCANNER_LOG_PREFIX" "Scanning cycle started."
    
    # Clear recently seen items at the start of each full scan cycle
    # This allows items that were skipped for stability to be re-evaluated.
    RECENTLY_SEEN_DROP_ITEMS=()

    _scan_clipboard_for_youtube
    _scan_clipboard_for_magnet
    _scan_drop_folder

    log_trace_event "$_SCANNER_LOG_PREFIX" "Scanning cycle ended. Sleeping for ${MAIN_LOOP_SLEEP_INTERVAL:-5}s."
    sleep "${MAIN_LOOP_SLEEP_INTERVAL:-5}"
done
