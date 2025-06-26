#!/bin/bash
#==============================================================================
# JellyMac Watcher/jellymac.sh
#==============================================================================
# Main orchestrator script for JellyMac Media Automator.
#
# Purpose:
# - Monitors clipboard for YouTube links and magnet URLs
# - Watches DROP_FOLDER for new media files/folders
# - Launches appropriate processing scripts for each media type
# - Manages concurrent processing of multiple media items if desired
# - Can fully automate the media acquisition pipeline for Jellyfin users (or Plex/Emby)
#
# Author: Eli Sher (Mtn_Man)
# Version: v0.2.6
# Last Updated: 2025-06-25
# License: MIT Open Source

# --- Set Terminal Title ---
printf "\033]0;JellyMac\007"

# --- Strict Mode ---
set -eo pipefail # Exit on error, and error on undefined vars (via pipefail implicitly for commands)

# --- Adjust PATH for macOS Homebrew ---
# Prepend Homebrew's default binary path for Apple Silicon Macs (and common for Intel)
# This helps ensure commands installed via Homebrew (like flock) are found.
if [[ "$(uname)" == "Darwin" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
    # For older Intel Macs, Homebrew might be in /usr/local/bin. instead
    # If /opt/homebrew/bin doesn't exist or flock is still not found,
    # you might need to add /usr/local/bin as well or ensure your
    # .zshrc/.bash_profile correctly sets the PATH for all shell sessions.
    # Example: export PATH="/usr/local/bin:$PATH"
fi

# --- Project Root Directory ---
JELLYMAC_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export JELLYMAC_PROJECT_ROOT
SCRIPT_DIR="$JELLYMAC_PROJECT_ROOT" # Alias for clarity

# --- State Directory ---
STATE_DIR="${SCRIPT_DIR}/.state" # For lock files, temporary scan files etc.
export STATE_DIR

# --- Source Essential Libraries (Order Matters) ---
# 1. Logging Utilities (provides primitive log functions)
# shellcheck source=lib/logging_utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logging_utils.sh"

# 2. Configuration Setup - Handle missing config file and parse settings
CONFIG_FILE_NAME="Configuration.txt"
EXAMPLE_CONFIG_FILE_NAME="Configuration.example.txt"

CONFIG_PATH="${JELLYMAC_PROJECT_ROOT}/${CONFIG_FILE_NAME}"
EXAMPLE_PATH="${JELLYMAC_PROJECT_ROOT}/${EXAMPLE_CONFIG_FILE_NAME}"

# Auto-setup configuration if it doesn't exist
if [[ ! -f "$CONFIG_PATH" ]]; then
    if [[ -f "$EXAMPLE_PATH" ]]; then
        clear
        echo
        echo "                  Welcome to JellyMac 👋"
        echo ""
        echo "It looks like you haven't set up your configuration file yet."
        echo
        
        read -r -p "         Create default '${CONFIG_FILE_NAME}' from example? (Y/n): " response
        
        case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
            ""|y|yes)
                if cp "$EXAMPLE_PATH" "$CONFIG_PATH"; then
                    echo "✅ Created '$CONFIG_FILE_NAME' in your project folder."
                    echo "You can edit this file at any time to customize your paths."
                    echo
                    
                    read -r -p "Customize settings now? (y/N): " open_choice
                    case "$(echo "$open_choice" | tr '[:upper:]' '[:lower:]')" in
                        y|yes)
                            echo "Please edit the file, save your changes, and then run ./jellymac.sh again."
                            # Use 'open' on macOS, 'xdg-open' on Linux if available, fallback to message
                            if command -v open >/dev/null 2>&1; then
                                open "$CONFIG_PATH"
                            elif command -v xdg-open >/dev/null 2>&1; then
                                xdg-open "$CONFIG_PATH"
                            else
                                echo "Could not open file automatically. Please open '$CONFIG_PATH' manually."
                            fi
                            exit 0
                            ;;
                        *)
                            echo "Continuing with default settings..."
                            echo
                            ;;
                    esac
                else
                    echo "❌ Failed to create config file. Check permissions." >&2
                    exit 1
                fi
                ;;
            n|no)
                echo "Setup cancelled. Please create '$CONFIG_FILE_NAME' manually and restart." >&2
                exit 1
                ;;
            *)
                echo "Invalid response. Setup cancelled." >&2
                exit 1
                ;;
        esac
    else
        echo "CRITICAL: Example config '$EXAMPLE_CONFIG_FILE_NAME' not found in project root!" >&2
        echo "Please ensure JellyMac is properly installed." >&2
        exit 1
    fi
fi

# 3. Source the new config parser and load settings
PARSER_LIB_PATH="${SCRIPT_DIR}/lib/parsing_utils.sh"
if [[ ! -f "$PARSER_LIB_PATH" ]]; then
    log_error_event "JellyMacSetup" "CRITICAL: Config parser library not found at '$PARSER_LIB_PATH'."
    exit 1
fi

# shellcheck source=lib/parsing_utils.sh
# shellcheck disable=SC1091
source "$PARSER_LIB_PATH"

# Call the parser function to read the config and export variables.
# The YTDLP_OPTS array will be populated in this script's scope.
if ! _parse_and_export_config "$CONFIG_PATH"; then
    log_error_event "JellyMacSetup" "CRITICAL: Failed to parse configuration file '$CONFIG_PATH'. Check for errors in the file."
    exit 1
fi

# 4. Initialize SCRIPT_CURRENT_LOG_LEVEL (based on LOG_LEVEL from config)
case "$(echo "${LOG_LEVEL:-INFO}" | tr '[:lower:]' '[:upper:]')" in
    "DEBUG") SCRIPT_CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
    "INFO")  SCRIPT_CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    "WARN")  SCRIPT_CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN ;;
    "ERROR") SCRIPT_CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
    *)
        SCRIPT_CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
        # Use log_warn_event directly from logging_utils.sh as local log_warn isn't defined yet
        log_warn_event "[JELLYMAC_SETUP]" "LOG_LEVEL ('${LOG_LEVEL:-NOT SET}') is invalid in config. Defaulting to INFO."
        ;;
esac
export SCRIPT_CURRENT_LOG_LEVEL

# Export other logging-related config variables for subshells (e.g., bin/ scripts)
# These are read from Configuration.txt and used by exported logging functions.
export LOG_ROTATION_ENABLED
export LOG_DIR
export LOG_FILE_BASENAME
export LOG_RETENTION_DAYS
# Note: CURRENT_LOG_FILE_PATH and LAST_LOG_DATE_CHECKED are managed by the exported 
# _ensure_log_file_updated function and will be handled correctly within each 
# subshell's context by that function when it's called.

# 4. Common Utilities (provides play_sound_notification, find_executable, etc.)
# shellcheck source=lib/common_utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common_utils.sh"

# 5. Doctor Utilities (Health Checks)
# shellcheck source=lib/doctor_utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/doctor_utils.sh"

# 6. Media Utilities (for determine_media_category by watcher if needed)
# shellcheck source=lib/media_utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/media_utils.sh"

# 7. YouTube Utilities (for YouTube queue management)
# shellcheck source=lib/youtube_utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/youtube_utils.sh"

# --- Paths to Helper Scripts in bin/ ---
HANDLE_YOUTUBE_SCRIPT="${SCRIPT_DIR}/bin/handle_youtube_link.sh"
HANDLE_MAGNET_SCRIPT="${SCRIPT_DIR}/bin/handle_magnet_link.sh"
PROCESS_MEDIA_ITEM_SCRIPT="${SCRIPT_DIR}/bin/process_media_item.sh"

# --- Local Logging Setup (File Logging & Rotation) ---
_WATCHER_LOG_PREFIX="JellyMac" # This is the unique prefix for jellymac.sh logs
CURRENT_LOG_FILE_PATH=""       # Path to the current log file
LAST_LOG_DATE_CHECKED=""       # Used to track if we need to create a new log file

#==============================================================================
# LOG FILE MANAGEMENT FUNCTIONS
#==============================================================================
# Functions for creating, rotating, and cleaning up log files

