# jm4b.sh — Audiobook Creation Script

Converts, cleans, merges, and tags MP3/FLAC files into a `.m4b` audiobook.

## Features

|Feature|Description|
|---|---|
|Input|MP3, FLAC|
|Output|`.m4b` file|
|Processing|Cleans MP3s, converts FLACs|
|Chapters|Numeric sorting (1-9999)|
|Progress|ASCII progress bar|
|Tagging|Title, album, artist, cover|
|Bitrate|Dynamic (64-128 Kbps)|

## Prerequisite Setup

Install: `ffmpeg`, `AtomicParsley`, `ffprobe`, `bc`, and optionally `gcp` (falls back to `cp`).

### Debian Linux

```bash
sudo apt update
sudo apt install ffmpeg atomicparsley coreutils bc
```

### macOS (Homebrew)

```bash
brew install ffmpeg atomicparsley coreutils bc
```

Clone repository:

```bash
git clone https://github.com/Marcus1571/Audiobooks-Tools.git
cd Audiobooks-Tools
```

## Usage

1. Add MP3/FLAC files (e.g., `01-chapter.mp3`) and optional JPG cover to a folder.
2. Add `jm4b` to your shell:
    - Open `~/.bashrc` (Linux) or `~/.zshrc` (macOS) in a text editor.
    - Copy the `jm4b` function from `jm4b.sh` (everything from `jm4b() {` to the closing `}`) and paste it at the bottom.
    - Save and source the file:
        
        ### Debian Linux
        
        ```bash
        source ~/.bashrc
        ```
        
        ### macOS
        
        ```bash
        source ~/.zshrc
        ```
        
3. Run `jm4b` from the folder with your audio files.
4. Output: `.m4b` file named after the folder.

---

_Updated: July 2025_
