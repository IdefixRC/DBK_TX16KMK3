#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./deploy.sh [-v] [--dry-run] [/path/to/card-root]

Examples:
  ./deploy.sh
  ./deploy.sh -v
  ./deploy.sh -v /run/media/$USER/EDGETX
  ./deploy.sh --dry-run
  ./deploy.sh --dry-run /run/media/$USER/EDGETX
  ./deploy.sh /run/media/$USER/EDGETX

Without a destination, the script automatically looks for an EdgeTX card
mounted under /run/media, /media or /mnt. An explicit destination must be the
root of the SD card, the level that holds WIDGETS/ and IMAGES/.

The deploy copies only the widget files, audio and images. Flight logs and an
existing /WIDGETS/DBK_TX16KMK3_config.json on the radio are never removed.

With -v, the script queries the releases published on GitHub, lists the 10 most
recent versions and installs the one you pick. That mode needs curl, unzip and
internet access.
EOF
}

dry_run=false
release_mode=false
radio_root=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -v) release_mode=true ;;
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n $radio_root ]]; then
        printf 'Error: give at most one destination.\n' >&2
        usage >&2
        exit 2
      fi
      radio_root=${1%/}
      ;;
  esac
  shift
done

is_edgetx_root() {
  local candidate=$1
  [[ -d $candidate/WIDGETS ]] || return 1
  [[ -d $candidate/RADIO || -d $candidate/SCRIPTS || -d $candidate/SOUNDS \
     || -d $candidate/IMAGES ]]
}

