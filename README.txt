┌─────────────────────────────────────────────────────────────┐
│                     J E L L Y M A C                         │
│           Automated Video Downloader for macOS              │
└─────────────────────────────────────────────────────────────┘

JellyMac is a sophisticated media automation tool that handles
both YouTube content and torrent downloads with complete library
integration. Copy a YouTube or magnet link, and JellyMac handles
everything:

copy link → download video → clean name → intelligent sorting → library sync → ready to watch!

All with zero additional user input. Just copy, done. Media is ready to stream.


Don't need all that? Jellymac is also a fully featured, free YouTube downloader,
that works well with minimal setup!

---

WHO THIS IS FOR
---------------
• YouTube content collectors who want automatic downloads and organization
• Jellyfin/Plex users who want media automatically integrated and synced
• Technical users who appreciate clipboard-based workflows
• Media enthusiasts who want clean, human-readable filenames
• Home server operators who need reliable network transfers
• Anyone who values "set and forget" automation that works invisibly

---

WHAT IT DOES
------------

Core Automation:
• Complete YouTube Workflow - Copy link → Download → Organize → Done!
• Complete Magnet Workflow - Copy link → Download → Sort → Done!
• Intelligent File Organization - Auto-sorted with clean names
• Background Processing - Queueing, monitoring, and cleanup

Smart Features:
• Never Download Twice - Smart tracking prevents duplicates
• Progress Notifications - Desktop alerts when downloads complete
• Network Smart - Works with local folders or network drives/NAS
• Queue Management - Copy multiple links, they process automatically

Technical Sophistication:
• Network Intelligence - Volume validation & transfer reliability
• Error Recovery - YouTube SABR recovery & automatic quarantine
• macOS Integration - Clipboard monitoring, notifications, & caffeinate

Media Server Integration:
• Jellyfin Integration - Auto-scan libraries when new content arrives
• Plex Support - Works with Plex media servers
• No Server Installation - Your Mac runs JellyMac, server can be anywhere

---

QUICKSTART GUIDE
----------------
Step 1: Install Homebrew (if you don't have it) - visit: https://brew.sh for more info
    
(To open your Terminal, press (⌘ + space) and type "terminal" then hit return) 
(then you can copy (⌘ + c) and paste (⌘ + v) the following commands into your terminal)

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Step 2: Install and Start JellyMac

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mtn-Man/JellyMac/main/install.sh)"

That's it! JellyMac will start automatically and guide you through the interactive setup.

For future use, to start JellyMac again:

    cd ~/JellyMac && ./jellymac.sh

For more detailed installation and config instructions, see Getting_Started.txt

---

IMPORTANT DISCLAIMERS
---------------------
Security Note: Before running any script, it's a crucial security
practice to review its contents. If you're not a developer, you can
use an AI assistant (Gemini, ChatGPT, etc.) to analyze the script
for you. This helps ensure the software is safe and does what it
claims.

Beta Software: JellyMac is in ongoing development. Always maintain
backups of important media files.

Legal Responsibility: Use this tool only with media you have the
legal right to access and manage.

Moral Responsibility: If you find value in someone's work, please
consider supporting them. Your support genuinely matters.

---

FOR DEVELOPERS AND ADVANCED USERS
---------------------------------
JellyMac is designed to be highly configurable and extensible.
If you want to dive deeper, these resources are for you:

• Configuration Guide: A detailed explanation of every setting available in 
    Configuration.txt.
• Arr Suite Handoff Guide: Instructions for integrating JellyMac with Sonarr and 
    Radarr for advanced media management workflows.

• Code Comments: The shell scripts in lib/ and bin/ are extensively
  commented to explain the logic and flow of the automation processes.
  Everything is Bash 3.2 compliant for broader compatibility.

---

LICENSE AND CONTACT
-------------------
License: MIT License - See LICENSE.txt
Contributor: Eli Sher (Mtn-Man) - elisher@duck.com