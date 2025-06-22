# 🪼 JellyMac

**Complete media automation for macOS - from clipboard to library**

JellyMac is a sophisticated media automation tool that handles both YouTube content and torrent downloads with complete library integration. Copy a YouTube or magnet link, and JellyMac handles everything: 

copy → download → intelligent processing → clean naming → sorting → library sync → ready to watch! 

All with zero additional user input. Just copy, done. Media is ready to stream.

**Don't need all that?** Jellymac is also a fully featured, free YouTube downloader, that works well with minimal setup!

---

## WHO THIS IS FOR

**YouTube content collectors** who want automatic download and organization
**Jellyfin/Plex users** who want their media automatically integrated and scanned
**Technical users** who appreciate clipboard-based workflows and background processing
**Media enthusiasts** who want clean, human-readable filenames without clutter
**Home server operators** who need reliable network transfers and automatic library scanning
**Anyone** who values "set and forget" automation that works reliably and invisibly

---

## WHAT IT DOES

### Core Automation
🎬 **Complete YouTube Workflow** - Copy YouTube link → Download → Organize → Library → Done!
🧲 **Complete Magnet Workflow** - Copy magnet link → Download → Clean naming → Library → Done!
📁 **Intelligent File Organization** - Movies and TV shows automatically sorted with clean names
🔄 **Background Processing** - Queue management, progress monitoring, and automatic cleanup

### Smart Features 
🛡️ **Never Download Twice** - Smart tracking prevents duplicate downloads across sessions
📱 **Progress Notifications** - Desktop alerts when downloads complete  
🌐 **Network Smart** - Works with local folders or network drives/NAS  
⚡ **Queue Management** - Copy multiple links, they process automatically  

### Technical Sophistication
🌐 **Network Intelligence** - Volume validation, transfer reliability, and rsync timeouts
⚡ **Error Recovery** - YouTube SABR recovery, transfer failure handling, and automatic quarantine
📱 **macOS Integration** - Clipboard monitoring, desktop notifications, and caffeinate support

### Media Server Integration
🪼 **Jellyfin Integration** - Auto-scan libraries when new content arrives
📺 **Plex Support** - Works with Plex media servers  
🖥️ **No Server Installation** - Your Mac runs JellyMac, media server can be anywhere

---

## QUICKSTART GUIDE

### Step 1: Install Homebrew (for more info please visit brew.sh)

If you don't already have Homebrew, install it by running this command in your Terminal app:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Step 2: Install and Start JellyMac

Run this command to download, set up, and automatically start JellyMac:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mtn-Man/JellyMac/dev/install.sh)"
```

That's it! JellyMac will start automatically after installation and guide you through the interactive setup to configure your media folders and services.

### For Future Use

To start JellyMac again later (after stopping it or restarting your Mac):

```bash
cd ~/JellyMac && ./jellymac.sh
```

For detailed instructions and troubleshooting, see the **[Getting_Started.txt](Getting_Started.txt)** guide.

---

## IMPORTANT DISCLAIMERS

**Beta Software:** JellyMac is still in ongoing development. Always maintain backups of important media files before use.

**Legal Responsibility:** Use this tool only with media you have the legal right to access and manage. Ensure compliance with local laws and platform terms of service.

**Moral Responsibility:** Support the creators of the content you enjoy, even if indirectly. If what others have made bring you value, please consider supporting them.

---

### For Developers and Advanced Users

JellyMac is designed to be highly configurable and extensible. If you want to dive deeper, these resources are for you:

-   **[Configuration Guide](Configuration_guide.txt):** A detailed explanation of every setting available in `lib/jellymac_config.sh`.

-   **[Arr Suite Handoff Guide](Arr_Suite_Handoff_Guide.txt):** Instructions for integrating JellyMac with Sonarr and Radarr for advanced media management workflows.

-   **Code Comments:** The shell scripts in `lib/` and `bin/` are extensively commented to explain the logic and flow of the automation processes. Everything is Bash 3.2 compliant for broader compatibility.

---

## LICENSE AND CONTACT

**License:** MIT License - See LICENSE.txt  
**Contributor:** Eli Sher (Mtn-Man) - elisher@duck.com
