#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./deploy.sh [--dry-run] [/caminho/para/raiz-do-cartao]

Exemplos:
  ./deploy.sh
  ./deploy.sh --dry-run
  ./deploy.sh --dry-run /run/media/$USER/EDGETX
  ./deploy.sh /run/media/$USER/EDGETX

Sem um destino, o script procura automaticamente um cartao EdgeTX montado em
/run/media, /media ou /mnt. O destino explicito deve ser a raiz do cartao SD,
onde ficam WIDGETS/ e IMAGES/.

O deploy copia somente os arquivos do widget, audios e imagens. Logs de voo e
/WIDGETS/DBK_TX16KMK3_config.json existentes no radio nunca sao removidos.
EOF
}

dry_run=false
radio_root=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    --*)
      printf 'Erro: opcao desconhecida: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n $radio_root ]]; then
        printf 'Erro: informe no maximo um destino.\n' >&2
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
    printf 'Radio EdgeTX detectado automaticamente: %s\n' "$radio_root"
    return
  fi
  if [[ ${#candidates[@]} -eq 0 ]]; then
    printf 'Erro: nenhum cartao EdgeTX montado foi detectado.\n' >&2
  else
    printf 'Erro: mais de um cartao EdgeTX foi detectado:\n' >&2
    printf '  %s\n' "${candidates[@]}" >&2
  fi
  printf 'Informe a raiz desejada: ./deploy.sh /caminho/para/o/cartao\n' >&2
  exit 1
}

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -z $radio_root ]]; then
  detect_radio_root
fi

if [[ ! -d $radio_root ]]; then
  printf 'Erro: o destino nao existe ou nao e uma pasta: %s\n' "$radio_root" >&2
  exit 1
fi

case $radio_root in
  ""|/|"$project_dir")
    printf 'Erro: destino inseguro: %s\n' "$radio_root" >&2
    exit 1
    ;;
esac

required_files=(
  main.lua
  config.lua
  Image/background.png
  Image/default.png
  Image/hold1.png
  Image/hold2.png
)
for relative_path in "${required_files[@]}"; do
  if [[ ! -f $project_dir/$relative_path ]]; then
    printf 'Erro: arquivo necessario nao encontrado: %s\n' "$relative_path" >&2
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
      printf '[dry-run] Atualizar: %s\n' "$display_path"
    else
      printf '[dry-run] Instalar: %s\n' "$display_path"
    fi
    return
  fi

  mkdir -p -- "$(dirname -- "$destination")"
  cp -p -- "$source" "$destination"
  printf 'Atualizado: %s\n' "$display_path"
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
printf 'Destino do radio: %s\n' "$radio_root"

copy_file "$project_dir/main.lua" "$widget_destination/main.lua"
copy_file "$project_dir/config.lua" "$widget_destination/config.lua"
copy_file "$project_dir/Image/background.png" "$widget_destination/image/background.png"
copy_file "$project_dir/Image/default.png" "$widget_destination/image/default.png"
copy_file "$project_dir/Image/hold1.png" "$widget_destination/image/hold1.png"
copy_file "$project_dir/Image/hold2.png" "$widget_destination/image/hold2.png"
copy_tree_files "$project_dir/audio" "$widget_destination/audio" '*.wav'
copy_tree_files "$project_dir/modelImage" "$radio_root/IMAGES" '*.png'

if $dry_run; then
  printf 'Dry-run concluido; nenhum arquivo foi alterado.\n'
else
  printf 'Deploy do DBK_TX16KMK3 concluido.\n'
fi
