#!/usr/bin/env bash
set -uo pipefail

SECONDS=0
limit=1000000
temporary=''
file_list=''

cleanup() {
    [[ -z "$temporary" ]] || rm -f -- "$temporary"
    [[ -z "$file_list" ]] || rm -f -- "$file_list"
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ $# -ne 1 || ! -d "$1" ]]; then
    printf 'Uso: bash %s CARTELLA\n' "$0" >&2
    exit 1
fi
for dependency in flock find stat mktemp chmod mv rm mkdir; do
    if ! command -v "$dependency" >/dev/null; then
        printf 'Comando richiesto non trovato: %s\n' "$dependency" >&2
        exit 1
    fi
done
if command -v magick >/dev/null; then
    image=(magick)
    identify=(magick identify)
elif command -v convert >/dev/null && command -v identify >/dev/null; then
    image=(convert)
    identify=(identify)
else
    printf 'Installare ImageMagick con supporto JPEG, PNG e WebP.\n' >&2
    exit 1
fi
root=$(cd -- "$1" && pwd -P) || exit 1
lock_directory="${XDG_RUNTIME_DIR:-/tmp}/imgridim-$UID"
if ! mkdir -m 700 -- "$lock_directory" 2>/dev/null; then
    if [[ ! -d "$lock_directory" || -L "$lock_directory" || ! -O "$lock_directory" ]] ||
        [[ $(stat -c %a -- "$lock_directory") != 700 ]]; then
        printf 'Directory lock non sicura o non accessibile: %s\n' "$lock_directory" >&2
        exit 1
    fi
fi
exec {lock_fd}>>"$lock_directory/run.lock" || exit 1
printf 'Attesa del lock...\n'
lock_started=$SECONDS
flock "$lock_fd" || exit 1
processing_started=$SECONDS
lock_seconds=$((processing_started - lock_started))
file_list=$(mktemp "$lock_directory/files.XXXXXXXX") || exit 1
find "$root" -type f ! -name '.imgridim.*' -print0 > "$file_list" || exit 1

reduce_image() {
    local source=$1 metadata format width height quality size verified
    local -a qualities resize_options
    case "${source,,}" in
        *.jpg|*.jpeg|*.png|*.webp) ;;
        *) return 2 ;;
    esac
    metadata=$("${identify[@]}" -format '%m %w %h\n' - < "$source") || return 1
    if [[ "$metadata" == *$'\n'* ]]; then
        printf 'Ignorata immagine animata/multipagina: %q\n' "$source"
        return 2
    fi
    read -r format width height <<< "$metadata"
    case "$format" in
        JPEG|WEBP) qualities=(90 80 70 60) ;;
        PNG) qualities=(95) ;;
        *) return 2 ;;
    esac
    temporary=$(mktemp "${source%/*}/.imgridim.XXXXXXXX") || return 1
    resize_options=()
    while :; do
        for quality in "${qualities[@]}"; do
            if ! "${image[@]}" - "${resize_options[@]}" -quality "$quality" \
                "$format:$temporary" < "$source"; then
                return 1
            fi
            size=$(stat -c %s -- "$temporary") || return 1
            if (( size > 0 && size <= limit )); then
                verified=$("${identify[@]}" -format '%m' - < "$temporary") || return 1
                [[ "$verified" == "$format" ]] || return 1
                "${image[@]}" - null: < "$temporary" || return 1
                chmod --reference="$source" -- "$temporary" || return 1
                mv -fT -- "$temporary" "$source" || return 1
                temporary=''
                printf 'Ridotta: %q (%s byte)\n' "$source" "$size"
                return 0
            fi
        done
        if (( width == 1 && height == 1 )); then
            printf 'Impossibile raggiungere la soglia: %q\n' "$source" >&2
            return 1
        fi
        width=$((width * 85 / 100))
        height=$((height * 85 / 100))
        (( width > 0 )) || width=1
        (( height > 0 )) || height=1
        resize_options=(-resize "${width}x${height}>")
        [[ "$format" == PNG ]] || qualities=(60)
    done
}

modified=0
skipped=0
errors=0
while IFS= read -r -d '' source; do
    if ! size=$(stat -c %s -- "$source"); then
        errors=$((errors + 1))
        continue
    fi
    if (( size <= limit )); then
        skipped=$((skipped + 1))
        continue
    fi
    reduce_image "$source"
    result=$?
    case "$result" in
        0) modified=$((modified + 1)) ;;
        2) skipped=$((skipped + 1)) ;;
        *)
            printf 'Errore, originale conservato: %q\n' "$source" >&2
            errors=$((errors + 1))
            ;;
    esac
    if [[ -n "$temporary" ]]; then
        rm -f -- "$temporary"
        temporary=''
    fi
done < "$file_list"
printf 'Ridotte: %d; ignorate: %d; errori: %d\n' "$modified" "$skipped" "$errors"
elapsed=$SECONDS
printf 'Tempo totale: %d s; attesa lock: %d s; elaborazione: %d s\n' \
    "$elapsed" "$lock_seconds" "$((elapsed - processing_started))"
(( errors == 0 ))