#==================================================================
# Function: _delete_old_logs
# Description: Deletes log files older than LOG_RETENTION_DAYS
# Parameters: None
# Returns: None
_delete_old_logs() {
    if [[ "${LOG_ROTATION_ENABLED:-false}" != "true" || -z "$LOG_DIR" || -z "$LOG_FILE_BASENAME" || -z "$LOG_RETENTION_DAYS" || "$LOG_RETENTION_DAYS" -lt 1 ]]; then
        return
    fi
    
    local retention_days_for_find=$((LOG_RETENTION_DAYS - 1))
    [[ "$retention_days_for_find" -lt 0 ]] && retention_days_for_find=0
    
    if [[ ! -d "$LOG_DIR" ]]; then
        return
    fi
    
    local old_log_count
    old_log_count=$(find "$LOG_DIR" -name "${LOG_FILE_BASENAME}_*.log" -type f -mtime +"$retention_days_for_find" -print 2>/dev/null | wc -l)
    
    if [[ "$old_log_count" -gt 0 ]]; then
        find "$LOG_DIR" -name "${LOG_FILE_BASENAME}_*.log" -type f -mtime +"$retention_days_for_find" -delete
    fi
}
export -f _delete_old_logs
#=================================================================

#==============================================================================
# Function: _ensure_log_file_updated
# Description: Creates or updates the log file path based on current date
# Parameters: None
# Returns: None
# Side Effects: Updates CURRENT_LOG_FILE_PATH and LAST_LOG_DATE_CHECKED globals
#==============================================================================
_ensure_log_file_updated() {
    if [[ "${LOG_ROTATION_ENABLED:-false}" != "true" || -z "$LOG_DIR" || -z "$LOG_FILE_BASENAME" ]]; then
        CURRENT_LOG_FILE_PATH=""
        return
    fi
    
    local current_date; current_date=$(date +%F)
    if [[ "$current_date" != "$LAST_LOG_DATE_CHECKED" || ! -f "$CURRENT_LOG_FILE_PATH" ]]; then
        LAST_LOG_DATE_CHECKED="$current_date"
        CURRENT_LOG_FILE_PATH="${LOG_DIR}/${LOG_FILE_BASENAME}_${current_date}.log"
    
        # Create log directory - succeed or exit
        mkdir -p "$LOG_DIR"
        local mkdir_exit_code=$?
        if [[ $mkdir_exit_code -ne 0 ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - CRITICAL WATCHER: Failed to create log directory '$LOG_DIR'. Check permissions and filesystem. Exiting." >&2
            exit 1
        fi
        _delete_old_logs
    fi
}
export -f _ensure_log_file_updated
_ensure_log_file_updated # Initial setup call

#==============================================================================
# Function: _log_to_current_file
# Description: File-only logging helper for logging_utils.sh emoji-based functions
# Parameters:
#   $1: Required level number (LOG_LEVEL_DEBUG, LOG_LEVEL_INFO, etc.)
#   $2: Prefix string (includes emoji)
#   $3: Message string
# Returns: None
# Side Effects: Writes to CURRENT_LOG_FILE_PATH if file logging is enabled
# Dev Note: makes heavy use of shellcheck disable=SC2317 to prevent false positives, 
# since this is a helper for the emoji-based logging system in loggin_utils.sh.
#==============================================================================
_log_to_current_file() {
    # shellcheck disable=SC2317
    local required_level_num="$1"
    # shellcheck disable=SC2317
    local prefix="$2" 
    # shellcheck disable=SC2317
    local message="$3"

    # Only log if file logging is enabled
    # shellcheck disable=SC2317
    if [[ "${LOG_ROTATION_ENABLED:-false}" != "true" ]]; then
        return
    fi
    
    # Ensure log file path is current (handles rotation)
    # This function sets CURRENT_LOG_FILE_PATH in the current shell
    # shellcheck disable=SC2317
    _ensure_log_file_updated
    
    # Now check if CURRENT_LOG_FILE_PATH was successfully set by _ensure_log_file_updated
    # shellcheck disable=SC2317
    if [[ -z "$CURRENT_LOG_FILE_PATH" ]]; then
        return
    fi
    
    # Convert numeric level to severity label for file
    # shellcheck disable=SC2317
    local severity_label
    # shellcheck disable=SC2317
    case "$required_level_num" in
        "$LOG_LEVEL_DEBUG") severity_label="DEBUG:" ;;
        "$LOG_LEVEL_INFO")  severity_label="" ;;
        "$LOG_LEVEL_WARN")  severity_label="WARN:" ;;
        "$LOG_LEVEL_ERROR") severity_label="ERROR:" ;;
        *)                  severity_label="LOG:" ;;
    esac
    
    # Construct file log message
    # shellcheck disable=SC2317
    local file_log_message
    # shellcheck disable=SC2317
    file_log_message="${prefix} $(date '+%Y-%m-%d %H:%M:%S') - ${severity_label} ${message}"
    
    # Write to file with flock protection (same pattern as existing code)
    # Use flock to ensure safe concurrent writes
    # shellcheck disable=SC2317
    if command -v flock >/dev/null 2>&1; then
        exec 200>>"$CURRENT_LOG_FILE_PATH"
        if flock -w 0.5 200; then
            echo "$file_log_message" >&200
            flock -u 200
        else
            echo "[FLOCK_TIMEOUT] $file_log_message" >> "$CURRENT_LOG_FILE_PATH"
        fi
        exec 200>&-
    else
        echo "$file_log_message" >> "$CURRENT_LOG_FILE_PATH"
    fi
}
export -f _log_to_current_file

# Define local log function for jellymac.sh using the modern emoji-based system
# shellcheck disable=SC2317
log_debug() { log_debug_event "JellyMac" "$1"; }


# --- Single Instance Lock ---
LOCK_FILE="${STATE_DIR}/jellymac.sh.lock"
_acquire_lock() {
    log_debug_event "JellyMac" "Attempting to acquire instance lock: $LOCK_FILE"
    if [[ ! -d "$STATE_DIR" ]]; then
        if ! mkdir -p "$STATE_DIR"; then
            # Use primitive echo for critical startup error
            echo "$(date '+%Y-%m-%d %H:%M:%S') - CRITICAL WATCHER: Failed to create state dir '$STATE_DIR'. Cannot acquire lock. Exiting." >&2
            exit 1;
        fi
        log_user_info "JellyMac" "State directory '$STATE_DIR' created."
    fi

    # 'flock' command availability is checked by perform_system_health_checks earlier.
    # If flock is not available, find_executable in doctor_utils.sh would have exited.
    exec 201>"$LOCK_FILE" # Open file descriptor 201 for flock.
    if ! flock -n 201; then 
        log_error_event "JellyMac" "Another instance of jellymac.sh is already running (Lock file: '$LOCK_FILE'). Exiting."
        exit 1
    fi
    log_debug_event "JellyMac" "Instance lock acquired: $LOCK_FILE"
}
_release_lock() {
    # shellcheck disable=SC2317
    log_debug_event "JellyMac" "Releasing instance lock: $LOCK_FILE"
    # shellcheck disable=SC2317
    if [[ -n "$LOCK_FILE" ]]; then 
        exec 201>&- # Close file descriptor
        # rm -f "$LOCK_FILE" # Optional: remove lock file, flock releases advisory lock anyway
        log_debug_event "JellyMac" "Instance lock released."
    fi
}

# --- Desktop Notification Function (macOS Only) ---
# Now handled by send_desktop_notification() in common_utils.sh

# --- Caffeinate and Process Management ---
CAFFEINATE_PROCESS_ID=""
CAFFEINATE_CMD_PATH="" 
_ACTIVE_PROCESSOR_INFO_STRING="" 
LAST_CLIPBOARD_CONTENT_YOUTUBE=""
LAST_CLIPBOARD_CONTENT_MAGNET=""
PBPASTE_CMD="" 
_SHUTDOWN_IN_PROGRESS=""

