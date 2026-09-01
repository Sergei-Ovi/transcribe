# transcribe

Локальная RU-распознавалка речи (GigaAM) с горячей клавишей F9 на основе [`transcribe.cpp`](https://github.com/handy-computer/transcribe.cpp).

## Что делает

- **нажми и удерживай F9** — идёт запись с микрофона
- **отпусти F9** — запись останавливается, речь распознаётся (русский язык) и текст автоматически вставляется в текущую позицию курсора

Всё работает локально, без интернета во время распознавания. Python не нужен.

## Первый релиз (для мейнтейнера)

Бинарники `transcribe-cli` собираются в GitHub Actions и публикуются в [Releases](https://github.com/Sergei-Ovi/transcribe/releases):

```bash
git tag v1.0.0
git push origin v1.0.0
```

После завершения workflow установщики смогут скачать CLI из latest release.

## Установка

Склонируй репозиторий и запусти установщик для своей ОС.

### Linux (CachyOS, Arch, Hyprland, KDE Plasma)

```bash
chmod +x install.sh transcribe.sh
./install.sh
```

Установщик:

- скачивает `transcribe-cli` из GitHub Releases (Vulkan на x86_64)
- скачивает модель `gigaam-v3-e2e-rnnt-Q8_0.gguf` с Hugging Face
- копирует `transcribe.sh` в `~/.local/share/transcribe/`
- добавляет бинд F9 в Hyprland (если есть `~/.config/hypr/hyprland.conf`)

Зависимости (Arch / CachyOS):

```bash
sudo pacman -S --needed curl alsa-utils ydotool
systemctl --user enable --now ydotoold
```

Debian / Ubuntu:

```bash
sudo apt install curl alsa-utils ydotool
systemctl --user enable --now ydotoold
```

#### KDE Plasma

В **System Settings → Shortcuts → Custom Shortcuts** создай два шортката на `~/.local/share/transcribe/transcribe.sh`:

| Действие | Команда | Триггер |
|---|---|---|
| Начать запись | `~/.local/share/transcribe/transcribe.sh start` | F9, при нажатии |
| Остановить | `~/.local/share/transcribe/transcribe.sh stop` | F9, при отпускании |

#### Hyprland

Бинд добавляется автоматически. Вручную:

```bash
bind = , F9, keydown, exec, ~/.local/share/transcribe/transcribe.sh start
bind = , F9, keyup,   exec, ~/.local/share/transcribe/transcribe.sh stop
```

### Windows

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\install.ps1
```

Установщик:

- скачивает `transcribe-cli.exe` из GitHub Releases
- скачивает модель GigaAM
- скачивает portable **ffmpeg** и **AutoHotkey v2** (если ffmpeg нет в PATH)
- определяет микрофон по умолчанию и сохраняет в `%LOCALAPPDATA%\transcribe\audio_device.txt`
- создаёт ярлык в автозагрузке для F9 (удержание → запись → распознавание → вставка через буфер обмена)

Другой микрофон: отредактируй `audio_device.txt` или задай переменную `TRANSCRIBE_AUDIO_DEVICE`.

## Использование

### Горячая клавиша

- **нажми F9** — начать запись
- **отпусти F9** — остановить, распознать, вставить текст

### Распознавание файлов вручную

```bash
# конвертация в 16 кГц моно WAV при необходимости
ffmpeg -i input.mp3 -ar 16000 -ac 1 input.wav

~/.local/share/transcribe/transcribe-cli \
  -m ~/.local/share/transcribe/models/gigaam-v3-e2e-rnnt-Q8_0.gguf \
  input.wav
```

Windows:

```powershell
& "$env:LOCALAPPDATA\transcribe\transcribe-cli.exe" `
  -m "$env:LOCALAPPDATA\transcribe\models\gigaam-v3-e2e-rnnt-Q8_0.gguf" `
  input.wav
```

## Конфигурация

| Переменная | Значение по умолчанию |
|---|---|
| `INSTALL_DIR` | `~/.local/share/transcribe` / `%LOCALAPPDATA%\transcribe` |
| `MODEL_QUANT` | `Q8_0` |
| `MODEL_NAME` | `gigaam-v3-e2e-rnnt` |
| `TRANSCRIBE_RELEASE_REPO` | `Sergei-Ovi/transcribe` |

Доступные кванты модели (`MODEL_QUANT`): `F32`, `F16`, `Q8_0`, `Q6_K`, `Q5_K_M`, `Q4_K_M`.

`transcribe-cli` собирается из [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) v0.2.3 в CI (Linux: Vulkan, Windows: CPU). Upstream не публикует готовый CLI в своих релизах.

## Переустановка

Linux:

```bash
rm -rf ~/.local/share/transcribe
# убрать бинд F9 из ~/.config/hypr/hyprland.conf при необходимости
```

Windows:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\transcribe"
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\transcribe.lnk" -ErrorAction SilentlyContinue
```

## Лицензия

- `transcribe.cpp` — MIT
- GigaAM-v3 — MIT (на основе исходной модели)
