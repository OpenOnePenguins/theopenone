#!/usr/bin/env bash
# Regenerates the film's audio (and, with the key's image_video_generation permission, its footage).
# Requires ELEVENLABS_API_KEY. Music takes are not deterministic: after a new score, re-measure the
# beat grid (see src/timeline.ts) before rendering.
set -euo pipefail
cd "$(dirname "$0")/.."
api=https://api.elevenlabs.io/v1
auth=(-H "xi-api-key: $ELEVENLABS_API_KEY" -H "Content-Type: application/json")

case "${1:-}" in
  score)
    curl -sf -X POST "$api/music?output_format=mp3_44100_192" "${auth[@]}" -d @scripts/score-prompt.json -o public/score.mp3 ;;
  sfx)
    gen() { curl -sf -X POST "$api/sound-generation?output_format=mp3_44100_192" "${auth[@]}" \
      -d "{\"text\":\"$2\",\"duration_seconds\":$3,\"prompt_influence\":0.6}" -o "public/sfx/$1.mp3"; }
    gen key "single soft mechanical keyboard key press, deep muted thock, close mic, dry, no reverb" 0.5
    gen pop "cute soft rounded bubble pop, modern UI notification, clean" 0.5
    gen whoosh "soft airy short whoosh swipe transition, clean, modern product video" 0.8
    gen chime "gentle two-note smartphone notification chime, clean, warm, short" 1.0
    gen send "quick light swoosh for a message being sent, modern UI, short" 0.5
    gen typing "soft fast typing on a premium laptop keyboard, about eight keystrokes, close mic, dry" 1.6
    gen tick "tiny soft UI tick click, very short, clean" 0.5
    gen shimmer "soft magical sparkle shimmer swell, airy, gentle, for a logo reveal" 2.0 ;;
  footage)
    # Each finished clip lands in public/footage/<name>.mp4 and replaces that procedural scene.
    mkdir -p public/footage
    shot() {
      local name=$1 body id url status
      body=$(python3 -c 'import json,sys; print(json.dumps({"model_id":"veo-3.1-generate-001","prompt":sys.argv[1],"duration_secs":int(sys.argv[2]),"aspect_ratio":"16:9","resolution":"1080p","generate_audio":False}))' "$2" "${3:-4}")
      id=$(curl -sf -X POST "$api/flows/video" "${auth[@]}" -d "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
      while :; do
        sleep 10
        status=$(curl -sf "$api/flows/video/$id" "${auth[@]}")
        case $(printf %s "$status" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])') in
          completed) url=$(printf %s "$status" | python3 -c 'import json,sys; print(json.load(sys.stdin)["content_url"])')
                     curl -sf "$url" -o "public/footage/$name.mp4" && echo "$name ok"; return ;;
          failed) echo "$name failed" >&2; return ;;
        esac
      done
    }
    shot pool "An emperor penguin standing at the edge of an infinity pool on a cliffside villa above a deep blue Mediterranean bay with white sailboats, bright sun, slow drift, cinematic, no text" &
    shot village "Telephoto shot of a line of emperor penguins waddling down a sun-bleached whitewashed Greek island street with blue doors and bougainvillea, heat haze, cinematic, no text" &
    shot beach "Wide shot of a tropical palm beach at sunset, golden sky with soft clouds, gentle waves, a single emperor penguin on the wet sand in the lower left, large empty sky, slow dolly, cinematic 35mm film, no text" &
    shot lavender "The emperor penguin stands between lavender rows in Provence at golden hour, slowly turning its head toward the sunset; lavender sways in a warm breeze; calm clear sky; very slow push in; photorealistic, no text" &
    wait ;;
  *) echo "usage: $0 score|sfx|footage" >&2; exit 1 ;;
esac