# --- YouTube Queue Tracking ---
_YOUTUBE_PROCESSING_ACTIVE=""             # Flag to track if YouTube is being processed in foreground
_ACTIVE_YOUTUBE_URL=""                    # Track the currently downloading YouTube URL
_ACTIVE_YOUTUBE_PID=""                    # Track the PID of active YouTube download

# --- Torrent Cleanup Tracking ---
last_torrent_cleanup=0                    # Timestamp of last cleanup (Unix timestamp) 

# --- Caffeinate Management Functions ---
# Function: _stop_caffeinate_if_running
# Description: Stops caffeinate if it's currently running
# Parameters: None
# Returns: None
_stop_caffeinate_if_running() {
    if [[ -n "$CAFFEINATE_PROCESS_ID" ]] && ps -p "$CAFFEINATE_PROCESS_ID" >/dev/null 2>&1; then
        log_debug_event "JellyMac" "Stopping caffeinate (PID: $CAFFEINATE_PROCESS_ID)..."
        kill "$CAFFEINATE_PROCESS_ID" 2>/dev/null || log_warn_event "JellyMac" "Failed to stop caffeinate process"
        CAFFEINATE_PROCESS_ID=""
    fi
}

# Function: _start_caffeinate_if_needed
# Description: Starts caffeinate if not already running and if we have active processes
# Parameters: None
# Returns: None
_start_caffeinate_if_needed() {
    # Only proceed if we're on macOS and caffeinate is available
    if [[ "$(uname)" != "Darwin" || -z "$CAFFEINATE_CMD_PATH" ]]; then
        return
    fi

    # Check if we have any active processes that need caffeinate
    local needs_caffeinate="false"  # Use string instead of boolean for Bash 3.2

    # Check for active YouTube download
    if [[ "$_YOUTUBE_PROCESSING_ACTIVE" == "true" ]]; then
        needs_caffeinate="true"
    fi

    # Check for active media processors
    if [[ -n "$_ACTIVE_PROCESSOR_INFO_STRING" ]]; then
        needs_caffeinate="true"
    fi

    # Start caffeinate if needed and not already running
    if [[ "$needs_caffeinate" == "true" ]]; then
        if [[ -z "$CAFFEINATE_PROCESS_ID" ]] || ! ps -p "$CAFFEINATE_PROCESS_ID" >/dev/null 2>&1; then
            log_debug_event "JellyMac" "Starting caffeinate for active processes..."
            "$CAFFEINATE_CMD_PATH" -i &
            CAFFEINATE_PROCESS_ID=$!
            if ps -p "$CAFFEINATE_PROCESS_ID" >/dev/null 2>&1; then
                log_debug_event "JellyMac" "Caffeinate started with PID: $CAFFEINATE_PROCESS_ID"
            else
                log_warn_event "JellyMac" "Failed to start caffeinate process"
                CAFFEINATE_PROCESS_ID=""
            fi
        fi
    else
        # No active processes need caffeinate, stop it if running
        _stop_caffeinate_if_running
    fi
}

#==============================================================================
# PROCESS MANAGEMENT FUNCTIONS
#==============================================================================
# Functions for managing child processes, cleanup operations, and graceful exit

# Function: _cleanup_jellymac_temp_files
# Description: Cleans up any temporary files created by the watcher
# Parameters: None
# Returns: None
_cleanup_jellymac_temp_files() {
    #shellcheck disable=SC2317
    log_debug_event "JellyMac" "Cleaning up jellymac.sh specific temp files..."
    #shellcheck disable=SC2317
    log_debug_event "JellyMac" "No specific jellymac.sh temp files to clean in this version beyond what functions manage themselves."
}

