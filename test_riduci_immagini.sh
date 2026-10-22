#!/usr/bin/env bash
set -euo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/riduci_immagini.sh"
workspace=$(mktemp -d)
waiting_pid=''
trap '[[ -z "$waiting_pid" ]] || kill "$waiting_pid" 2>/dev/null || :; rm -rf -- "$workspace"' EXIT
export XDG_RUNTIME_DIR="$workspace/runtime"
mkdir -p "$XDG_RUNTIME_DIR" "$workspace/images/sotto cartella" "$workspace/lock-test"
if command -v magick >/dev/null; then
    image=(magick)
    identify=(magick identify)
else
    image=(convert)
    identify=(identify)
fi
images="$workspace/images"
jpeg="$images/sotto cartella/"$'-foto\n[1].JPG'
"${image[@]}" -size 1100x1100 xc: +noise Random -depth 8 -quality 100 "JPEG:$jpeg"
"${image[@]}" -size 900x900 xc: +noise Random -depth 8 "$images/foto.png"
"${image[@]}" -size 900x900 xc: +noise Random -depth 8 \
    -define webp:lossless=true "$images/foto.webp"
for source in "$jpeg" "$images/foto.png" "$images/foto.webp"; do
    test "$(stat -c %s -- "$source")" -gt 1000000
done
cp -- "$jpeg" "$workspace/original.jpg"
chmod 640 -- "$jpeg"
"${image[@]}" -size 20x20 xc:red "$images/piccola.png"
cp -- "$images/piccola.png" "$images/esatta.png"
truncate -s 1000000 "$images/esatta.png"
truncate -s 1000001 "$images/non-immagine.txt"
"${image[@]}" -size 20x20 xc:red -size 20x20 xc:blue -delay 10 -loop 0 "$images/animata.webp"
truncate -s 1000001 "$images/animata.webp"
ln -s "$workspace/original.jpg" "$images/link.jpg"
unchanged=$(sha256sum -- "$images/piccola.png" "$images/esatta.png" \
    "$images/animata.webp" "$images/non-immagine.txt" "$workspace/original.jpg")
bash "$script" "$images"
test "$unchanged" = "$(sha256sum -- "$images/piccola.png" "$images/esatta.png" \
    "$images/animata.webp" "$images/non-immagine.txt" "$workspace/original.jpg")"
test -L "$images/link.jpg"
test "$(stat -c %a -- "$jpeg")" = 640
for source in "$jpeg" "$images/foto.png" "$images/foto.webp"; do
    test "$(stat -c %s -- "$source")" -le 1000000
    "${image[@]}" - null: < "$source"
done
test "$("${identify[@]}" -format %m - < "$jpeg")" = JPEG
test "$("${identify[@]}" -format %m "$images/foto.png")" = PNG
test "$("${identify[@]}" -format %m "$images/foto.webp")" = WEBP
before=$(find "$images" -type f -exec sha256sum -- {} +)
bash "$script" "$images"
test "$before" = "$(find "$images" -type f -exec sha256sum -- {} +)"

truncate -s 1000001 "$images/rotta.jpg"
broken=$(sha256sum "$images/rotta.jpg")
cp "$workspace/original.jpg" "$images/ancora.jpg"
if bash "$script" "$images"; then
    printf 'ERRORE: immagine corrotta non segnalata\n' >&2
    exit 1
fi
test "$broken" = "$(sha256sum "$images/rotta.jpg")"
test "$(stat -c %s "$images/ancora.jpg")" -le 1000000
test -z "$(find "$images" -name '.imgridim.*' -print)"
rm "$images/rotta.jpg"

cp "$workspace/original.jpg" "$workspace/lock-test/foto.jpg"
before=$(sha256sum "$workspace/lock-test/foto.jpg")
exec 9>>"$XDG_RUNTIME_DIR/imgridim-$UID/run.lock"
flock 9
coproc WAITING { bash "$script" "$workspace/lock-test" 9>&-; }
waiting_pid=$WAITING_PID
exec {output_fd}<&"${WAITING[0]}"
IFS= read -r message <&"$output_fd"
test "$message" = 'Attesa del lock...'
kill -0 "$waiting_pid"
test "$before" = "$(sha256sum "$workspace/lock-test/foto.jpg")"
flock -u 9
exec 9>&-
cat <&"$output_fd"
wait "$waiting_pid"
waiting_pid=''
exec {output_fd}<&-
test "$(stat -c %s "$workspace/lock-test/foto.jpg")" -le 1000000
flock -n "$XDG_RUNTIME_DIR/imgridim-$UID/run.lock" true
if bash "$script" "$workspace/inesistente"; then
    exit 1
fi
printf 'OK: formati, soglia, ricorsione, nomi speciali, idempotenza, errori e lock.\n'