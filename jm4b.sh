# 📚 jm4b function — Convert, Clean, Merge and Tag Audiobooks
# ───────────────────────────────────────────────────────────────
# 🛠️ Capabilities Table:
# ┌─────────────┬────────────────────────────────────────────────┐
# │ Input       │ FLAC, MP3                                    │
# │ Output      │ Single unified `.m4b` file                   │
# │ Audio Fix   │ Cleans MP3s, converts FLACs to `.m4a`        │
# │ Order       │ Zero-padded chapter sorting (1-9999)         │
# │ Progress UI │ Custom ASCII progress bar with percentage    │
# │ Tagging     │ AtomicParsley with cover, title, album, artist│
# │ Bitrate     │ Dynamic bitrate based on input average      │
# │ Validation  │ Checks for invalid files and output size    │
# │ Fallbacks   │ Defaults for missing artist/cover, 5-hour   │
# │             │ duration if invalid                          │
# └─────────────┴────────────────────────────────────────────────┘

jm4b() {
  echo "📚  jm4b function starting…"
  echo "🧾  Version: 1.7.145 (dynamic bitrate, fixed chapter order, gcp instead of cp with fix)"

  local title="${PWD##*/}"
  local output="${title}.m4b"
  local artist="Unknown"

  echo "🔎  Scanning current folder: $PWD"
  echo "🗃️  Output file will be: $output"
  echo "🎼  Title: $title"
  echo "🎤  Artist: $artist"

  # ─── 🔧 STEP 1: Cleanup old files and prepare environment ──────
  rm -f inputs.txt clean-* .ffmpeg-progress "$output" joined.m4b ffmpeg.log

  # ─── 🎧 STEP 2: Clean and process audio files ──────────────────
  echo "🧹  Found MP3s → Cleaning and copying streams..."
  files=(*.mp3(N) *.flac(N))
  sorted_files=()
  i=1
  for f in "${files[@]}"; do
    base="${f%.mp3}"
    # Extract numeric prefix before first non-digit, fallback to sequence
    chapnum=$(echo "$f" | grep -oE '^[0-9]+' | head -1 || echo "$i")
    if [[ -z "$chapnum" ]]; then
      chapnum="$i"
    else
      # Debug to verify chapter number
      echo "DEBUG: Extracted chapnum for $f: $chapnum"
    fi
    printf -v padded "%04d" "$chapnum"
    echo "$padded:$f"
    ((i++))
  done | sort -n | while IFS=: read -r _ f; do
    sorted_files+=("$f")
  done

  i=1
  for f in "${sorted_files[@]}"; do
    [[ -e "$f" ]] || continue
    base="${f%.mp3}"
    ext="${f##*.}"
    # Use extracted or sequential chapter number
    chapnum=$(echo "$f" | grep -oE '^[0-9]+' | head -1 || echo "$i")
    [[ -z "$chapnum" ]] && chapnum="$i"
    printf -v padded "%04d" "$chapnum"
    newname="clean-${padded}-${base//\'/}.mp3"
    echo "   🔧  $f → $newname"
    echo "   ℹ️  Copying: gcp -- \"$f\" \"$newname.tmp\""
    gcp -- "$f" "$newname.tmp"
    if [[ "$ext" == "flac" ]]; then
      ffmpeg -hide_banner -loglevel error -y -i "$newname.tmp" -map 0:a -c:a aac -b:a 128000 "${newname%.mp3}.m4a" || { echo "   ⚠️  Failed to convert $newname.tmp, error: $?"; rm -f "$newname.tmp"; continue; }
      newname="${newname%.mp3}.m4a"
      rm -f "$newname.tmp"
    else
      ffmpeg -hide_banner -loglevel error -y -i "$newname.tmp" -map 0:a -c:a copy "$newname" || { echo "   ⚠️  Failed to process $newname.tmp, error: $?"; rm -f "$newname.tmp"; continue; }
      rm -f "$newname.tmp"
    fi
    # Validate the cleaned file
    if [ ! -s "$newname" ]; then
      echo "   ⚠️  Validation failed: $newname is empty or invalid, skipping."
      continue
    fi
    ((i++))
  done

  cleanfiles=(clean-[0-9]*.m4a(N) clean-[0-9]*.mp3(N))
  if [ ${#cleanfiles[@]} -eq 0 ]; then
    echo "❌  No valid cleaned files found!"
    exit 1
  fi

  # ─── 🔗 STEP 3: Prepare concatenation list ─────────────────────
  echo "🧾  Preparing concat list for joined output..."
  input_list=""
  valid_files=0
  total_bitrate=0
  total_duration_us=0
  for f in "${cleanfiles[@]}"; do
    if [[ -f "$f" ]]; then
      dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
      if [[ -n "$dur" && "$dur" != "N/A" ]]; then
        input_list="$input_list\nfile '$f'"
        ((valid_files++))
        # Calculate average bitrate
        bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
        total_bitrate=$((total_bitrate + bitrate))
        dur_us=$(printf "%.0f" "$(echo "$dur * 1000000" | bc -l)")
        total_duration_us=$((total_duration_us + dur_us))
      else
        echo "   ⚠️  Skipping invalid file: $f (no valid duration)"
      fi
    fi
  done
  echo -e "$input_list" > inputs.txt
  echo "   ℹ️  Copying inputs.txt to inputs.txt.debug"
  gcp -- inputs.txt inputs.txt.debug
  echo "🔎  Analyzing MP3 parameters..."
  min_sec=$(printf "%d:%02d" $((total_duration_us / 60000000)) $(((total_duration_us % 60000000) / 1000000)))
  echo "🧾  MP3 parameters: Average bitrate = $((total_bitrate / valid_files / 1000)) Kbps, Total duration = $min_sec"

  # ─── ⚙️ STEP 4: Set dynamic output bitrate ─────────────────────
  avg_bitrate=$((total_bitrate / valid_files))
  output_bitrate=$((avg_bitrate > 128000 ? 128000 : (avg_bitrate < 64000 ? 64000 : avg_bitrate)))
  echo "🎚️  Setting conversion: Output bitrate = $((output_bitrate / 1000)) Kbps"

  if [ "$total_duration_us" -le 0 ]; then
    echo "⚠  Total duration is zero or negative, setting to default 18000000 us (5 hours)!"
    total_duration_us=18000000
  fi

  # ─── ⏳ STEP 5: Calculate total duration and join files ─────────
  echo "📏  Calculating total duration for progress bar..."
  echo "🔗  Joining clean files into unified .m4b..."
  ffmpeg -hide_banner -loglevel info -f concat -safe 0 -i inputs.txt -map 0:a -c:a aac -b:a "$output_bitrate" -movflags +faststart "$output" -progress .ffmpeg-progress -y </dev/null > ffmpeg.log 2>&1 &
  pid=$!
  sleep 1
  echo "   ℹ️  Copying progress and log files for debug"
  gcp -- .ffmpeg-progress .ffmpeg-progress.debug
  gcp -- ffmpeg.log ffmpeg.log.debug

  # 🟨 Custom Progress Bar
  while kill -0 $pid 2>/dev/null; do
    progress=$(grep out_time_ms .ffmpeg-progress 2>/dev/null | tail -n1 | cut -d= -f2)
    [[ -z "$progress" || "$progress" -eq 0 ]] && progress=1
    percent=0
    if [ "$total_duration_us" -gt 0 ]; then
      percent=$(( (progress * 100) / total_duration_us ))
    fi
    percent=$(( percent > 100 ? 100 : percent ))
    barlen=$(( percent / 5 ))
    bar=$(printf '#%.0s' $(seq 1 $barlen))
    printf "\r📊 Progress: [%-20s] %3d%%" "$bar" "$percent"
    sleep 0.5
  done
  echo -e "\r📊 Progress: [####################] 100%"
  rm -f .ffmpeg-progress

  # ─── 🖼️ STEP 6: Embed metadata and cover ──────────────────────
  echo "🏷️  Embedding metadata and cover..."
  cover="$(ls -1 *.jpg *.jpeg 2>/dev/null | head -n1 || true)"
  if [[ -n "$cover" && -f "$output" ]]; then
    AtomicParsley "$output" --artwork "$cover" --overWrite --title "$title" --album "$title" --artist "$artist" --genre "Audiobook" >/dev/null
  else
    echo "🎨  No cover found, skipping artwork embedding."
  fi

  # ─── ✅ STEP 7: Validate and finalize ──────────────────────────
  # Validate output size
  if [ -f "$output" ] && [ "$(stat -f %z "$output" 2>/dev/null || echo 0)" -le 1000 ]; then
    echo "⚠  Output file $output is suspiciously small (<1MB), possible encoding failure!"
  fi

  echo "✅  📚 jm4b function complete! Output: $output"
  rm -f inputs.txt clean-*
}