# Function: graceful_shutdown_and_cleanup
# Description: Main cleanup handler called when script exits (normal or interrupted)
# Parameters: None
# Returns: None (exits the script)
# Note: Registered as a trap for SIGINT, SIGTERM, and EXIT signals
# We make heavy use of shellcheck disable=SC2317 to prevent false positives in shutdown functions
graceful_shutdown_and_cleanup() {
    # Prevent duplicate execution
    #shellcheck disable=SC2317
    if [[ "$_SHUTDOWN_IN_PROGRESS" == "true" ]]; then
        return
    fi
    #shellcheck disable=SC2317
    _SHUTDOWN_IN_PROGRESS="true"
    # shellcheck disable=SC2317
    echo 
    # shellcheck disable=SC2317
    log_user_shutdown "JellyMac" "Exiting JellyMac..." 

    # Handle interrupted YouTube downloads
    # shellcheck disable=SC2317
    if [[ -n "$_ACTIVE_YOUTUBE_URL" && -n "$_ACTIVE_YOUTUBE_PID" ]]; then
        log_user_info "JellyMac" "🔄 Handling interrupted YouTube download..."
        _handle_interrupted_youtube_download
    fi
    
    # Stop caffeinate if running
    # shellcheck disable=SC2317
    _stop_caffeinate_if_running
    
    #shellcheck disable=SC2317
    log_debug_event "JellyMac" "Cleaning up any active child processes..."
    #shellcheck disable=SC2317
    local old_ifs="$IFS" 
    #shellcheck disable=SC2317
    IFS='|'
    # shellcheck disable=SC2317
    local script_name_killed 
    #shellcheck disable=SC2317
    set -f 
    # Bash 3.2 compatible: Use explicit string replacement then array assignment
    # shellcheck disable=SC2317
    local processor_string_modified
    #shellcheck disable=SC2317
    processor_string_modified="${_ACTIVE_PROCESSOR_INFO_STRING//|||/|}"
    # shellcheck disable=SC2317
    local old_ifs_gsac="$IFS" # Store original IFS
    # shellcheck disable=SC2317
    IFS='|'                   # Set IFS to the delimiter
    # shellcheck disable=SC2317
    set -f                    # Disable globbing
    # shellcheck disable=SC2162,SC2317,SC2086
    set -- $processor_string_modified # Bash 3.2 compatible: use set -- instead of read -r -a (intentional word splitting)
    # shellcheck disable=SC2317
    p_info_array=("$@")       # Copy positional parameters to array
    # shellcheck disable=SC2317
    set +f                    # Re-enable globbing
    # shellcheck disable=SC2317
    IFS="$old_ifs_gsac"       # Restore original IFS
    # shellcheck disable=SC2317
    IFS="$old_ifs"
    # shellcheck disable=SC2317
    local entry_count=${#p_info_array[@]}

    # shellcheck disable=SC2317
    if [[ $entry_count -gt 0 && $((entry_count % 4)) -eq 0 ]]; then
        for ((idx=0; idx<entry_count; idx+=4)); do
            local pid_to_kill="${p_info_array[idx]}"
            script_name_killed="$(basename "${p_info_array[idx+1]}")" 
            local item_killed="${p_info_array[idx+2]}"
            if [[ -n "$pid_to_kill" ]] && ps -p "$pid_to_kill" > /dev/null; then
                log_user_info "JellyMac" "  Terminating PID $pid_to_kill ($script_name_killed for '${item_killed:0:50}...')..."
                kill "$pid_to_kill" 2>/dev/null || log_warn_event "JellyMac" "  Failed to send SIGTERM to PID $pid_to_kill."
            fi
        done
    elif [[ -n "$_ACTIVE_PROCESSOR_INFO_STRING" ]]; then 
        log_warn_event "JellyMac" "Could not parse _ACTIVE_PROCESSOR_INFO_STRING for child process cleanup: '$_ACTIVE_PROCESSOR_INFO_STRING'"
    fi
    
    # shellcheck disable=SC2317
    _release_lock 
    
    # shellcheck disable=SC2317
    if command -v _cleanup_common_utils_temp_files >/dev/null 2>&1; then
        _cleanup_common_utils_temp_files 
    fi
    # shellcheck disable=SC2317
    if [[ -f "${STATE_DIR}/youtube_queue.txt" ]]; then
        log_debug_event "JellyMac" "YouTube queue file exists. Retaining for next session."
    fi
    # shellcheck disable=SC2317
    _cleanup_jellymac_temp_files   

    # shellcheck disable=SC2317
    printf "\033]0;%s\007" "${SHELL##*/}" 
    # shellcheck disable=SC2317
    log_user_shutdown "JellyMac" "JellyMac shutdown complete. See ya next time! 👋" 
    # shellcheck disable=SC2317
    exit 0 
}
trap graceful_shutdown_and_cleanup SIGINT SIGTERM EXIT

# Function: manage_active_processors
# Description: Checks status of all running child processes and updates their tracking
# Parameters: None
# Returns: None
# Side Effects: Updates _ACTIVE_PROCESSOR_INFO_STRING, cleans up completed tasks
# Dev Note: We use | and ||| as delimiters in _ACTIVE_PROCESSOR_INFO_STRING ensure no conflicts with parsed vars (sanitize input)
manage_active_processors() {
    [[ -z "$_ACTIVE_PROCESSOR_INFO_STRING" ]] && return 

    local still_running_string="" 
    local old_ifs="$IFS"
    IFS='|'
    set -f  # Disable globbing for safety
    local processor_string_modified
    processor_string_modified="${_ACTIVE_PROCESSOR_INFO_STRING//|||/|}"
    local p_info_array=()  # Initialize empty array for Bash 3.2
    
    # Bash 3.2 compatible array population
    local old_ifs_map="$IFS"
    IFS='|'
    set -f
    # shellcheck disable=SC2086
    set -- $processor_string_modified # Bash 3.2 compatible: use set -- instead of read -r -a (intentional word splitting)
    p_info_array=("$@") # Copy positional parameters to array
    set +f
    IFS="$old_ifs_map"
    set +f 
    IFS="$old_ifs"
    
    # Get array length in Bash 3.2 compatible way
    local entry_count=0
    for _ in "${p_info_array[@]}"; do
        entry_count=$((entry_count + 1))
    done

    if [[ $entry_count -eq 0 || $((entry_count % 4)) -ne 0 ]]; then
        if [[ -n "$_ACTIVE_PROCESSOR_INFO_STRING" ]]; then 
             log_warn_event "JellyMac" "manage_active_processors: _ACTIVE_PROCESSOR_INFO_STRING ('$_ACTIVE_PROCESSOR_INFO_STRING') is malformed. Clearing."
        fi
        _ACTIVE_PROCESSOR_INFO_STRING="" 
        _start_caffeinate_if_needed  # Update caffeinate state after clearing
        return
    fi
    
    # Process entries in groups of 4 (Bash 3.2 compatible)
    local idx=0
    while [[ $idx -lt $entry_count ]]; do
        local pid="${p_info_array[$idx]}"
        local script_full_path="${p_info_array[$((idx + 1))]}"
        local item_identifier="${p_info_array[$((idx + 2))]}" 
        local ts_launch="${p_info_array[$((idx + 3))]}"
        local script_basename
        script_basename=$(basename "$script_full_path")

        if ps -p "$pid" > /dev/null; then 
            # Bash 3.2 compatible string concatenation
            if [[ -n "$still_running_string" ]]; then 
                still_running_string="${still_running_string}|||"
            fi 
            still_running_string="${still_running_string}${pid}|||${script_full_path}|||${item_identifier}|||${ts_launch}"
        else 
            local exit_status=255 
            if wait "$pid" >/dev/null 2>&1; then 
                 exit_status=$?
            else
                 log_debug_event "JellyMac" "manage_active_processors: wait for PID $pid failed or already reaped. Assuming finished."
            fi
            log_debug_event "JellyMac" "✅ Processor PID $pid ($script_basename for '${item_identifier:0:70}...') completed. Exit status: $exit_status."
        fi
        idx=$((idx + 4))
    done
    
    _ACTIVE_PROCESSOR_INFO_STRING="$still_running_string"
    
    _stop_caffeinate_if_running
}

# Function: is_item_being_processed
# Description: Checks if a specific item is already being processed by any child process
# Parameters:
#   $1 - Full path to the item to check
# Returns:
#   0 - Item is being processed
#   1 - Item is not being processed
is_item_being_processed() {
    local item_to_check="$1"
    [[ -z "$_ACTIVE_PROCESSOR_INFO_STRING" ]] && return 1 

    local old_ifs="$IFS"; IFS='|'
    set -f 
    \
    local processor_string_modified
    processor_string_modified="${_ACTIVE_PROCESSOR_INFO_STRING//|||/|}"
    local p_info_array=() # Initialize for Bash 3.2
    local old_ifs_iibp="$IFS"
    IFS='|'
    set -f
    # shellcheck disable=SC2086
    set -- $processor_string_modified # Bash 3.2 compatible: use set -- instead of read -r -a (intentional word splitting)
    p_info_array=("$@") # Copy positional parameters to array
    set +f
    IFS="$old_ifs_iibp"
    set +f 
    IFS="$old_ifs"
    local entry_count=${#p_info_array[@]}

    if [[ $entry_count -eq 0 || $((entry_count % 4)) -ne 0 ]]; then
        log_debug_event "JellyMac" "is_item_being_processed: malformed _ACTIVE_PROCESSOR_INFO_STRING. Checked for '$item_to_check'."
        return 1 
    fi
    for ((idx=0; idx<entry_count; idx+=4)); do
        if [[ "${p_info_array[idx+2]}" == "$item_to_check" ]]; then
            return 0 
        fi
    done
    return 1 
}

#==============================================================================
# MEDIA DETECTION AND PROCESSING FUNCTIONS
#==============================================================================
# Functions for detecting and processing media from various sources

#==============================================================================
# Function: is_youtube_url_in_history
# Description: Checks if a YouTube URL exists in download archive or history
# Parameters:
#   $1 - YouTube URL to check
# Returns:
#   0 - URL found in history/archive (duplicate)
#   1 - URL not found (new content)
#==============================================================================
is_youtube_url_in_history() {
    local url="$1"
    
    # Check download archive first
    if [[ -n "${DOWNLOAD_ARCHIVE_YOUTUBE:-}" && -f "${DOWNLOAD_ARCHIVE_YOUTUBE}" ]]; then
        # Extract video ID and check archive
        local video_id=""
        case "$url" in
            *"watch?v="*)
                video_id="${url#*watch?v=}"
                video_id="${video_id%%&*}"
                ;;
            *"youtu.be/"*)
                video_id="${url#*youtu.be/}"
                video_id="${video_id%%\?*}"
                ;;
        esac
        
        if [[ -n "$video_id" ]] && grep -q "youtube $video_id" "$DOWNLOAD_ARCHIVE_YOUTUBE" 2>/dev/null; then
            return 0  # Found in archive
        fi
    fi
    
    # Check history file
    if [[ -n "${HISTORY_FILE:-}" && -f "${HISTORY_FILE}" ]]; then
        if grep -Fq "$url" "$HISTORY_FILE" 2>/dev/null; then
            return 0  # Found in history
        fi
    fi
    
    return 1  # Not found
}

#==============================================================================
# Function: check_and_resume_youtube_queue
# Description: Checks for existing YouTube queue on startup and resumes automatically
# Parameters: None
# Returns: None
# Side Effects: Processes existing queue if found
#==============================================================================
check_and_resume_youtube_queue() {
    local queue_file="${STATE_DIR}/youtube_queue.txt"
    
    if [[ ! -f "$queue_file" ]]; then
        log_debug_event "JellyMac" "No existing YouTube queue found on startup."
        return 0
    fi
    
    # Count non-empty lines in queue
    local queue_count
    queue_count=$(grep -c . "$queue_file" 2>/dev/null || echo "0")
    
    if [[ "$queue_count" -eq 0 ]]; then
        log_debug_event "JellyMac" "YouTube queue file exists but is empty. Removing."
        rm -f "$queue_file"
        return 0
    fi
    
    log_user_info "JellyMac" "📋 Found $queue_count queued YouTube downloads from previous session"
    log_user_info "JellyMac" "🎬 Auto-resuming YouTube queue..."
    
    # Process the queue
    if command -v _process_youtube_queue >/dev/null 2>&1; then
        _process_youtube_queue
    else
        log_warn_event "JellyMac" "Queue processing function not available. Cannot resume queue."
        rm -f "$queue_file"
    fi
}

