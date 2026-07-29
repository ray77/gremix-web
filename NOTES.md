# Ghouls'n Ghosts Remix — Browser-Bau

Unsere Fassung des GPL-Remakes von Valarsoft, übersetzt nach WebAssembly und
live auf arcade4ever als Spiel `gremix` (id 33).

`src/` ist **unsere** Fassung, nicht das Original: sie enthält den
Punktehaken und die Browser-Anpassungen (3× `EM_ASM`, 23× `__EMSCRIPTEN__`).
Das unveränderte Original liegt unter `~/Downloads/g_remix`.

## Warum es diese Ablage gibt

Der emcc-Aufruf war **nirgends festgehalten**. Bei jedem anderen Spiel des
Arcade ritt das Bauskript im ausgelieferten `src.zip` mit und überlebte damit;
hier stand es nur im Arbeitsverzeichnis, und das wurde aufgeräumt.

Am 2026-07-29 aus der überlebenden Umgebung neu hergeleitet und **durch Bauen
überprüft** — `build_web.sh` übersetzt und bindet fehlerfrei.

## Was noch fehlt

Der **Materialsatz** ist nicht rekonstruiert. Roh sind es 170 MB
(`maps/` 87 MB, `obj/` 62 MB), das ausgelieferte `gremix.data` hat 26 MB. Weggelassen
wurden nur 41 Dateien mit zusammen unter 1 MB — die Karten und Objekte müssen
also in Allegro-Datenpakete überführt worden sein (das Paket enthält 32
`.dat`-Dateien). Wie, ist offen.

**Ein Bau mit `build_web.sh` erzeugt heute ein 178-MB-Datenpaket statt 26 MB.**
Bevor irgendetwas ausgeliefert wird, muss dieser Schritt geklärt sein.

## Zutaten

| | |
|---|---|
| Umgebung | `~/Developer/allegro-web` — `Allegro-Legacy/build-web` (einfädrig), `prefix` (A5, gegen SDL gebaut), `midia5_web_stubs.c`, `tsf.h`, `TimGM6mb.sf2` |
| Original samt Rohmaterial | `~/Downloads/g_remix` |
| Ausgeliefertes Erzeugnis | `arcade4ever/htdocs/games/gremix/` |

## Fallen, die Zeit gekostet haben

- **`-sUSE_SDL=2` ist Pflicht.** Das Allegro 5 im `prefix` wurde gegen SDL
  gebaut; ohne den Schalter bricht das Binden mit `SDL_OpenAudioDevice`,
  `SDL_LockMutex` und einem Dutzend weiterer ab.
- **Getrennt übersetzen.** `-std=gnu++98` gilt nicht für die C-Datei der Stubs;
  ein gemeinsamer Aufruf scheitert sofort.
- **Ein Spielschritt pro Bild.** Im Web-Zweig von `rePaint()` ist die Bremse auf
  `MFPS = 60` wegkompiliert, ohne Ersatz. Die Spielgeschwindigkeit hängt damit
  an der Bildrate: 30 fps sind halbe Geschwindigkeit. Ein Spieler meldete
  Zeitlupe und maß 10 fps, zeitweise 5. Das ist der offene Hauptfehler.
- **Bild und Ton hängen an derselben Schleife.** Ein Versuch, den
  Grafikschalter `preserveDrawingBuffer` abzuschalten (er kostet Bilder), führte
  zu Falschtönen. Wer den Takt anfasst, muss den Ton mitprüfen.
- **Die Bildrate messen:** `games/gremix/index.html?fps` zeigt sie an. Der Zähler
  muss im `<head>` vor dem Spielskript sitzen — Emscripten merkt sich
  `requestAnimationFrame` beim Start. Erst nach dem Laden ablesen.
- Der spieleigene FPS-Zähler ist **nicht** erreichbar: er hängt an `DBUG` (F8)
  *und* am Bauschalter `DEBUG`, der ausgeliefert aus ist. F5 ist ohnehin die
  Neuladen-Taste des Browsers.