detect_radio_root() {
  local default_roots="/run/media/${USER:-}:/media/${USER:-}:/run/media:/media:/mnt"
  local configured_roots=${DBK_TX16KMK3_MOUNT_ROOTS:-$default_roots}
  local search_root candidate
  local -a roots candidates=()
  local -A seen=()
  IFS=: read -r -a roots <<< "$configured_roots"

  for search_root in "${roots[@]}"; do
    [[ -n $search_root && -d $search_root ]] || continue
    if is_edgetx_root "$search_root" && [[ -z ${seen["$search_root"]+x} ]]; then
      candidates+=("$search_root")
      seen["$search_root"]=1
    fi
    while IFS= read -r -d '' candidate; do
      is_edgetx_root "$candidate" || continue
      [[ -z ${seen["$candidate"]+x} ]] || continue
      candidates+=("$candidate")
      seen["$candidate"]=1
    done < <(find "$search_root" -mindepth 1 -maxdepth 2 -type d -print0 2>/dev/null)
  done

  if [[ ${#candidates[@]} -eq 1 ]]; then
    radio_root=${candidates[0]}
    printf 'EdgeTX radio detected automatically: %s\n' "$radio_root"
    return
  fi
  if [[ ${#candidates[@]} -eq 0 ]]; then
    printf 'Error: no mounted EdgeTX card was detected.\n' >&2
  else
    printf 'Error: more than one EdgeTX card was detected:\n' >&2
    printf '  %s\n' "${candidates[@]}" >&2
  fi
  printf 'Name the root you want: ./deploy.sh /path/to/the/card\n' >&2
  exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir=$script_dir
temporary_dir=""
selected_release=""

cleanup() {
  if [[ -n $temporary_dir && -d $temporary_dir ]]; then
    rm -rf -- "$temporary_dir"
  fi
}
trap cleanup EXIT

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Error: -v mode requires the %s command.\n' "$command_name" >&2
    exit 1
  fi
}

select_release() {
  require_command curl
  require_command unzip

  local api_url="https://api.github.com/repos/vhuzalo/DBK_TX16KMK3/releases?per_page=10"
  local release_json selection selected_tag asset_url archive_path
  local -a release_tags=()

  printf 'Querying releases on GitHub...\n'
  if ! release_json=$(curl -fsSL --retry 2 --connect-timeout 10 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' "$api_url"); then
    printf 'Error: could not query the releases on GitHub.\n' >&2
    exit 1
  fi

  mapfile -t release_tags < <(
    printf '%s\n' "$release_json" \
      | sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)",*$/\1/p' \
      | head -n 10
  )
  if [[ ${#release_tags[@]} -eq 0 ]]; then
    printf 'Error: no published release was found.\n' >&2
    exit 1
  fi

  printf 'Available versions:\n'
  local index
  for index in "${!release_tags[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${release_tags[index]}"
  done
  printf '  0) Cancel\n'
  printf 'Choose a version: '
  if ! read -r selection; then
    printf '\nError: could not read the chosen version.\n' >&2
    exit 1
  fi
  if [[ $selection == 0 ]]; then
    printf 'Installation cancelled.\n'
    exit 0
  fi
  if [[ ! $selection =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#release_tags[@]} )); then
    printf 'Error: invalid choice: %s\n' "$selection" >&2
    exit 2
  fi

  selected_tag=${release_tags[selection - 1]}
  if [[ ! $selected_tag =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Error: invalid release tag: %s\n' "$selected_tag" >&2
    exit 1
  fi

  temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/dbk-tx16kmk3-release.XXXXXX")
  archive_path=$temporary_dir/DBK_TX16KMK3.zip
  asset_url="https://github.com/vhuzalo/DBK_TX16KMK3/releases/download/$selected_tag/DBK_TX16KMK3-$selected_tag.zip"
  printf 'Downloading DBK_TX16KMK3 %s...\n' "$selected_tag"
  if ! curl -fL --retry 2 --connect-timeout 10 -o "$archive_path" "$asset_url"; then
    printf 'Error: could not download the package for release %s.\n' "$selected_tag" >&2
    exit 1
  fi
  if ! unzip -tq "$archive_path" >/dev/null; then
    printf 'Error: the downloaded package is corrupt or not a valid ZIP.\n' >&2
    exit 1
  fi
  if ! unzip -q "$archive_path" -d "$temporary_dir"; then
    printf 'Error: could not extract the release package.\n' >&2
    exit 1
  fi

  source_dir=$temporary_dir/DBK_TX16KMK3
  if [[ ! -d $source_dir ]]; then
    printf 'Error: unexpected structure in the package for release %s.\n' "$selected_tag" >&2
    exit 1
  fi
  selected_release=$selected_tag
  printf 'Selected release: %s\n' "$selected_tag"
}

if $release_mode; then
  select_release
fi

if [[ -z $radio_root ]]; then
  detect_radio_root
fi

if [[ ! -d $radio_root ]]; then
  printf 'Error: the destination does not exist or is not a folder: %s\n' "$radio_root" >&2
  exit 1
fi

case $radio_root in
  ""|/|"$script_dir")
    printf 'Error: unsafe destination: %s\n' "$radio_root" >&2
    exit 1
    ;;
esac

required_files=(
  main.lua
  image/background.png
  image/default.png
  image/hold1.png
  image/hold2.png
)
if ! $release_mode; then
  required_files+=(config.lua)
fi
for relative_path in "${required_files[@]}"; do
  if [[ ! -f $source_dir/$relative_path ]]; then
    printf 'Error: required file not found: %s\n' "$relative_path" >&2
    exit 1
  fi
done

copy_file() {
  local source=$1
  local destination=$2
  local display_path=${destination#"$radio_root"/}

  if [[ -f $destination ]] && cmp -s -- "$source" "$destination"; then
    return
  fi
  if $dry_run; then
    if [[ -e $destination ]]; then
      printf '[dry-run] Update: %s\n' "$display_path"
    else
      printf '[dry-run] Install: %s\n' "$display_path"
    fi
    return
  fi

  mkdir -p -- "$(dirname -- "$destination")"
  cp -p -- "$source" "$destination"
  printf 'Updated: %s\n' "$display_path"
}

copy_tree_files() {
  local source_dir=$1
  local destination_dir=$2
  local pattern=$3
  local source relative_path

  [[ -d $source_dir ]] || return
  while IFS= read -r -d '' source; do
    relative_path=${source#"$source_dir"/}
    copy_file "$source" "$destination_dir/$relative_path"
  done < <(find "$source_dir" -type f -name "$pattern" -print0)
}

widget_destination=$radio_root/WIDGETS/DBK_TX16KMK3
printf 'Radio destination: %s\n' "$radio_root"

copy_file "$source_dir/main.lua" "$widget_destination/main.lua"
if [[ -f $source_dir/config.lua ]]; then
  copy_file "$source_dir/config.lua" "$widget_destination/config.lua"
fi
copy_file "$source_dir/image/background.png" "$widget_destination/image/background.png"
copy_file "$source_dir/image/default.png" "$widget_destination/image/default.png"
copy_file "$source_dir/image/hold1.png" "$widget_destination/image/hold1.png"
copy_file "$source_dir/image/hold2.png" "$widget_destination/image/hold2.png"
copy_tree_files "$source_dir/audio" "$widget_destination/audio" '*.wav'

if $dry_run; then
  printf 'Dry-run finished; no file was changed.\n'
elif [[ -n $selected_release ]]; then
  printf 'DBK_TX16KMK3 %s deploy finished.\n' "$selected_release"
else
  printf 'DBK_TX16KMK3 deploy finished.\n'
fi