#==============================================================================
# Function: _handle_interrupted_youtube_download
# Description: Handles cleanup and re-queuing of interrupted YouTube downloads
# Parameters: None
# Returns: None
# Side Effects: Cleans up partial files, removes from archive, re-queues URL
# Dev note: We make heavy use of shellcheck disable=SC2317 to prevent false positives
#==============================================================================
_handle_interrupted_youtube_download() {
    # shellcheck disable=SC2317
    log_debug_event "JellyMac" "Cleaning up interrupted YouTube download: ${_ACTIVE_YOUTUBE_URL:0:60}..."
    
    # shellcheck disable=SC2317
    # 1. Terminate the download process if still running
    if [[ -n "$_ACTIVE_YOUTUBE_PID" ]] && ps -p "$_ACTIVE_YOUTUBE_PID" >/dev/null 2>&1; then
        log_debug_event "JellyMac" "Terminating YouTube download process (PID: $_ACTIVE_YOUTUBE_PID)..."
        kill "$_ACTIVE_YOUTUBE_PID" 2>/dev/null || true
        sleep 1
        # Force kill if still running
        if ps -p "$_ACTIVE_YOUTUBE_PID" >/dev/null 2>&1; then
            kill -9 "$_ACTIVE_YOUTUBE_PID" 2>/dev/null || true
        fi
    fi
    
    # shellcheck disable=SC2317
    # 2. Clean up partial download files in LOCAL_DIR_YOUTUBE
    if [[ -n "${LOCAL_DIR_YOUTUBE:-}" && -d "${LOCAL_DIR_YOUTUBE}" ]]; then
        log_debug_event "JellyMac" "Cleaning up partial YouTube files in: $LOCAL_DIR_YOUTUBE"
        find "${LOCAL_DIR_YOUTUBE}" -maxdepth 1 \( -name "*.part" -o -name "*.tmp" -o -name "*.ytdl" \) -type f -delete 2>/dev/null || true
    fi
    
    # shellcheck disable=SC2317
    # 3. Remove from download archive to allow retry
    if [[ -n "${DOWNLOAD_ARCHIVE_YOUTUBE:-}" && -f "${DOWNLOAD_ARCHIVE_YOUTUBE}" && -n "$_ACTIVE_YOUTUBE_URL" ]]; then
        _remove_url_from_youtube_archive "$_ACTIVE_YOUTUBE_URL"
    fi
    
    # shellcheck disable=SC2317
    # 4. Add back to queue for retry on next startup
    if [[ -n "$_ACTIVE_YOUTUBE_URL" ]]; then
        local queue_file="${STATE_DIR}/youtube_queue.txt"
        # Check if URL is already in queue to avoid duplicates
        if ! grep -Fxq "$_ACTIVE_YOUTUBE_URL" "$queue_file" 2>/dev/null; then
            echo "$_ACTIVE_YOUTUBE_URL" >> "$queue_file"
            log_user_info "JellyMac" "📋 Re-queued interrupted download for next startup: ${_ACTIVE_YOUTUBE_URL:0:60}..."
        fi
    fi
    
    # shellcheck disable=SC2317
    # 5. Clear tracking variables
    _ACTIVE_YOUTUBE_URL=""
    # shellcheck disable=SC2317
    _ACTIVE_YOUTUBE_PID=""
}

#==============================================================================
# Function: _remove_url_from_youtube_archive
# Description: Removes a YouTube URL from the download archive
# Parameters:
#   $1 - YouTube URL to remove from archive
# Returns: None
#==============================================================================
_remove_url_from_youtube_archive() {
    # shellcheck disable=SC2317
    local url_to_remove="$1"
    
    # shellcheck disable=SC2317
    if [[ -z "$url_to_remove" || -z "${DOWNLOAD_ARCHIVE_YOUTUBE:-}" || ! -f "${DOWNLOAD_ARCHIVE_YOUTUBE}" ]]; then
        return
    fi
    
    # shellcheck disable=SC2317
    # Extract video ID from URL using Bash 3.2 compatible method
    local video_id=""
    # shellcheck disable=SC2317
    case "$url_to_remove" in
        *"watch?v="*)
            video_id="${url_to_remove#*watch?v=}"  # Remove everything before "watch?v="
            video_id="${video_id%%&*}"             # Remove everything after first "&"
            ;;
        *"youtu.be/"*)
            video_id="${url_to_remove#*youtu.be/}" # Remove everything before "youtu.be/"
            video_id="${video_id%%\?*}"            # Remove everything after first "?"
            ;;
    esac
    
    # shellcheck disable=SC2317
    if [[ -n "$video_id" ]]; then
        log_debug_event "JellyMac" "Removing video ID from archive: $video_id"
        # Create backup and remove entry
        if cp "${DOWNLOAD_ARCHIVE_YOUTUBE}" "${DOWNLOAD_ARCHIVE_YOUTUBE}.bak" 2>/dev/null; then
            if grep -v "youtube $video_id" "${DOWNLOAD_ARCHIVE_YOUTUBE}.bak" > "${DOWNLOAD_ARCHIVE_YOUTUBE}" 2>/dev/null; then
                log_debug_event "JellyMac" "Successfully removed $video_id from download archive"
            else
                log_warn_event "JellyMac" "Failed to update download archive"
                # Restore backup if update failed
                mv "${DOWNLOAD_ARCHIVE_YOUTUBE}.bak" "${DOWNLOAD_ARCHIVE_YOUTUBE}" 2>/dev/null || true
            fi
            # Clean up backup file
            rm -f "${DOWNLOAD_ARCHIVE_YOUTUBE}.bak" 2>/dev/null || true
        else
            log_warn_event "JellyMac" "Failed to create backup of download archive"
        fi
    else
        log_warn_event "JellyMac" "Could not extract video ID from URL: ${url_to_remove:0:100}..."
    fi
}

