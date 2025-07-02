#!/bin/bash

# JellyMac/bin/handle_youtube_link.sh
# Handles downloading a YouTube video given a URL.
# Attempts to find the newest video file if yt-dlp exits successfully or hits max-downloads.
# Captures both stdout and stderr for more robust message checking, while showing live progress.

# --- Strict Mode & Globals ---
set -eo pipefail
# set -u # Uncomment for stricter undefined variable checks after thorough testing

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)" # Assumes lib is one level up from bin

# --- Temp File Management for this script ---
#==============================================================================
# Function: _cleanup_script_temp_files
# Description: Cleans up temporary files created during script execution.
# Parameters: None
# Returns: None
#==============================================================================
_cleanup_script_temp_files() {
    # shellcheck disable=SC2317
    if [[ ${#_SCRIPT_TEMP_FILES_TO_CLEAN[@]} -gt 0 ]]; then
        log_debug_event "YouTube" "EXIT trap: Cleaning up temporary files (${#_SCRIPT_TEMP_FILES_TO_CLEAN[@]})..."
        local temp_file_to_clean 
        for temp_file_to_clean in "${_SCRIPT_TEMP_FILES_TO_CLEAN[@]}"; do
            if [[ -n "$temp_file_to_clean" && -e "$temp_file_to_clean" ]]; then
                if rm -f "$temp_file_to_clean"; then
                    log_debug_event "YouTube" "EXIT trap: Removed '$temp_file_to_clean'"
                else
                    log_error_event "YouTube" "EXIT trap: Failed to remove '$temp_file_to_clean' - check permissions"
                fi
            fi
        done
    fi
    # shellcheck disable=SC2317
    _SCRIPT_TEMP_FILES_TO_CLEAN=()
    
    # CRITICAL: Always call library cleanup
    # shellcheck disable=SC2317
    if command -v _cleanup_common_utils_temp_files >/dev/null 2>&1; then
        _cleanup_common_utils_temp_files
    fi
}
trap _cleanup_script_temp_files EXIT SIGINT SIGTERM

# --- Source Libraries ---
# shellcheck source=../lib/logging_utils.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/logging_utils.sh"
# Configuration is now inherited from the parent shell (jellymac.sh)
# shellcheck source=../lib/common_utils.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/common_utils.sh" 
# shellcheck source=../lib/jellyfin_utils.sh
# shellcheck disable=SC1091
source "${LIB_DIR}/jellyfin_utils.sh" 


#==============================================================================
# ARGUMENT VALIDATION AND SETUP
#==============================================================================
if [[ $# -lt 1 ]]; then
    log_error_event "YouTube" "Usage: $SCRIPT_NAME <youtube_url> [yt-dlp options...]"
    exit 1
fi

YOUTUBE_URL="$1"
shift # Remove the URL from arguments, leaving only the options

# All remaining arguments are user-defined yt-dlp options
declare -a YTDLP_OPTS=("$@")

if [[ -z "$YOUTUBE_URL" ]]; then
    log_error_event "YouTube" "YouTube URL cannot be empty."
    exit 1
fi
log_user_info "YouTube" "▶️ Processing URL: ${YOUTUBE_URL:0:100}..."

#==============================================================================
# PRE-FLIGHT CHECKS AND DIRECTORY VALIDATION
#==============================================================================
# Validate required configuration variables and locate yt-dlp executable
YTDLP_EXECUTABLE=$(find_executable "yt-dlp" "${YTDLP_PATH:-}")
: "${LOCAL_DIR_YOUTUBE:?YT_HANDLER: LOCAL_DIR_YOUTUBE not set.}"
: "${DEST_DIR_YOUTUBE:?YT_HANDLER: DEST_DIR_YOUTUBE not set.}"
: "${YTDLP_FORMAT:?YT_HANDLER: YTDLP_FORMAT for YouTube not set in config.}"
: "${RSYNC_TIMEOUT:=300}"

# Validate LOCAL_DIR_YOUTUBE (local path)
if [[ ! -d "$LOCAL_DIR_YOUTUBE" ]]; then
    log_debug_event "YouTube" "Creating local directory '$LOCAL_DIR_YOUTUBE'..."
    if ! mkdir -p "$LOCAL_DIR_YOUTUBE"; then 
        log_error_event "YouTube" "Failed to create local dir '$LOCAL_DIR_YOUTUBE'. Check permissions."
        exit 1; 
    fi
fi
if [[ ! -w "$LOCAL_DIR_YOUTUBE" ]]; then 
    log_error_event "YouTube" "Local dir '$LOCAL_DIR_YOUTUBE' not writable."
    exit 1; 
fi

# Validate DEST_DIR_YOUTUBE (network-aware)
if ! validate_network_volume_before_transfer "$DEST_DIR_YOUTUBE" "YouTube"; then
    log_error_event "YouTube" "Network destination unavailable: $DEST_DIR_YOUTUBE"
    log_user_info "YouTube" "💡 Please reconnect to your media server and try again (Finder > Cmd+K)"
        # Add error sound notification
    play_sound_notification "task_error" "YouTube"
    exit 1
fi

if ! check_available_disk_space "${LOCAL_DIR_YOUTUBE}" "10240"; then # 10MB
    log_error_event "YouTube" "Insufficient disk space in '$LOCAL_DIR_YOUTUBE'."
    exit 1
fi

#==============================================================================
# DOWNLOAD EXECUTION AND COMMAND PREPARATION
#==============================================================================
log_user_progress "YouTube" "Starting download for: ${YOUTUBE_URL:0:70}..."
YTDLP_OUTPUT_TEMPLATE="${LOCAL_DIR_YOUTUBE}/%(title).200B.%(ext)s" # No initial subdirectory

# Build yt-dlp command arguments array
declare -a ytdlp_command_args=()
ytdlp_command_args[${#ytdlp_command_args[@]}]="--ignore-errors"  # Continue on non-fatal errors
ytdlp_command_args[${#ytdlp_command_args[@]}]="--format"
ytdlp_command_args[${#ytdlp_command_args[@]}]="$YTDLP_FORMAT"  # Use configured quality preference
ytdlp_command_args[${#ytdlp_command_args[@]}]="--output"
ytdlp_command_args[${#ytdlp_command_args[@]}]="$YTDLP_OUTPUT_TEMPLATE"  # Set filename template

# Check if progress option is already specified in user config
progress_option_set=false
if [[ ${#YTDLP_OPTS[@]} -gt 0 ]]; then
    for opt_check in "${YTDLP_OPTS[@]}"; do
        if [[ "$opt_check" == "--progress" || "$opt_check" == "--no-progress" ]]; then
            progress_option_set=true
            break
        fi
    done
fi
# Add progress option if not already specified by user
if [[ "$progress_option_set" == "false" ]]; then
    ytdlp_command_args[${#ytdlp_command_args[@]}]="--progress"
fi

# Apply user-specified yt-dlp options from YTDLP_OPTS array
if [[ ${#YTDLP_OPTS[@]} -gt 0 ]]; then
    for opt in "${YTDLP_OPTS[@]}"; do
        ytdlp_command_args[${#ytdlp_command_args[@]}]="$opt"
    done
fi

# Enable download archive if configured via DOWNLOAD_ARCHIVE_YOUTUBE
if [[ -n "$DOWNLOAD_ARCHIVE_YOUTUBE" ]]; then
    archive_dir=$(dirname "$DOWNLOAD_ARCHIVE_YOUTUBE")
    if [[ ! -d "$archive_dir" ]]; then
        log_debug_event "YouTube" "Creating archive directory '$archive_dir'..."
        if mkdir -p "$archive_dir"; then
            ytdlp_command_args[${#ytdlp_command_args[@]}]="--download-archive"
            ytdlp_command_args[${#ytdlp_command_args[@]}]="$DOWNLOAD_ARCHIVE_YOUTUBE"
            log_debug_event "YouTube" "Download archive enabled: $DOWNLOAD_ARCHIVE_YOUTUBE"
        else
             log_warn_event "YouTube" "Failed to create archive dir '$archive_dir'. Archive will NOT be used for this run."
        fi
    else
        ytdlp_command_args[${#ytdlp_command_args[@]}]="--download-archive"
        ytdlp_command_args[${#ytdlp_command_args[@]}]="$DOWNLOAD_ARCHIVE_YOUTUBE"
        log_debug_event "YouTube" "Download archive enabled: $DOWNLOAD_ARCHIVE_YOUTUBE"
    fi
else
    log_debug_event "YouTube" "No DOWNLOAD_ARCHIVE_YOUTUBE configured. Archive will not be used."
fi

# Apply cookies configuration if enabled
if [[ "${COOKIES_ENABLED:-false}" == "true" && -n "$COOKIES_FILE" ]]; then
    if [[ -f "$COOKIES_FILE" ]]; then 
        ytdlp_command_args[${#ytdlp_command_args[@]}]="--cookies"
        ytdlp_command_args[${#ytdlp_command_args[@]}]="$COOKIES_FILE"
        log_debug_event "YouTube" "Using cookies file: $COOKIES_FILE"
    else 
        log_warn_event "YouTube" "Cookies file '$COOKIES_FILE' not found. Proceeding without cookies."; 
    fi
else
    log_debug_event "YouTube" "Cookies disabled in config or not configured. Proceeding without cookies."
fi
ytdlp_command_args[${#ytdlp_command_args[@]}]="$YOUTUBE_URL" 

# Create temporary files to capture yt-dlp output for error analysis
YTDLP_STDOUT_CAPTURE_FILE=$(mktemp "${STATE_DIR}/.ytdlp_stdout_yt_handle.XXXXXX")
YTDLP_STDERR_CAPTURE_FILE=$(mktemp "${STATE_DIR}/.ytdlp_stderr_yt_handle.XXXXXX")
_SCRIPT_TEMP_FILES_TO_CLEAN[${#_SCRIPT_TEMP_FILES_TO_CLEAN[@]}]="$YTDLP_STDOUT_CAPTURE_FILE"
_SCRIPT_TEMP_FILES_TO_CLEAN[${#_SCRIPT_TEMP_FILES_TO_CLEAN[@]}]="$YTDLP_STDERR_CAPTURE_FILE"

log_debug_event "YouTube" "Executing command: $YTDLP_EXECUTABLE ${ytdlp_command_args[*]}"

#==============================================================================
# YTDLP EXECUTION WITH LIVE PROGRESS AND ERROR CAPTURE
#==============================================================================
set +e 
# Execute yt-dlp with dual output capture:
# - stderr: tee to capture file and display to user
# - stdout: tee to capture file and display progress to user
"$YTDLP_EXECUTABLE" "${ytdlp_command_args[@]}" \
    2> >(tee "$YTDLP_STDERR_CAPTURE_FILE" >&2) \
    | tee "$YTDLP_STDOUT_CAPTURE_FILE"

# Capture exit codes from the pipeline
YTDLP_EXIT_CODE=${PIPESTATUS[0]}  # yt-dlp exit code
_tee_stdout_ec=${PIPESTATUS[1]}   # tee exit code
set -e 

# Check for tee command issues (optional diagnostic)
if [[ "$_tee_stdout_ec" -ne 0 ]]; then
    log_warn_event "YouTube" "The 'tee' command for yt-dlp stdout exited with status $_tee_stdout_ec. Stdout capture might be affected, but yt-dlp progress should have been attempted."
fi

# Read captured output for error analysis
ytdlp_stdout_content=$(<"$YTDLP_STDOUT_CAPTURE_FILE")
ytdlp_stderr_content=$(<"$YTDLP_STDERR_CAPTURE_FILE")

DOWNLOADED_FILE_FULL_PATH="" 

#==============================================================================
# SABR STREAMING ERROR RECOVERY
#==============================================================================
# SABR (Streaming Audio/Video Browser Rendering) is a YouTube streaming method
# that can cause download failures. This section handles those errors with
# progressive retry attempts using different player clients.

if [[ "$YTDLP_EXIT_CODE" -ne 0 ]] && \
   (grep -q "YouTube is forcing SABR streaming" <<< "$ytdlp_stderr_content" || \
    grep -q "Only images are available for download" <<< "$ytdlp_stderr_content" || \
    grep -q "nsig extraction failed" <<< "$ytdlp_stderr_content"); then
    
    log_user_progress "YouTube" "Detected SABR streaming issue. Retrying with alternative player client..."
    
    # Create retry arguments, excluding cookies (incompatible with mobile clients)
    declare -a ytdlp_retry_args=()
    i=0
    while [[ $i -lt ${#ytdlp_command_args[@]} ]]; do
        arg="${ytdlp_command_args[$i]}"
        
        # Skip cookies arguments
        if [[ "$arg" == "--cookies" ]]; then
            i=$((i+2))  # Skip both --cookies and the filename
            continue
        elif [[ "$arg" == "$COOKIES_FILE" && $i -gt 0 && "${ytdlp_command_args[$((i-1))]}" == "--cookies" ]]; then
            i=$((i+1))  # Skip the filename (already skipped --cookies)
            continue
        else
            ytdlp_retry_args[${#ytdlp_retry_args[@]}]="$arg"
        fi
        i=$((i+1))
    done
    
    # Add iOS client arguments (better SABR compatibility)
    ytdlp_retry_args[${#ytdlp_retry_args[@]}]="--extractor-args"
    ytdlp_retry_args[${#ytdlp_retry_args[@]}]="youtube:player_client=ios"
    
    # Inform user about cookies removal if they were enabled
    if [[ "${COOKIES_ENABLED:-false}" == "true" && -n "$COOKIES_FILE" ]]; then
        log_debug_event "YouTube" "Note: Cookies disabled for iOS client retry (not supported)"
    fi
    
    # Execute first retry attempt with iOS client
    log_debug_event "YouTube" "Retrying with command: $YTDLP_EXECUTABLE ${ytdlp_retry_args[*]}"
    
    set +e
    "$YTDLP_EXECUTABLE" "${ytdlp_retry_args[@]}" \
        2> >(tee "$YTDLP_STDERR_CAPTURE_FILE" >&2) \
        | tee "$YTDLP_STDOUT_CAPTURE_FILE"
    
    YTDLP_EXIT_CODE=${PIPESTATUS[0]}
    _tee_stdout_ec=${PIPESTATUS[1]}
    set -e
    
    if [[ "$YTDLP_EXIT_CODE" -eq 0 ]]; then
        log_user_success "YouTube" "SABR stream retry successful using iOS player client!"
        ytdlp_stdout_content=$(<"$YTDLP_STDOUT_CAPTURE_FILE")
        ytdlp_stderr_content=$(<"$YTDLP_STDERR_CAPTURE_FILE")
    else
        log_warn_event "YouTube" "iOS player client retry also failed. Trying with Android player and 'b' format as final attempt..."
        
        # Prepare final attempt with Android client and simplified format
        declare -a ytdlp_final_args=()
        i=0
        while [[ $i -lt ${#ytdlp_command_args[@]} ]]; do
            arg="${ytdlp_command_args[$i]}"
            
            # Skip cookies arguments
            if [[ "$arg" == "--cookies" ]]; then
                i=$((i+2))  # Skip both --cookies and the filename
                continue
            elif [[ "$arg" == "$COOKIES_FILE" && $i -gt 0 && "${ytdlp_command_args[$((i-1))]}" == "--cookies" ]]; then
                i=$((i+1))  # Skip the filename (already skipped --cookies)
                continue
            # Skip format arguments (will be replaced with 'b')
            elif [[ "$arg" == "--format" ]]; then
                i=$((i+2))  # Skip both --format and the format value
                continue
            elif [[ "$arg" == "$YTDLP_FORMAT" && $i -gt 0 && "${ytdlp_command_args[$((i-1))]}" == "--format" ]]; then
                i=$((i+1))  # Skip the format value (already skipped --format)
                continue
            else
                ytdlp_final_args[${#ytdlp_final_args[@]}]="$arg"
            fi
            i=$((i+1))
        done
        
        # Use 'b' format (best) with Android player client as final attempt
        ytdlp_final_args[${#ytdlp_final_args[@]}]="--format"
        ytdlp_final_args[${#ytdlp_final_args[@]}]="b"
        ytdlp_final_args[${#ytdlp_final_args[@]}]="--extractor-args"
        ytdlp_final_args[${#ytdlp_final_args[@]}]="youtube:player_client=android"
        
        # Inform user about format and cookies changes
        if [[ "${COOKIES_ENABLED:-false}" == "true" && -n "$COOKIES_FILE" ]]; then
            log_debug_event "YouTube" "Note: Using format 'b' with Android player and cookies disabled for final retry attempt"
        else
            log_debug_event "YouTube" "Note: Using format 'b' with Android player for final retry attempt"
        fi
        
        log_debug_event "YouTube" "Final attempt with command: $YTDLP_EXECUTABLE ${ytdlp_final_args[*]}"
        
        set +e
        "$YTDLP_EXECUTABLE" "${ytdlp_final_args[@]}" \
            2> >(tee "$YTDLP_STDERR_CAPTURE_FILE" >&2) \
            | tee "$YTDLP_STDOUT_CAPTURE_FILE"
        
        YTDLP_EXIT_CODE=${PIPESTATUS[0]}
        _tee_stdout_ec=${PIPESTATUS[1]}
        set -e
        
        ytdlp_stdout_content=$(<"$YTDLP_STDOUT_CAPTURE_FILE")
        ytdlp_stderr_content=$(<"$YTDLP_STDERR_CAPTURE_FILE")
        
        if [[ "$YTDLP_EXIT_CODE" -eq 0 ]]; then
            log_user_success "YouTube" "Final attempt with Android player and 'b' format successful!"
        else
            log_user_info "YouTube" "All retry attempts failed for this YouTube URL."
            
            # Provide detailed user-friendly error information for SABR issues
            if grep -q "SABR streaming" <<< "$ytdlp_stderr_content" || grep -q "Only images are available" <<< "$ytdlp_stderr_content"; then
                log_warn_event "YouTube" "=========================================================================================="
                log_warn_event "YouTube" "⚠️  This YouTube video cannot be downloaded due to a recent YouTube streaming change (SABR)"
                log_warn_event "YouTube" "   JellyMac attempted multiple methods to download this video, but all failed."
                log_warn_event "YouTube" ""
                log_warn_event "YouTube" "   Possible workarounds:"
                log_warn_event "YouTube" "   1. Try again later - YouTube sometimes rotates video delivery methods"
                log_warn_event "YouTube" "   2. Try an alternative URL for this video (e.g., mobile or YouTube Music URL)"
                log_warn_event "YouTube" "   3. Update yt-dlp: brew update && brew upgrade yt-dlp"
                log_warn_event "YouTube" ""
                log_warn_event "YouTube" "   This is a known limitation with YouTube's new streaming format and not a JellyMac issue."
                log_warn_event "YouTube" "   For more details see: https://github.com/yt-dlp/yt-dlp/issues/12482"
                log_warn_event "YouTube" "=========================================================================================="
                
                # Show desktop notification if enabled
                if [[ "$(uname)" == "Darwin" && "${ENABLE_DESKTOP_NOTIFICATIONS:-false}" == "true" ]]; then
                    if command -v osascript &>/dev/null; then
                        osascript -e 'display notification "Cannot download this video due to YouTube SABR streaming limitations. See terminal for details." with title "JellyMac - YouTube Download Failed"' || true
                    fi
                fi
            fi
        fi
    fi
fi

# After SABR retry fails, auto-update yt-dlp and retry once more
if [[ "$YTDLP_EXIT_CODE" -ne 0 ]]; then
    log_user_info "YouTube" "🔄 Download failed. Updating yt-dlp and retrying..."
    
    # Update yt-dlp
    if brew update && brew upgrade yt-dlp; then
        log_user_info "YouTube" "✅ yt-dlp updated successfully. Retrying download..."
        
        # Re-find yt-dlp executable in case path changed
        YTDLP_EXECUTABLE=$(find_executable "yt-dlp" "${YTDLP_PATH:-}")
        
        # Final retry with updated yt-dlp using original arguments
        log_debug_event "YouTube" "Final retry with updated yt-dlp: $YTDLP_EXECUTABLE ${ytdlp_command_args[*]}"
        
        set +e
        "$YTDLP_EXECUTABLE" "${ytdlp_command_args[@]}" \
            2> >(tee "$YTDLP_STDERR_CAPTURE_FILE" >&2) \
            | tee "$YTDLP_STDOUT_CAPTURE_FILE"
        
        YTDLP_EXIT_CODE=${PIPESTATUS[0]}
        _tee_stdout_ec=${PIPESTATUS[1]}
        set -e
        
        ytdlp_stdout_content=$(<"$YTDLP_STDOUT_CAPTURE_FILE")
        ytdlp_stderr_content=$(<"$YTDLP_STDERR_CAPTURE_FILE")
        
        if [[ "$YTDLP_EXIT_CODE" -eq 0 ]]; then
            log_user_success "YouTube" "✅ Download successful after yt-dlp update!"
        else
            log_warn_event "YouTube" "❌ Download still failed after yt-dlp update. Exit code: $YTDLP_EXIT_CODE"
        fi
    else
        log_warn_event "YouTube" "❌ Failed to update yt-dlp. Cannot retry download."
    fi
fi

#==============================================================================
# DOWNLOAD RESULT PROCESSING AND FILE DISCOVERY
#==============================================================================
# Handle yt-dlp exit codes and attempt to find downloaded file
# Exit code 0: Successful download
# Exit code 101: Max downloads reached OR video already in archive
if [[ "$YTDLP_EXIT_CODE" -eq 0 ]] || \
   ([[ "$YTDLP_EXIT_CODE" -eq 101 ]] && (grep -q -i "max-downloads" <<< "$ytdlp_stdout_content" || grep -q -i "max-downloads" <<< "$ytdlp_stderr_content") ); then

    log_debug_event "YouTube" "yt-dlp exited with $YTDLP_EXIT_CODE. Adding 2s delay for file finalization..."
    sleep 2

    # Check if video was already processed (archive hit)
    if (grep -q -i "already been recorded in the archive" <<< "$ytdlp_stderr_content" || grep -q -i "already been recorded in the archive" <<< "$ytdlp_stdout_content"); then
        log_debug_event "YouTube" "yt-dlp (exit $YTDLP_EXIT_CODE) indicated video is already in archive. Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
        
        # CRITICAL FIX: Verify the file actually exists before treating as successful
        # Extract video title from URL to check if file exists in destination
        video_title=""
        case "$YOUTUBE_URL" in
            *"watch?v="*)
                # Try to extract title from yt-dlp output if available
                if [[ -n "$ytdlp_stdout_content" ]]; then
                    video_title=$(echo "$ytdlp_stdout_content" | grep -o "\[download\] Destination: .*" | head -1 | sed 's/\[download\] Destination: //')
                fi
                ;;
        esac
        
        # If we can't get the title from output, try to find any video file in destination
        if [[ -z "$video_title" ]]; then
            log_debug_event "YouTube" "Could not extract video title from yt-dlp output. Checking if any video file exists in destination."
            # Look for any video file in the destination directory
            found_video_file=""
            if [[ -d "$DEST_DIR_YOUTUBE" ]]; then
                found_video_file=$(find "$DEST_DIR_YOUTUBE" -maxdepth 2 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) -newer "$LOCAL_DIR_YOUTUBE" 2>/dev/null | head -1)
            fi
            
            if [[ -n "$found_video_file" && -f "$found_video_file" ]]; then
                log_user_info "YouTube" "✅ Found existing video file in destination: $(basename "$found_video_file")"
                log_user_info "YouTube" "Video already processed and available. Skipping to avoid re-processing."
                exit 0
            else
                log_warn_event "YouTube" "⚠️ Archive entry found but no video file exists in destination. Removing archive entry to allow retry."
                # Remove from archive to allow retry
                if [[ -n "$DOWNLOAD_ARCHIVE_YOUTUBE" && -f "$DOWNLOAD_ARCHIVE_YOUTUBE" ]]; then
                    video_id=""
                    case "$YOUTUBE_URL" in
                        *"watch?v="*)
                            video_id="${YOUTUBE_URL#*watch?v=}"
                            video_id="${video_id%%&*}"
                            ;;
                        *"youtu.be/"*)
                            video_id="${YOUTUBE_URL#*youtu.be/}"
                            video_id="${video_id%%\?*}"
                            ;;
                    esac
                    
                    if [[ -n "$video_id" ]]; then
                        log_debug_event "YouTube" "Removing video ID $video_id from archive to allow retry"
                        cp "$DOWNLOAD_ARCHIVE_YOUTUBE" "$DOWNLOAD_ARCHIVE_YOUTUBE.bak"
                        grep -v "youtube $video_id" "$DOWNLOAD_ARCHIVE_YOUTUBE.bak" > "$DOWNLOAD_ARCHIVE_YOUTUBE"
                        log_debug_event "YouTube" "Removed $video_id from archive - will retry download"
                    fi
                fi
                # Continue with normal download process instead of exiting
            fi
        else
            log_user_info "YouTube" "Video already processed and available. Skipping to avoid re-processing."
            exit 0
        fi
    fi
    
    if [[ "$YTDLP_EXIT_CODE" -eq 101 ]]; then 
        log_debug_event "YouTube" "yt-dlp (exit 101) indicated --max-downloads limit was respected. Will attempt to find downloaded file. Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
    fi

    # Search for the newest video file directly in the LOCAL_DIR_YOUTUBE
    log_user_progress "YouTube" "Locating downloaded file in '${LOCAL_DIR_YOUTUBE}'..."
    if [[ -d "${LOCAL_DIR_YOUTUBE}" ]]; then
        set +e
        # Search only in the top level of LOCAL_DIR_YOUTUBE
        potential_file_full_path=$(find "${LOCAL_DIR_YOUTUBE}" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.webm" \) -print0 2>/dev/null | xargs -0 ls -Ft 2>/dev/null | head -n 1 | sed 's/[*@/]$//')
        find_ls_exit_code=$?
        set -e

        if [[ "$find_ls_exit_code" -eq 0 && -n "$potential_file_full_path" && -f "$potential_file_full_path" ]]; then
            DOWNLOADED_FILE_FULL_PATH="$potential_file_full_path"
            log_debug_event "YouTube" "Found potential newest video file: '$DOWNLOADED_FILE_FULL_PATH'"
        elif [[ "$find_ls_exit_code" -ne 0 ]]; then
            log_warn_event "YouTube" "Command to find newest video file failed (exit code $find_ls_exit_code)."
        elif [[ -z "$potential_file_full_path" ]]; then
            log_warn_event "YouTube" "No common video files (.mkv, .mp4, .webm) found in '${LOCAL_DIR_YOUTUBE}' after yt-dlp run (exit code $YTDLP_EXIT_CODE)."
        else 
             log_warn_event "YouTube" "Found path '$potential_file_full_path' from find/ls, but it's not a valid file or test failed."
        fi
    else
        log_warn_event "YouTube" "LOCAL_DIR_YOUTUBE ('${LOCAL_DIR_YOUTUBE}') is not a directory."
    fi
    
    # Validate discovered file
    if [[ -n "$DOWNLOADED_FILE_FULL_PATH" && -f "$DOWNLOADED_FILE_FULL_PATH" ]]; then
         log_debug_event "YouTube" "Proceeding with discovered file: '$DOWNLOADED_FILE_FULL_PATH'"
    else
        if [[ "$YTDLP_EXIT_CODE" -eq 0 ]]; then
            log_warn_event "YouTube" "Could not reliably determine downloaded file after yt-dlp exited 0. Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
            exit 1 
        else 
            log_debug_event "YouTube" "yt-dlp exited 101 (max-downloads) but no new video file was found. Assuming limit respected before download or file not a recognized video type. Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
            exit 0 
        fi
    fi

elif [[ "$YTDLP_EXIT_CODE" -eq 101 ]]; then 
    # Handle other exit 101 cases (not max-downloads related)
    if (grep -q -i "already been recorded in the archive" <<< "$ytdlp_stderr_content" || grep -q -i "already been recorded in the archive" <<< "$ytdlp_stdout_content"); then
        log_debug_event "YouTube" "yt-dlp (exit 101) indicated video is already in archive. Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
        
        # CRITICAL FIX: Verify the file actually exists before treating as successful
        # Look for any video file in the destination directory
        found_video_file=""
        if [[ -d "$DEST_DIR_YOUTUBE" ]]; then
            found_video_file=$(find "$DEST_DIR_YOUTUBE" -maxdepth 2 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) -newer "$LOCAL_DIR_YOUTUBE" 2>/dev/null | head -1)
        fi
        
        if [[ -n "$found_video_file" && -f "$found_video_file" ]]; then
            log_user_info "YouTube" "✅ Found existing video file in destination: $(basename "$found_video_file")"
            log_user_info "YouTube" "Video already processed and available. Exiting successfully."
            exit 0
        else
            log_warn_event "YouTube" "⚠️ Archive entry found but no video file exists in destination. Removing archive entry to allow retry."
            # Remove from archive to allow retry
            if [[ -n "$DOWNLOAD_ARCHIVE_YOUTUBE" && -f "$DOWNLOAD_ARCHIVE_YOUTUBE" ]]; then
                video_id=""
                case "$YOUTUBE_URL" in
                    *"watch?v="*)
                        video_id="${YOUTUBE_URL#*watch?v=}"
                        video_id="${video_id%%&*}"
                        ;;
                    *"youtu.be/"*)
                        video_id="${YOUTUBE_URL#*youtu.be/}"
                        video_id="${video_id%%\?*}"
                        ;;
                esac
                
                if [[ -n "$video_id" ]]; then
                    log_debug_event "YouTube" "Removing video ID $video_id from archive to allow retry"
                    cp "$DOWNLOAD_ARCHIVE_YOUTUBE" "$DOWNLOAD_ARCHIVE_YOUTUBE.bak"
                    grep -v "youtube $video_id" "$DOWNLOAD_ARCHIVE_YOUTUBE.bak" > "$DOWNLOAD_ARCHIVE_YOUTUBE"
                    log_debug_event "YouTube" "Removed $video_id from archive - will retry download"
                fi
            fi
            # Continue with normal download process instead of exiting
        fi
    else
        log_error_event "YouTube" "yt-dlp exited 101 (unhandled reason). Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
        exit 1
    fi
else 
    # Handle all other error cases
    log_error_event "YouTube" "yt-dlp failed. Exit: $YTDLP_EXIT_CODE. Stdout: [$ytdlp_stdout_content] Stderr: [$ytdlp_stderr_content]"
    # Clean up any partial downloads (.part files)
    find "$LOCAL_DIR_YOUTUBE" -maxdepth 1 -name "*.part" -exec rm -f {} \; -print0 2>/dev/null | xargs -0 -r -I {} log_debug_event "YouTube" "Removed partial: {}"
    exit 1
fi

# Final validation of discovered file
if [[ -z "$DOWNLOADED_FILE_FULL_PATH" || ! -f "$DOWNLOADED_FILE_FULL_PATH" ]]; then
    log_error_event "YouTube" "FATAL LOGIC ERROR: No valid downloaded file path. Path: '${DOWNLOADED_FILE_FULL_PATH:-EMPTY}'. Review logs."
    exit 1
fi

#==============================================================================
# FILENAME LENGTH VALIDATION AND TRUNCATION
#==============================================================================
# Get the original filename and directory
original_downloaded_filename=$(basename "$DOWNLOADED_FILE_FULL_PATH")
download_dir=$(dirname "$DOWNLOADED_FILE_FULL_PATH")

# Only keep the length check for filesystem limits
max_filename_length=200  # Conservative limit for cross-filesystem compatibility

if [[ ${#original_downloaded_filename} -gt $max_filename_length ]]; then
    log_user_progress "YouTube" "Filename too long (${#original_downloaded_filename} chars), truncating to $max_filename_length..."
    
    # Extract extension and truncate
    file_ext="${original_downloaded_filename##*.}"
    filename_no_ext="${original_downloaded_filename%.*}"
    available_length=$((max_filename_length - ${#file_ext} - 1))
    
    if [[ $available_length -gt 3 ]]; then
        truncated_filename_no_ext="${filename_no_ext:0:$((available_length - 3))}..."
    else
        truncated_filename_no_ext="${filename_no_ext:0:$available_length}"
    fi
    
    final_local_filename="${truncated_filename_no_ext}.${file_ext}"
    final_local_full_path="${download_dir}/${final_local_filename}"
    
    # Rename with proper quoting
    if mv -- "$DOWNLOADED_FILE_FULL_PATH" "$final_local_full_path"; then
        log_debug_event "YouTube" "Successfully truncated filename to: '$final_local_filename'"
        DOWNLOADED_FILE_FULL_PATH="$final_local_full_path"
    else
        log_error_event "YouTube" "Failed to rename file for length truncation. Proceeding with original name."
        final_local_filename="$original_downloaded_filename"
    fi
else
    final_local_filename="$original_downloaded_filename"
    final_local_full_path="$DOWNLOADED_FILE_FULL_PATH"
fi

log_user_info "YouTube" "✅ Confirmed media file: '${final_local_filename//\'/\'\\\'\'}'"

#==============================================================================
# FINAL TRANSFER TO DESTINATION
#==============================================================================
# DOWNLOADED_FILE_FULL_PATH at this point is like: /Users/user/JellyMac/.temp_youtube/CleanedAndPossiblyTruncatedFileName.mp4
# final_local_filename is "CleanedAndPossiblyTruncatedFileName.mp4"

# The variable 'original_temp_subdir_source' is no longer needed as we operate directly on the file.

# Derive the desired *final* subdirectory name from the cleaned and truncated filename
desired_final_subdir_name="${final_local_filename%.*}" # Removes extension, e.g., "Tip Line - Microsoft Recall Bypass..."

# Construct the full path for the final destination DIRECTORY and FILE
# based on YOUTUBE_CREATE_SUBFOLDER_PER_VIDEO setting
if [[ "${YOUTUBE_CREATE_SUBFOLDER_PER_VIDEO:-false}" == "true" ]]; then
    # Create a subfolder for the video
    final_destination_dir="${DEST_DIR_YOUTUBE}/${desired_final_subdir_name}"
    final_destination_path_for_file="${final_destination_dir}/${final_local_filename}"
    log_debug_event "YouTube" "Subfolder per video enabled. Final destination dir: $final_destination_dir"
else
    # Place video loosely in DEST_DIR_YOUTUBE
    final_destination_dir="${DEST_DIR_YOUTUBE}"
    final_destination_path_for_file="${final_destination_dir}/${final_local_filename}"
    log_debug_event "YouTube" "Subfolder per video disabled. Final destination dir: $final_destination_dir"
fi

# Calculate file size for disk space check (using the actual file to be transferred)
file_size_bytes=$(stat -f "%z" "$DOWNLOADED_FILE_FULL_PATH" 2>/dev/null || echo "0")
file_size_kb="1"
if [[ "$file_size_bytes" =~ ^[0-9]+$ && "$file_size_bytes" -gt 0 ]]; then
    file_size_kb=$(( (file_size_bytes + 1023) / 1024 ));
fi

# Verify sufficient disk space in the root of DEST_DIR_YOUTUBE (mkdir -p will handle subfolder creation)
if ! check_available_disk_space "${DEST_DIR_YOUTUBE}" "$file_size_kb"; then
    log_error_event "YouTube" "Insufficient disk space in '$DEST_DIR_YOUTUBE' for '$final_local_filename'."
    # Quarantine the source file if it exists
    if [[ -n "$DOWNLOADED_FILE_FULL_PATH" && -f "$DOWNLOADED_FILE_FULL_PATH" ]]; then
        quarantine_item "$DOWNLOADED_FILE_FULL_PATH" "No remote disk space for YouTube video (pre-transfer)" || log_warn_event "YouTube" "Quarantine failed for '$DOWNLOADED_FILE_FULL_PATH'"
    fi
    exit 1
fi

log_user_progress "YouTube" "Preparing to move '$final_local_filename' to '$final_destination_dir'..."

# Create final destination directory (e.g., /Volumes/MEDIA/Content/Tip Line - Microsoft Recall Bypass...)
if [[ ! -d "$final_destination_dir" ]]; then
    log_debug_event "YouTube" "Creating final destination directory: $final_destination_dir"
    if ! mkdir -p "$final_destination_dir"; then
        log_error_event "YouTube" "Failed to create destination directory: $final_destination_dir. Check permissions."
        # No need to quarantine here, transfer will fail and handle it if mkdir fails
        exit 1
    fi
fi

# Transfer the single video file
transfer_failed=false
if transfer_file_smart "$DOWNLOADED_FILE_FULL_PATH" "$final_destination_path_for_file" "YouTube"; then
    log_debug_event "YouTube" "File transfer successful."
else
    transfer_failed=true
    log_error_event "YouTube" "File transfer failed: $DOWNLOADED_FILE_FULL_PATH -> $final_destination_path_for_file"
fi

# Handle transfer failure (if it occurred)
if [[ "$transfer_failed" == "true" ]]; then
    # Remove from download archive since transfer failed - allows retry on next attempt
    if [[ -n "$DOWNLOAD_ARCHIVE_YOUTUBE" && -f "$DOWNLOAD_ARCHIVE_YOUTUBE" ]]; then
        # Extract video ID from URL for archive removal using Bash 3.2 parameter expansion
        video_id=""
        case "$YOUTUBE_URL" in
            *"watch?v="*)
                video_id="${YOUTUBE_URL#*watch?v=}"  # Remove everything before "watch?v="
                video_id="${video_id%%&*}"           # Remove everything after first "&"
                ;;
            *"youtu.be/"*)
                video_id="${YOUTUBE_URL#*youtu.be/}" # Remove everything before "youtu.be/"
                video_id="${video_id%%\?*}"          # Remove everything after first "?"
                ;;
        esac
        
        if [[ -n "$video_id" ]]; then
            log_debug_event "YouTube" "Extracted video ID for archive cleanup: $video_id"
            # Remove the video ID from download archive to allow retry
            if grep -q "youtube $video_id" "$DOWNLOAD_ARCHIVE_YOUTUBE" 2>/dev/null; then
                # Create backup and remove entry using portable method
                cp "$DOWNLOAD_ARCHIVE_YOUTUBE" "$DOWNLOAD_ARCHIVE_YOUTUBE.bak"
                grep -v "youtube $video_id" "$DOWNLOAD_ARCHIVE_YOUTUBE.bak" > "$DOWNLOAD_ARCHIVE_YOUTUBE"
                log_debug_event "YouTube" "Removed $video_id from download archive due to transfer failure - retry will be possible"
            fi
        else
            log_warn_event "YouTube" "Could not extract video ID from URL for archive cleanup: $YOUTUBE_URL"
        fi
    fi
    
    # Quarantine the source file that failed to transfer
    if [[ -n "$DOWNLOADED_FILE_FULL_PATH" && -f "$DOWNLOADED_FILE_FULL_PATH" ]]; then
        quarantine_item "$DOWNLOADED_FILE_FULL_PATH" "transfer_failed_youtube" || log_warn_event "YouTube" "Quarantine failed for '$DOWNLOADED_FILE_FULL_PATH'"
    fi
    exit 1
fi

# Success logging and history
log_user_progress "YouTube" "↪️ Successfully moved '$final_local_filename' to '$final_destination_dir'"
record_transfer_to_history "YouTube: ${YOUTUBE_URL:0:70}... -> ${final_destination_path_for_file}" || log_warn_event "YouTube" "History record failed."

#==============================================================================
# POST-PROCESSING AND NOTIFICATIONS
#==============================================================================
# Trigger Jellyfin library scan if configured
if [[ "${ENABLE_JELLYFIN_SCAN_YOUTUBE:-false}" == "true" ]]; then
    log_user_info "YouTube" "Triggering Jellyfin scan for YouTube..."
    trigger_jellyfin_library_scan "YouTube" || log_warn_event "YouTube" "Jellyfin scan for YouTube may have failed. Check Jellyfin logs."
fi

# macOS-specific notifications and sound alerts
if [[ "$(uname)" == "Darwin" ]]; then
    notification_title_safe=$(echo "$final_local_filename" | head -c 200) 
    
    # Desktop notification if enabled
    if [[ "${ENABLE_DESKTOP_NOTIFICATIONS:-false}" == "true" ]]; then
        osascript_cmd_str="display notification \"Processing complete: ${notification_title_safe}\" with title \"JellyMac - YouTube\""
        if command -v osascript &>/dev/null; then 
            osascript -e "$osascript_cmd_str" || log_warn_event "YouTube" "osascript desktop notification failed."; 
        else 
            log_warn_event "YouTube" "'osascript' not found. Cannot send desktop notification."; 
        fi
    fi
    
    # Sound notification for successful completion
    play_sound_notification "task_success" "$SCRIPT_NAME"
fi

log_user_complete "YouTube" "✨ Successfully processed: $final_local_filename"
exit 0