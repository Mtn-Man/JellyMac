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
• YouTube content collectors who want automatic download and organization
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
Step 1: Install Homebrew (if you don't have it)

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Step 2: Install and Start JellyMac

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mtn-Man/JellyMac/dev/install.sh)"

That's it! JellyMac will start automatically and guide you through
the interactive setup.

For future use, to start JellyMac again:

    cd ~/JellyMac && ./jellymac.sh

For detailed instructions, see the **Getting_Started.txt** guide.

---

IMPORTANT DISCLAIMERS
---------------------
Beta Software: JellyMac is in ongoing development. Always maintain
backups of important media files.

Legal Responsibility: Use this tool only with media you have the
legal right to access and manage.

Moral Responsibility: If you find value in someone's work, please
consider supporting them. Your support genuinely matters.

---

FOR DEVELOPERS AND ADVANCED USERS
---------------------------------
JellyMac is highly configurable and extensible. For details:

• Configuration_Guide.txt: A detailed explanation of every
  setting available in lib/jellymac_config.sh.

• Arr_Suite_Handoff_Guide.txt: Instructions for integrating
  JellyMac with your existing Sonarr and Radarr setup.

• Code Comments: The shell scripts in lib/ and bin/ are
  extensively commented. Everything is Bash 3.2 compliant for
  broader compatibility.

---

LICENSE AND CONTACT
-------------------
License: MIT License - See LICENSE.txt
Contributor: Eli Sher (Mtn-Man) - elisher@duck.com