# Function: _check_clipboard_youtube
# Description: Checks clipboard for YouTube URLs and processes them if found
# Parameters: None
# Returns: None
# Side Effects: Updates LAST_CLIPBOARD_CONTENT_YOUTUBE
_check_clipboard_youtube() {
    if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" != "true" || -z "$PBPASTE_CMD" ]]; then return; fi
    local current_cb_content
    current_cb_content=$("$PBPASTE_CMD" 2>/dev/null || echo "CLIPBOARD_READ_ERROR")
    if [[ "$current_cb_content" == "CLIPBOARD_READ_ERROR" ]]; then
        log_warn_event "JellyMac" "Failed to read clipboard for YouTube monitoring. 'pbpaste' might have failed."
        return
    fi

    if [[ "$current_cb_content" != "$LAST_CLIPBOARD_CONTENT_YOUTUBE" && -n "$current_cb_content" ]]; then
        LAST_CLIPBOARD_CONTENT_YOUTUBE="$current_cb_content" 
        local trimmed_cb; trimmed_cb="$(echo -E "${current_cb_content}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        
        case "$trimmed_cb" in
            https://www.youtube.com/watch\?v=*|https://youtu.be/*|https://www.youtube.com/playlist\?list=*)
                # Check if this URL is already being processed or queued
                if is_item_being_processed "$trimmed_cb"; then
                    log_user_info "JellyMac" "YouTube URL already being processed: '${trimmed_cb:0:70}...'"
                    return
                fi
                
                # Check history BEFORE playing sound - early exit for duplicates
                if is_youtube_url_in_history "$trimmed_cb"; then
                    log_user_info "JellyMac" "📋 YouTube URL found in history - skipping to prevent duplicate download"
                    log_user_info "JellyMac" "URL: '${trimmed_cb:0:70}...'"
                    return
                fi
                
                # Check if this is a playlist URL
                if [[ "$trimmed_cb" == *"playlist?list="* ]]; then
                    log_user_info "JellyMac" "📋 Detected YouTube playlist: '${trimmed_cb:0:70}...'"
                    play_sound_notification "input_detected" "$_WATCHER_LOG_PREFIX"
                    log_user_info "JellyMac" "🚧 Playlist processing not yet implemented - coming soon!"
                    return
                fi
                
                log_user_info "JellyMac" "📺 Detected YouTube URL: '${trimmed_cb:0:70}...'"
                # Sound only plays for genuinely new URLs
                play_sound_notification "input_detected" "$_WATCHER_LOG_PREFIX" 
                
                # Check if YouTube processing is already active
                if [[ "$_YOUTUBE_PROCESSING_ACTIVE" == "true" ]]; then
                    # Add to queue instead of processing immediately
                    _add_youtube_to_queue "$trimmed_cb"
                    return
                fi
                
                # No active processing - start foreground processing
                _YOUTUBE_PROCESSING_ACTIVE="true"
                _ACTIVE_YOUTUBE_URL="$trimmed_cb"  # NEW: Track active URL
                log_user_info "JellyMac" "🎬 Starting YouTube download..."
                log_user_info "JellyMac" "💡 You may continue copying links - they'll be queued automatically!"
                
                # Start caffeinate for YouTube download
                _start_caffeinate_if_needed
                
                # Fork background monitoring loop
                {
                    local last_torrent_cleanup_subshell="$last_torrent_cleanup" # Initialize from global for this subshell's timer
                    while [[ "$_YOUTUBE_PROCESSING_ACTIVE" == "true" ]]; do
                        manage_active_processors
                        
                        # Check for new YouTube links to queue (but don't process)
                        if [[ -n "$PBPASTE_CMD" ]]; then 
                            _check_clipboard_youtube_for_queue
                            _check_clipboard_magnet
                        fi
                        process_drop_folder
                        
                        # Time-based torrent cleanup
                        if [[ "${TRANSMISSION_AUTO_CLEANUP:-false}" == "true" ]]; then
                            current_time=$(date +%s)
                            if [[ $((current_time - last_torrent_cleanup_subshell)) -ge 180 ]]; then # Use subshell's timer
                                cleanup_completed_torrents "JellyMac" # Log source remains JellyMac for consistency
                                last_torrent_cleanup_subshell=$current_time # Update subshell's timer
                            fi
                        fi
                        
                        sleep "${MAIN_LOOP_SLEEP_INTERVAL:-2}"
                    done
                } &
                local background_loop_pid=$!
                
                # Process YouTube in foreground with full output visibility
                "$HANDLE_YOUTUBE_SCRIPT" "$trimmed_cb" "${YTDLP_OPTS[@]}" &
                _ACTIVE_YOUTUBE_PID=$!

                if wait "$_ACTIVE_YOUTUBE_PID"; then
                    log_user_info "JellyMac" "✅ YouTube download complete"
                else
                    log_warn_event "JellyMac" "❌ YouTube download failed: '${trimmed_cb:0:60}...'"
                    send_desktop_notification "JellyMac: YouTube Error" "Failed: ${trimmed_cb:0:60}..." "Basso"
                    log_warn_event "JellyMac" "Close JellyMac, run brew update && brew upgrade yt-dlp, restart JellyMac and try again."
                fi

                # Clear tracking variables after completion
                _ACTIVE_YOUTUBE_URL=""
                _ACTIVE_YOUTUBE_PID=""
                
                # Process any queued downloads
                _process_youtube_queue
                
                # Clean up background monitoring
                _YOUTUBE_PROCESSING_ACTIVE=""
                kill "$background_loop_pid" 2>/dev/null || true
                wait "$background_loop_pid" 2>/dev/null || true
                
                # Update caffeinate state
                _start_caffeinate_if_needed
                
                ;;
        esac
    fi
}

# Function: _check_clipboard_magnet
# Description: Checks clipboard for magnet links and processes them if found
# Parameters: None
# Returns: None
# Side Effects: Updates LAST_CLIPBOARD_CONTENT_MAGNET
_check_clipboard_magnet() {
    if [[ "${ENABLE_CLIPBOARD_MAGNET:-false}" != "true" || -z "$PBPASTE_CMD" ]]; then return; fi
    local current_cb_content
    current_cb_content=$("$PBPASTE_CMD" 2>/dev/null || echo "CLIPBOARD_READ_ERROR")
    if [[ "$current_cb_content" == "CLIPBOARD_READ_ERROR" ]]; then
        log_warn_event "JellyMac" "Failed to read clipboard for magnet link monitoring. 'pbpaste' might have failed."
        return
    fi

    if [[ "$current_cb_content" != "$LAST_CLIPBOARD_CONTENT_MAGNET" && -n "$current_cb_content" ]]; then
        LAST_CLIPBOARD_CONTENT_MAGNET="$current_cb_content" 
        local trimmed_cb; trimmed_cb="$(echo -E "${current_cb_content}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        
        case "$trimmed_cb" in
            magnet:\?xt=urn:btih:*)
                # Extract magnet hash for archive checking
                MAGNET_HASH="${trimmed_cb#*xt=urn:btih:}"
                MAGNET_HASH="${MAGNET_HASH%%&*}"  # Remove any additional parameters
                MAGNET_HASH="${MAGNET_HASH:0:40}" # Ensure exactly 40 chars
                
                # Check magnet download archive to prevent duplicates
                if [[ -n "${DOWNLOAD_ARCHIVE_MAGNET:-}" ]]; then
                    if [[ -f "$DOWNLOAD_ARCHIVE_MAGNET" ]] && grep -q "^magnet $MAGNET_HASH$" "$DOWNLOAD_ARCHIVE_MAGNET" 2>/dev/null; then
                        log_user_info "JellyMac" "🔄 Magnet link already processed previously (found in archive)"
                        log_user_info "JellyMac" "Hash: $MAGNET_HASH"
                        log_user_info "JellyMac" "Skipping duplicate download to prevent bandwidth waste and file conflicts"
                        return
                    fi
                fi
                
                # Check history file BEFORE playing sound
                if [[ -n "${HISTORY_FILE:-}" && -f "${HISTORY_FILE}" ]]; then
                    if grep -Fq "$MAGNET_HASH" "$HISTORY_FILE" 2>/dev/null; then
                        log_user_info "JellyMac" "🔄 Magnet link found in history - skipping to prevent duplicate download"
                        log_user_info "JellyMac" "Hash: $MAGNET_HASH"
                        return
                    fi
                fi
                
                log_user_info "JellyMac" "🧲 Detected Magnet URL: '${trimmed_cb:0:70}...'"
                # Sound only plays for genuinely new magnet links
                play_sound_notification "input_detected" "$_WATCHER_LOG_PREFIX" 

                # Process magnet in background (non-blocking)
                log_user_info "JellyMac" "🚀 Processing magnet link (background)..."
                
                # Launch magnet handler in background
                {
                    if "$HANDLE_MAGNET_SCRIPT" "$trimmed_cb"; then
                        log_user_info "JellyMac" "✅ Magnet link sent to Transmission: '${trimmed_cb:0:60}...'"
                        send_desktop_notification "JellyMac: Magnet Added" "Sent to Transmission: ${trimmed_cb:0:50}..."
                    else
                        log_warn_event "JellyMac" "❌ Failed to process magnet link: '${trimmed_cb:0:60}...'"
                        send_desktop_notification "JellyMac: Magnet Error" "Failed: ${trimmed_cb:0:50}..." "Basso"
                    fi
                } &
                
                log_user_info "JellyMac" "💡 Magnet processing continues in background - you can keep adding links!"
                ;;
        esac
    fi
}

