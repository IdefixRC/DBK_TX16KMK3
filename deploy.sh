#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./deploy.sh [-v] [--dry-run] [/caminho/para/raiz-do-cartao]

Exemplos:
  ./deploy.sh
  ./deploy.sh -v
  ./deploy.sh -v /run/media/$USER/EDGETX
  ./deploy.sh --dry-run
  ./deploy.sh --dry-run /run/media/$USER/EDGETX
  ./deploy.sh /run/media/$USER/EDGETX

Sem um destino, o script procura automaticamente um cartao EdgeTX montado em
/run/media, /media ou /mnt. O destino explicito deve ser a raiz do cartao SD,
onde ficam WIDGETS/ e IMAGES/.

O deploy copia somente os arquivos do widget, audios e imagens. Logs de voo e
/WIDGETS/DBK_TX16KMK3_config.json existentes no radio nunca sao removidos.

Com -v, o script consulta os releases publicados no GitHub, mostra as 10
versoes mais recentes e instala a versao escolhida. Esse modo requer curl,
unzip e acesso a internet.
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
    printf 'Erro: o modo -v requer o comando %s.\n' "$command_name" >&2
    exit 1
  fi
}

select_release() {
  require_command curl
  require_command unzip

  local api_url="https://api.github.com/repos/vhuzalo/DBK_TX16KMK3/releases?per_page=10"
  local release_json selection selected_tag asset_url archive_path
  local -a release_tags=()

  printf 'Consultando releases no GitHub...\n'
  if ! release_json=$(curl -fsSL --retry 2 --connect-timeout 10 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' "$api_url"); then
    printf 'Erro: nao foi possivel consultar os releases no GitHub.\n' >&2
    exit 1
  fi

  mapfile -t release_tags < <(
    printf '%s\n' "$release_json" \
      | sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)",*$/\1/p' \
      | head -n 10
  )
  if [[ ${#release_tags[@]} -eq 0 ]]; then
    printf 'Erro: nenhum release publicado foi encontrado.\n' >&2
    exit 1
  fi

  printf 'Versoes disponiveis:\n'
  local index
  for index in "${!release_tags[@]}"; do
    printf '  %d) %s\n' "$((index + 1))" "${release_tags[index]}"
  done
  printf '  0) Cancelar\n'
  printf 'Escolha uma versao: '
  if ! read -r selection; then
    printf '\nErro: nao foi possivel ler a versao escolhida.\n' >&2
    exit 1
  fi
  if [[ $selection == 0 ]]; then
    printf 'Instalacao cancelada.\n'
    exit 0
  fi
  if [[ ! $selection =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#release_tags[@]} )); then
    printf 'Erro: escolha invalida: %s\n' "$selection" >&2
    exit 2
  fi

  selected_tag=${release_tags[selection - 1]}
  if [[ ! $selected_tag =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Erro: tag de release invalida: %s\n' "$selected_tag" >&2
    exit 1
  fi

  temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/dbk-tx16kmk3-release.XXXXXX")
  archive_path=$temporary_dir/DBK_TX16KMK3.zip
  asset_url="https://github.com/vhuzalo/DBK_TX16KMK3/releases/download/$selected_tag/DBK_TX16KMK3-$selected_tag.zip"
  printf 'Baixando DBK_TX16KMK3 %s...\n' "$selected_tag"
  if ! curl -fL --retry 2 --connect-timeout 10 -o "$archive_path" "$asset_url"; then
    printf 'Erro: nao foi possivel baixar o pacote do release %s.\n' "$selected_tag" >&2
    exit 1
  fi
  if ! unzip -tq "$archive_path" >/dev/null; then
    printf 'Erro: o pacote baixado esta corrompido ou nao e um ZIP valido.\n' >&2
    exit 1
  fi
  if ! unzip -q "$archive_path" -d "$temporary_dir"; then
    printf 'Erro: nao foi possivel extrair o pacote do release.\n' >&2
    exit 1
  fi

  source_dir=$temporary_dir/DBK_TX16KMK3
  if [[ ! -d $source_dir ]]; then
    printf 'Erro: estrutura inesperada no pacote do release %s.\n' "$selected_tag" >&2
    exit 1
  fi
  selected_release=$selected_tag
  printf 'Release selecionado: %s\n' "$selected_tag"
}

if $release_mode; then
  select_release
fi

if [[ -z $radio_root ]]; then
  detect_radio_root
fi

if [[ ! -d $radio_root ]]; then
  printf 'Erro: o destino nao existe ou nao e uma pasta: %s\n' "$radio_root" >&2
  exit 1
fi

case $radio_root in
  ""|/|"$script_dir")
    printf 'Erro: destino inseguro: %s\n' "$radio_root" >&2
    exit 1
    ;;
esac

required_files=(
  main.lua
  Image/background.png
  Image/default.png
  Image/hold1.png
  Image/hold2.png
)
if ! $release_mode; then
  required_files+=(config.lua)
fi
for relative_path in "${required_files[@]}"; do
  if [[ ! -f $source_dir/$relative_path ]]; then
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

copy_file "$source_dir/main.lua" "$widget_destination/main.lua"
if [[ -f $source_dir/config.lua ]]; then
  copy_file "$source_dir/config.lua" "$widget_destination/config.lua"
fi
copy_file "$source_dir/Image/background.png" "$widget_destination/image/background.png"
copy_file "$source_dir/Image/default.png" "$widget_destination/image/default.png"
copy_file "$source_dir/Image/hold1.png" "$widget_destination/image/hold1.png"
copy_file "$source_dir/Image/hold2.png" "$widget_destination/image/hold2.png"
copy_tree_files "$source_dir/audio" "$widget_destination/audio" '*.wav'
copy_tree_files "$source_dir/modelImage" "$radio_root/IMAGES" '*.png'

if $dry_run; then
  printf 'Dry-run concluido; nenhum arquivo foi alterado.\n'
elif [[ -n $selected_release ]]; then
  printf 'Deploy do DBK_TX16KMK3 %s concluido.\n' "$selected_release"
else
  printf 'Deploy do DBK_TX16KMK3 concluido.\n'
fi
