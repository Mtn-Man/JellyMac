#!/bin/bash

# lib/logging_utils.sh
# Contains common logging functions for the JellyMac project.

#===============================================================================
# Log Level Definitions
# Description: Numeric representations of log levels. Lower numbers are more verbose.
#===============================================================================
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

#===============================================================================
# Global Variable for Script's Current Log Level
# Description: Sets the current log level for the script sourcing this library.
# Parameters: None
# Returns: Defaults to INFO if not set by the calling script.
#===============================================================================
: "${SCRIPT_CURRENT_LOG_LEVEL:=$LOG_LEVEL_INFO}"

#===============================================================================
# Function: _log_event_if_level_met
# Description: Internal helper function to check level and print message.
# Parameters:
#   $1: Required numeric level for this message (e.g., LOG_LEVEL_DEBUG)
#   $2: Prefix string (e.g., emoji or script name)
#   $3: Message string
#   $4: (Optional) Output stream override. If set to ">&1", forces stdout.
# Returns: None
#===============================================================================
_log_event_if_level_met() {
    local required_level="$1"
    local prefix="$2"
    local message="$3"
    local output_stream_override="${4:-}" # Optional override

    if [[ "$SCRIPT_CURRENT_LOG_LEVEL" -le "$required_level" ]]; then
        # Console output
        if [[ "$output_stream_override" == ">&1" ]]; then
            echo "$prefix $(date '+%Y-%m-%d %H:%M:%S') - $message"
        else
            echo "$prefix $(date '+%Y-%m-%d %H:%M:%S') - $message" >&2
        fi
        
        # File output (if logging capability is available)
        if command -v _log_to_current_file >/dev/null 2>&1; then
            _log_to_current_file "$required_level" "$prefix" "$message"
        fi
    fi
}

#===============================================================================
# Function: log_debug_event
# Description: Logs DEBUG level messages with module prefix.
# Parameters:
#   $1: Module name (e.g., "YouTube", "JellyMac")
#   $2: Message string
# Returns: None
#===============================================================================
log_debug_event() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_DEBUG" "🔧 $module" "$message"
}

#===============================================================================
# Function: log_info_event
# Description: Logs INFO level messages with module prefix.
# Parameters:
#   $1: Module name (e.g., "JellyMac", "YouTube")
#   $2: Message string
# Returns: None
#===============================================================================
log_info_event() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_INFO" "🪼 $module" "$message"
}

#===============================================================================
# Function: log_warn_event
# Description: Logs WARN level messages with module prefix.
# Parameters:
#   $1: Module name (e.g., "YouTube", "JellyMac") 
#   $2: Message string
# Returns: None
#===============================================================================
log_warn_event() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_WARN" "⚠️ $module" "$message"
}

#===============================================================================
# Function: log_error_event
# Description: Logs an ERROR message.
# Parameters:
#   $1: Prefix (e.g., emoji or script name)
#   $2: Message string
# Returns: None
#===============================================================================
log_error_event() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_ERROR" "❌ $module" "$message"
}

#===============================================================================
# UI-FOCUSED LOGGING FUNCTIONS
# Description: Clean, user-friendly logging functions with consistent emoji prefixes
# These functions provide a better visual hierarchy for end-user experience
#===============================================================================

#===============================================================================
# Function: log_user_info
# Description: Logs important user-facing information with clean formatting.
# Parameters:
#   $1: Module name (e.g., "JellyMac", "YouTube", "Health")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_info() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    local emoji
    
    # Auto-assign emoji based on module
    case "$module" in
        "JellyMac"|"jellymac") emoji="🪼" ;;
        "YouTube"|"youtube") emoji="📥" ;;
        "Doctor"|"doctor") emoji="💊" ;;
        "Config"|"config") emoji="⚙️" ;;
        "Torrent"|"torrent") emoji="🧲" ;;
        "Jellyfin"|"jellyfin") emoji="🔄" ;;
        "Processing"|"processing") emoji="⚙️" ;;
        "Media"|"media") emoji="🎬" ;;
        "Transfer"|"transfer") emoji="📁" ;;
        "Scan"|"scan") emoji="👀" ;;
        *) emoji="ℹ️" ;;
    esac
    
    _log_event_if_level_met "$LOG_LEVEL_INFO" "$emoji $module" "$message"
}

#===============================================================================
# Function: log_user_success
# Description: Logs major completion events with emphasis.
# Parameters:
#   $1: Module name (e.g., "YouTube", "Processing")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_success() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_INFO" "✅ $module" "$message"
}

#===============================================================================
# Function: log_user_progress
# Description: Logs progress indicators for long-running operations.
# Parameters:
#   $1: Module name (e.g., "YouTube", "Transfer")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_progress() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    local emoji
    
    # Auto-assign progress emoji based on module
    case "$module" in
    "JellyMac"|"jellymac") emoji="🪼" ;;
    "YouTube"|"youtube") emoji="📥" ;;
    "Doctor"|"doctor") emoji="💊" ;;
    "Config"|"config") emoji="⚙️" ;;
    "Torrent"|"torrent") emoji="🧲" ;;
    "Jellyfin"|"jellyfin") emoji="🔄" ;;
    "Processing"|"processing") emoji="⚙️" ;;
    "Media"|"media") emoji="🎬" ;;
    "Transfer"|"transfer") emoji="📁" ;;
    "Scan"|"scan") emoji="👀" ;;
    *) emoji="🔄" ;;    
    esac
    
    _log_event_if_level_met "$LOG_LEVEL_INFO" "$emoji $module" "$message"
}

#===============================================================================
# Function: log_user_start
# Description: Logs major operation start events.
# Parameters:
#   $1: Module name (e.g., "JellyMac", "YouTube")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_start() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_INFO" "🚀 $module" "$message"
}

#===============================================================================
# Function: log_user_complete
# Description: Logs major operation completion with celebration.
# Parameters:
#   $1: Module name (e.g., "YouTube", "Processing")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_complete() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_INFO" "🎉 $module" "$message"
}

#===============================================================================
# Function: log_user_status
# Description: Logs status updates and monitoring information.
# Parameters:
#   $1: Module name (e.g., "JellyMac", "Monitor")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_status() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_INFO" "🔄 $module" "$message"
}

#===============================================================================
# Function: log_user_shutdown
# Description: Logs shutdown and cleanup messages.
# Parameters:
#   $1: Module name (e.g., "JellyMac")
#   $2: Message string
# Returns: None
#===============================================================================
log_user_shutdown() {
    local module="${1:-Unknown}"
    local message="${2:-}"
    _log_event_if_level_met "$LOG_LEVEL_INFO" "👋 $module" "$message"
}