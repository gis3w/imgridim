# Riduzione ricorsiva immagini

Script per Linux: elabora JPEG, PNG e WebP statici nelle sottocartelle e porta
i file oltre **1.000.000 byte** a una dimensione non superiore a tale soglia.
Nome, percorso e formato rimangono invariati. I file gia entro soglia non
vengono riscritti, nemmeno alle esecuzioni successive.

## Requisiti

Bash 4.4 o successivo, ImageMagick 6 (`convert`, `identify`) oppure 7 (`magick`),
con codec JPEG, PNG e WebP, `flock` (util-linux) e le normali utility GNU.
Su Debian/Ubuntu i pacchetti di riferimento sono `imagemagick` e `util-linux`.
Lo script non installa dipendenze automaticamente e non richiede privilegi root.

## Utilizzo

```bash
bash /data/vcode_projects/imgridim/riduci_immagini.sh "/percorso/immagini"
```

**Provare prima su una copia:** gli originali vengono sostituiti e non viene
creato un backup. Una perdita di qualita e/o risoluzione e possibile.

Per JPEG e WebP vengono provate qualita 90, 80, 70 e 60 senza cambiare i pixel.
PNG viene ricompresso senza perdita. Se non basta, larghezza e altezza vengono
ridotte progressivamente di circa il 15%, mantenendo le proporzioni, con
qualita 60 per JPEG/WebP. Ogni tentativo riparte dall'originale. La soglia
indica la dimensione del file, non il numero di pixel, e non significa
esattamente 1 MB ne 1 MiB (1.048.576 byte).

Il risultato viene scritto in un temporaneo nella stessa cartella e verificato
prima della sostituzione atomica. Se un'immagine non puo essere elaborata,
l'originale resta intatto e l'elaborazione prosegue con gli altri file.
Vengono preservati i permessi Unix; proprietario, ACL, attributi estesi,
timestamp e conservazione integrale dei metadati non sono garantiti.
Non viene effettuata una rimozione esplicita dei metadati.

Si considerano le estensioni `.jpg`, `.jpeg`, `.png`, `.webp`, senza distinzione
tra maiuscole e minuscole, verificando anche il formato effettivo.
Animazioni, immagini multipagina, collegamenti simbolici nelle sottocartelle
e file con altre estensioni vengono ignorati. Il riepilogo conta anche i file
non elaborabili per estensione o gia sotto soglia tra gli ignorati.
Codice di uscita: `0` per completamento senza errori, `1` in presenza di errori.

## Lock e Cron

Il lock e **bloccante**: gli avvii sovrapposti attendono, poi riesaminano i file.
Un solo lock per utente serializza anche scansioni di cartelle diverse:
`${XDG_RUNTIME_DIR:-/tmp}/imgridim-UID/run.lock`, dove UID e l'identificativo
numerico dell'utente. Il file lock resta presente: **non va cancellato**.
Il kernel rilascia il lock alla chiusura dei processi che lo detengono.
Se un figlio ImageMagick sta ancora terminando, il lock resta valido anche
dopo l'arresto del processo Bash.

Usare lo stesso utente e lo stesso `XDG_RUNTIME_DIR` per tutte le invocazioni;
se cron e il terminale hanno ambienti diversi, uniformare questa variabile.
Il lock non coordina altri programmi, utenti diversi o modifiche manuali:
non caricare/modificare immagini durante la scansione. Non e un lock distribuito
per filesystem di rete. Dopo un arresto non gestibile, come SIGKILL o blackout,
puo rimanere un temporaneo `.imgridim.*`, ignorato dalle scansioni successive.

Esempio di crontab, ogni quattro ore, con cartella runtime uniforme per l'utente:

```cron
0 */4 * * * XDG_RUNTIME_DIR=/tmp /bin/bash /data/vcode_projects/imgridim/riduci_immagini.sh /srv/immagini >> /percorso/scrivibile/imgridim.log 2>&1
```

Adattare i percorsi e usare `XDG_RUNTIME_DIR=/tmp` anche negli avvii manuali
da coordinare con questo esempio. Il cron non viene installato dallo script.
Se una scansione dura piu dell'intervallo, gli avvii si accodano: scegliere
una frequenza adeguata. I messaggi riportano i nomi con escaping Bash.

## Test

```bash
bash -n riduci_immagini.sh test_riduci_immagini.sh
bash test_riduci_immagini.sh
```

I test generano immagini in una cartella temporanea, senza modificare immagini
esistenti. Richiedono anche `sha256sum`, `truncate` e `cp` (GNU coreutils).