# Function: process_drop_folder
# Description: Scans the DROP_FOLDER for new media files/folders and processes them
# Parameters: None
# Returns: None
# Side Effects: Launches child processes for media processing, updates _ACTIVE_PROCESSOR_INFO_STRING
process_drop_folder() {
    if [[ -z "$DROP_FOLDER" || ! -d "$DROP_FOLDER" ]]; then
        log_warn_event "JellyMac" "Drop Folder ('${DROP_FOLDER:-N/A}') not configured or found. Skipping scan."
        return
    fi
    if [[ "${_LAST_DROP_SCAN_HAD_ITEMS:-false}" == "true" ]] || [[ $(( $(date +%s) % 300 )) -eq 0 ]]; then
    log_debug_event "JellyMac" "Scanning Drop Folder: $DROP_FOLDER"
    fi 
    local items_processed=0
    local find_results_file 
    if [[ ! -d "$STATE_DIR" ]]; then 
        mkdir -p "$STATE_DIR" || { log_error_event "JellyMac" "Failed to create STATE_DIR '$STATE_DIR' for temp scan file. Cannot scan DROP_FOLDER."; exit 1; }
    fi
    find_results_file=$(mktemp "${STATE_DIR}/.drop_folder_scan.XXXXXX")
    
    find "$DROP_FOLDER" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0 > "$find_results_file"
    
    # Clean up completed processes BEFORE checking for new items
    manage_active_processors 
    
    while IFS= read -r -d $'\0' item_path; do
        [[ -z "$item_path" ]] && continue 

        local item_basename; item_basename=$(basename "$item_path")

        # Bash 3.2 compatible: Use case statement instead of regex
        case "$item_basename" in
            .DS_Store|desktop.ini|.stfolder|.stversions|.localized|._*|*.part|*.crdownload)
                continue
                ;;
        esac

        if is_item_being_processed "$item_path"; then
            log_debug_event "JellyMac" "Item '$item_basename' (DROP_FOLDER) already processing. Skipping."; continue
        fi

        log_user_info "JellyMac" "Checking stability for a detected file in your Drop Folder before processing: '$item_basename'"
        if ! wait_for_file_stability "$item_path" "${STABLE_CHECKS_DROP_FOLDER:-3}" "${STABLE_SLEEP_INTERVAL_DROP_FOLDER:-10}"; then
            log_debug_event "JellyMac" "Item '$item_basename' (DROP_FOLDER) not stable. Will re-check next cycle."; continue
        fi
        log_user_info "JellyMac" "✅ Item '$item_basename' (DROP_FOLDER) is stable."

        local old_ifs="$IFS"; IFS='|'
        set -f 
        # Bash 3.2 compatible: Use explicit string replacement then array assignment
        local processor_string_modified
        processor_string_modified="${_ACTIVE_PROCESSOR_INFO_STRING//|||/|}"
        local p_array_temp=() # Initialize for Bash 3.2
        local old_ifs_pdf="$IFS"
        IFS='|'
        set -f
        # shellcheck disable=SC2086
        set -- $processor_string_modified # Bash 3.2 compatible: use set -- instead of read -r -a (intentional word splitting)
        p_array_temp=("$@") # Copy positional parameters to array
        set +f
        IFS="$old_ifs_pdf"
        set +f 
        IFS="$old_ifs"
        local p_count=$(( ${#p_array_temp[@]} / 4 )) 

        if [[ "$p_count" -lt "${MAX_CONCURRENT_PROCESSORS:-2}" ]]; then
            local item_type_for_processor="generic_file"; if [[ -d "$item_path" ]]; then item_type_for_processor="media_folder"; fi
            
            local category_hint_for_processor
            category_hint_for_processor=$(determine_media_category "$item_basename") 
            if [[ "$category_hint_for_processor" != "Movies" && "$category_hint_for_processor" != "Shows" ]]; then
                category_hint_for_processor="" 
            fi

            log_user_info "JellyMac" "🚀 Launching media processor for '$item_basename'. Type: $item_type_for_processor, Hint: '$category_hint_for_processor'"
            play_sound_notification "input_detected" "$_WATCHER_LOG_PREFIX" 

            local ts_launch; ts_launch=$(date +%s)
            "$PROCESS_MEDIA_ITEM_SCRIPT" "$item_type_for_processor" "$item_path" "$category_hint_for_processor" & 
            local child_pid=$! 

            # Bash 3.2 compatible string concatenation
            if [[ -n "$_ACTIVE_PROCESSOR_INFO_STRING" ]]; then 
                _ACTIVE_PROCESSOR_INFO_STRING="${_ACTIVE_PROCESSOR_INFO_STRING}|||"
            fi
            _ACTIVE_PROCESSOR_INFO_STRING="${_ACTIVE_PROCESSOR_INFO_STRING}${child_pid}|||${PROCESS_MEDIA_ITEM_SCRIPT}|||${item_path}|||${ts_launch}"
            
            log_user_info "JellyMac" "🚀 Launched Media Processor (PID $child_pid). Active processors: $((p_count+1))."
            # send_desktop_notification "JellyMac: Processing" "Item: ${item_basename:0:60}..."
            items_processed=$((items_processed + 1))
            
            # Start caffeinate for media processing
            _start_caffeinate_if_needed
        else
            log_warn_event "JellyMac" "🚦 Max concurrent processors (${MAX_CONCURRENT_PROCESSORS:-2}) reached. Deferring processing for '$item_basename' from DROP_FOLDER."
        fi
    done < "$find_results_file" 
    rm -f "$find_results_file" 

    # Track if this scan found items for conditional logging
    if [[ $items_processed -gt 0 ]]; then
        _LAST_DROP_SCAN_HAD_ITEMS="true"
    else
        _LAST_DROP_SCAN_HAD_ITEMS="false"
    fi
    
    # Update caffeinate state at end of function
    _start_caffeinate_if_needed
}

#==============================================================================
# Function: show_startup_banner
# Description: Displays ASCII startup banner if enabled in config
# Parameters: None
# Returns: None
#==============================================================================
show_startup_banner() {
    if [[ "${SHOW_STARTUP_BANNER:-true}" != "true" ]]; then
        return
    fi
    
    echo
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                     J E L L Y M A C                         │"
    echo "│          Automated Media Assistant for macOS                │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
}

# --- Main Initialization & Startup ---

# Perform System Health Checks
health_status=0
perform_system_health_checks || health_status=$? # from doctor_utils.sh

if [[ "$health_status" -eq 1 ]]; then # Critical failure from health check
    log_error_event "JellyMac" "CRITICAL system health checks failed. Exiting."
    exit 1
elif [[ "$health_status" -eq 2 ]]; then # Optional checks failed
    log_warn_event "JellyMac" "Optional system health checks failed. Some features may be degraded or unavailable. Continuing."
fi
# If we reach here, all critical executables are present and critical paths were validated by doctor_utils.sh.

# Acquire Single Instance Lock (AFTER health checks)
_acquire_lock  # Ensure only one instance of JellyMac runs at a time

show_startup_banner  # Call the startup banner function if enabled

log_user_info "JellyMac" "🚀 JellyMac Starting..."
log_user_info "JellyMac" "Version: v0.2.6 ($(date +%Y-%m-%d))"
log_user_info "JellyMac" "JellyMac location: $JELLYMAC_PROJECT_ROOT"
log_debug_event "JellyMac" "   Log Level: ${LOG_LEVEL:-INFO} (Effective Syslog Level: $SCRIPT_CURRENT_LOG_LEVEL)"
if [[ "${LOG_ROTATION_ENABLED:-false}" == "true" && -n "$CURRENT_LOG_FILE_PATH" ]]; then
    log_debug_event "JellyMac" "   Log File: $CURRENT_LOG_FILE_PATH"
    log_debug_event "JellyMac" "   (Retention: ${LOG_RETENTION_DAYS:-7} days)"
else
    log_user_info "JellyMac" "   File Logging: Disabled or not configured. Logging to console only."
fi

# STATE_DIR creation is handled by _acquire_lock if needed.
if [[ -d "$STATE_DIR" ]]; then
    log_debug_event "JellyMac" "✅ State directory OK: $STATE_DIR"
fi

log_debug_event "JellyMac" "Verifying feature-specific directory configurations..."

# doctor_utils.sh::validate_config_filepaths has already performed comprehensive checks for:
# - DEST_DIR_MOVIES, DEST_DIR_SHOWS, DROP_FOLDER, ERROR_DIR (required: non-empty config, exist/created, writable, network mounted)
# - DEST_DIR_YOUTUBE (optional: if non-empty in config, then exist/created, writable, network mounted)
# If any of those critical checks failed, jellymac.sh would have exited via doctor_utils.sh.

# Check LOCAL_DIR_YOUTUBE: Critical if YouTube features are enabled.
if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" == "true" ]]; then
    if [[ -z "${LOCAL_DIR_YOUTUBE:-}" ]]; then
        log_error_event "JellyMac" "CRITICAL: LOCAL_DIR_YOUTUBE is not configured in 'Configuration.txt' but YouTube features are enabled. Exiting."
        exit 1
    elif [[ ! -d "$LOCAL_DIR_YOUTUBE" ]]; then
        log_warn_event "JellyMac" "LOCAL_DIR_YOUTUBE ('$LOCAL_DIR_YOUTUBE') does not exist. Attempting to create."
        if ! mkdir -p "$LOCAL_DIR_YOUTUBE"; then
            log_error_event "JellyMac" "CRITICAL: Failed to create LOCAL_DIR_YOUTUBE ('$LOCAL_DIR_YOUTUBE'). Check permissions. Exiting."
            exit 1
        fi
    elif [[ ! -w "$LOCAL_DIR_YOUTUBE" ]]; then
        log_error_event "JellyMac" "CRITICAL: LOCAL_DIR_YOUTUBE ('$LOCAL_DIR_YOUTUBE') is not writable. Check permissions. Exiting."
        exit 1
    else
        log_debug_event "JellyMac" "✅ LOCAL_DIR_YOUTUBE ('$LOCAL_DIR_YOUTUBE') is configured and accessible for YouTube features."
    fi

    # Also ensure DEST_DIR_YOUTUBE is configured if YouTube features are on.
    if [[ -z "${DEST_DIR_YOUTUBE:-}" ]]; then
        log_error_event "JellyMac" "CRITICAL: DEST_DIR_YOUTUBE is not configured in 'Configuration.txt' but YouTube features are enabled. Exiting."
    else
        log_debug_event "JellyMac" "✅ DEST_DIR_YOUTUBE ('$DEST_DIR_YOUTUBE') is configured for YouTube features (accessibility checked by doctor_utils.sh)."
    fi
fi

# Check LOG_DIR: Critical if file logging is enabled.
if [[ "${LOG_ROTATION_ENABLED:-false}" == "true" ]]; then
    if [[ -z "${LOG_DIR:-}" ]]; then
        log_error_event "JellyMac" "CRITICAL: LOG_DIR is not configured in 'Configuration.txt' but LOG_ROTATION_ENABLED is true. Exiting."
    else
        log_debug_event "JellyMac" "✅ LOG_DIR ('$LOG_DIR') is configured for rotated logs (creation/writability handled by logging system)."
    fi
fi

log_user_info "JellyMac" "✅ Feature-specific directory configuration checks complete."
log_user_info "JellyMac" "✅ Core directory configurations validated."

log_debug_event "JellyMac" "Verifying program files are executable..."
for helper_script_path in "$HANDLE_YOUTUBE_SCRIPT" "$HANDLE_MAGNET_SCRIPT" "$PROCESS_MEDIA_ITEM_SCRIPT"; do
    if [[ ! -x "$helper_script_path" ]]; then
        log_error_event "JellyMac" "CRITICAL: Essential program file '$helper_script_path' is not found or not executable. Exiting."
        exit 1
    fi
done; log_user_info "JellyMac" "✅ All essential program files ready to go."

log_user_info "JellyMac" "✅ All critical checks passed and filepaths validated."

if [[ -n "$HISTORY_FILE" ]]; then
    if [[ ! -f "$HISTORY_FILE" ]]; then log_user_info "JellyMac" "📝 History file '$HISTORY_FILE' will be created on first use.";
    else log_debug_event "JellyMac" "📝 Using history file: $HISTORY_FILE"; fi
else log_warn_event "JellyMac" "HISTORY_FILE not configured. No history will be recorded."; fi

# --- Store command paths as needed for runtime ---
# doctor_utils.sh has verified command availability if features are enabled.
PBPASTE_CMD=""
if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" == "true" || "${ENABLE_CLIPBOARD_MAGNET:-false}" == "true" ]]; then
    PBPASTE_CMD="pbpaste" # Assumed available by doctor_utils.sh
fi

CAFFEINATE_CMD_PATH=""
if [[ "$(uname)" == "Darwin" ]]; then
    CAFFEINATE_CMD_PATH="caffeinate" # Assumed available by doctor_utils.sh
fi

# --- Log Configuration Summary ---
log_user_info "JellyMac" ""
log_user_info "JellyMac" "--- JellyMac Configuration Summary (v0.2.6) ---"
log_user_info "JellyMac" "   Check Interval: ${MAIN_LOOP_SLEEP_INTERVAL:-2}s | Max Processors: ${MAX_CONCURRENT_PROCESSORS:-2}"
log_user_info "JellyMac" ""
log_user_info "JellyMac" "  Media Destinations:"
log_user_info "JellyMac" "   Movies  → ${DEST_DIR_MOVIES:-N/A}"
log_user_info "JellyMac" "   Shows   → ${DEST_DIR_SHOWS:-N/A}"
log_user_info "JellyMac" "   YouTube → ${DEST_DIR_YOUTUBE:-N/A}"
log_user_info "JellyMac" ""
log_user_info "JellyMac" "📂 Drop Folder: ${DROP_FOLDER:-N/A}"
log_user_info "JellyMac" "📋 Clipboard: YouTube=${ENABLE_CLIPBOARD_YOUTUBE:-false} | Magnet=${ENABLE_CLIPBOARD_MAGNET:-false}"
log_user_info "JellyMac" ""
# Jellyfin status
if [[ -n "${JELLYFIN_SERVER:-}" && -n "${JELLYFIN_API_KEY:-}" ]]; then
    log_user_info "JellyMac" "🪼 Jellyfin: ${JELLYFIN_SERVER}"
    log_user_info "JellyMac" "   Auto-Syncing → Movies:${ENABLE_JELLYFIN_SCAN_MOVIES:-false} Shows:${ENABLE_JELLYFIN_SCAN_SHOWS:-false} YouTube:${ENABLE_JELLYFIN_SCAN_YOUTUBE:-false}"
else
    log_user_info "JellyMac" "🪼 Jellyfin: Auto-Sync not configured"
fi

log_user_info "JellyMac" "🔔 Notifications:${ENABLE_DESKTOP_NOTIFICATIONS:-false} | Sounds:${SOUND_NOTIFICATION:-false}"
log_user_info "JellyMac" "------------------------------------------------"
log_user_info "JellyMac" ""
log_user_info "JellyMac" "🔍 Checking the Drop Folder for movies or shows..."
process_drop_folder
if [[ -n "$PBPASTE_CMD" ]]; then
    log_user_info "JellyMac" "📋 Checking the clipboard for links..."; 
    _check_clipboard_youtube; 
    _check_clipboard_magnet
else log_user_info "JellyMac" "📋 Skipping initial clipboard checks ('pbpaste' not available or clipboard features disabled)."; fi

if [[ "${ENABLE_CLIPBOARD_YOUTUBE:-false}" == "true" ]]; then
    check_and_resume_youtube_queue
fi

log_user_status "JellyMac" "🔄 JellyMac is ready! Checking for any new links and files every ${MAIN_LOOP_SLEEP_INTERVAL:-2} second(s)..."
log_user_status "JellyMac" "(Press Ctrl+C to exit any time)"
while true; do
    manage_active_processors    
    
    # Time-based torrent cleanup (every 3 minutes, independent of main loop timing)
    if [[ "${TRANSMISSION_AUTO_CLEANUP:-false}" == "true" ]]; then
        current_time=$(date +%s)
        if [[ $((current_time - last_torrent_cleanup)) -ge 180 ]]; then
            cleanup_completed_torrents "JellyMac"
            last_torrent_cleanup=$current_time
        fi
    fi
    
    if [[ -n "$PBPASTE_CMD" ]]; then 
        _check_clipboard_youtube; 
        _check_clipboard_magnet; 
    fi
    process_drop_folder         
    
    sleep "${MAIN_LOOP_SLEEP_INTERVAL:-2}"
done
exit 0
