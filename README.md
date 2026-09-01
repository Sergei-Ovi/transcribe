# transcribe

Локальная RU-распознавалка речи (GigaAM) с горячей клавишей F9 на основе [`transcribe.cpp`](https://github.com/handy-computer/transcribe.cpp).

## Что делает

- **нажми и удерживай F9** — идёт запись с микрофона
- **отпусти F9** — запись останавливается, речь распознаётся (русский язык) и текст автоматически вставляется в текущую позицию курсора

Всё работает локально, без интернета во время распознавания.

## Установка

Склонируй репозиторий (нужны `install.sh` / `install.ps1` и `transcribe.py` в одной папке) и запусти установщик для своей ОС.

### Linux (CachyOS, Arch, Hyprland, KDE Plasma)

```bash
chmod +x install.sh
./install.sh
```

Установщик:

- создаёт Python venv в `~/.local/share/transcribe/` и ставит `transcribe-cpp` (CPU + Vulkan)
- скачивает модель `gigaam-v3-e2e-rnnt-Q8_0.gguf` с Hugging Face
- генерирует `transcribe.sh` для записи и вставки текста
- добавляет бинд F9 в Hyprland (если есть `~/.config/hypr/hyprland.conf`)

Зависимости (Arch / CachyOS):

```bash
sudo pacman -S --needed curl python python-pip alsa-utils ydotool
systemctl --user enable --now ydotoold
```

Debian / Ubuntu:

```bash
sudo apt install curl python3 python3-pip python3-venv alsa-utils ydotool
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

- ставит `transcribe-cpp` в `%LOCALAPPDATA%\transcribe\venv\`
- скачивает модель GigaAM
- скачивает portable **ffmpeg** и **AutoHotkey v2** (если ffmpeg нет в PATH)
- определяет микрофон по умолчанию и сохраняет в `%LOCALAPPDATA%\transcribe\audio_device.txt`
- создаёт ярлык в автозагрузке для F9 (удержание → запись → распознавание → вставка через буфер обмена)

Требуется **Python 3.9+** ([python.org](https://www.python.org/downloads/)).

Другой микрофон: отредактируй `audio_device.txt` или задай переменную `TRANSCRIBE_AUDIO_DEVICE`.

## Использование

### Горячая клавиша

- **нажми F9** — начать запись
- **отпусти F9** — остановить, распознать, вставить текст

### Распознавание файлов вручную

```bash
# конвертация в 16 кГц моно WAV при необходимости
ffmpeg -i input.mp3 -ar 16000 -ac 1 input.wav

~/.local/share/transcribe/venv/bin/python \
  ~/.local/share/transcribe/transcribe.py \
  ~/.local/share/transcribe/models/gigaam-v3-e2e-rnnt-Q8_0.gguf \
  input.wav
```

Windows:

```powershell
& "$env:LOCALAPPDATA\transcribe\venv\Scripts\python.exe" `
  "$env:LOCALAPPDATA\transcribe\transcribe.py" `
  "$env:LOCALAPPDATA\transcribe\models\gigaam-v3-e2e-rnnt-Q8_0.gguf" `
  input.wav
```

## Конфигурация

Параметры в начале `install.sh` / `install.ps1`:

| Переменная | Значение по умолчанию |
|---|---|
| `INSTALL_DIR` | `~/.local/share/transcribe` / `%LOCALAPPDATA%\transcribe` |
| `MODEL_QUANT` | `Q8_0` |
| `MODEL_NAME` | `gigaam-v3-e2e-rnnt` |

Доступные кванты модели (`MODEL_QUANT`): `F32`, `F16`, `Q8_0`, `Q6_K`, `Q5_K_M`, `Q4_K_M`.

Распознавание идёт через Python-пакет [`transcribe-cpp`](https://pypi.org/project/transcribe-cpp/) (официальные биндинги с CPU + Vulkan на Linux/Windows). Отдельного `transcribe-cli` в релизах upstream нет.

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
