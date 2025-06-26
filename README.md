# 🪼 JellyMac

**Complete media automation for macOS - from clipboard to library**

JellyMac is a sophisticated media automation tool that handles both YouTube content and torrent downloads with complete library integration. Copy a YouTube or magnet link, and JellyMac handles everything: 

copy link → download video → clean name → intelligent sorting → library sync → ready to watch! 

All with zero additional user input. Just copy, done. Media is ready to stream.

**Don't need all that?** Jellymac is also a fully featured, free YouTube downloader, that works well with minimal setup on any mac!

---

## WHO THIS IS FOR

**YouTube content collectors** who want automatic downloads and organization

**Jellyfin/Plex users** who want their media automatically integrated and synced with their library

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

### Step 1: Install Homebrew (for more info please visit [brew.sh](https://brew.sh))

If you don't already have Homebrew, install it by running this command in your Terminal app:
(To open your Terminal, press (⌘ + space) and type "terminal" then hit return) 
(then you can copy (⌘ + c) and paste (⌘ + v) the following commands into your terminal)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
### Step 2: Install and Start JellyMac

Run this command to download, set up, and automatically start JellyMac:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mtn-Man/JellyMac/main/install.sh)"
```
That's it! JellyMac will start automatically after installation and guide you through the interactive setup to configure your media folders and services for seamless downloads.

### For Future Use

To start JellyMac again later (after stopping it or restarting your Mac):

```bash
cd ~/JellyMac && ./jellymac.sh
```

For detailed instructions and troubleshooting, see the **[Getting_Started.txt](Getting_Started.txt)** guide.

---

## IMPORTANT DISCLAIMERS

**Security Note:** Before running any script, it's a crucial security practice to review its contents. If you're not a developer, you can use an AI assistant (Gemini, ChatGPT, etc.) to analyze the script for you. This helps ensure the software is safe and does what it claims.

**Beta Software:** JellyMac is still in ongoing development. Always maintain backups of important media files before use.

**Legal Responsibility:** Use this tool only with media you have the legal right to access and manage. Ensure compliance with local laws and platform terms of service.

**Moral Responsibility:** Support the creators of the content you enjoy, even if indirectly. If what others have made bring you value, please consider supporting them.

---

### For Developers and Advanced Users

JellyMac is designed to be highly configurable and extensible. If you want to dive deeper, these resources are for you:

-   **[Quick Reference](Quick_Reference.txt):** Quick commands for advanced users.
-   **[Configuration Guide](Configuration_Guide.txt):** A detailed explanation of every setting available in `Configuration.txt`.
-   **[Arr Suite Handoff Guide](Arr_Suite_Handoff_Guide.txt):** A guide for integrating JellyMac with Sonarr, Radarr, etc.
-   **[Getting Started](Getting_Started.txt):** A comprehensive guide for new users.

---

## LICENSE AND CONTACT

**License:** MIT License - See LICENSE.txt  

**Contributor:** Eli Sher (Mtn-Man) - elisher@duck.com



