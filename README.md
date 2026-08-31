# transcribe

Локальная RU-распознавалка речи (GigaAM) с горячей клавишей F9 на основе[`transcribe.cpp`](https://github.com/handy-computer/transcribe.cpp).

## Что делает

- **нажми и удерживай F9** — идёт запись с микрофона
- **отпусти F9** — запись останавливается, речь распознаётся (русский язык) и текст автоматически печатается в текущую позицию курсора

Всё работает локально, без интернета во время распознавания.

## Установка

Скопируй `install.sh` на целевую машину и запусти:

```bash
chmod +x install.sh
./install.sh
```

Скрипт скачает:
- бинарь `transcribe-cli` — **последний релиз** с GitHub (определяется автоматически через GitHub API)
- модель `gigaam-v3-e2e-rnnt-Q8_0.gguf` (Hugging Face)
- сгенерирует `transcribe.sh` и добавит бинд F9 в Hyprland

Всё устанавливается в `~/.local/share/transcribe/`.

### Архитектура

Архитектура бинаря определяется автоматически:

| Платформа | Ветка |
|---|---|
| x86_64 + NVIDIA GPU | CUDA |
| x86_64 без GPU | CPU + Vulkan |
| aarch64 / arm64 | CPU + Vulkan |

## Зависимости

- `curl`, `tar` — скачивание и распаковка
- `arecord` (пакет `alsa-utils`) — запись с микрофона
- `xdotool` — автовставка текста
- (необязательно) `unzip`/`ffmpeg`, если нужно распознавать файлы вручную

Установка зависимостей (Debian/Ubuntu):

```bash
sudo apt install curl tar alsa-utils xdotool
```

Если у тебя не Hyprland, вручную добавь бинд F9 с keydown/keyup к подходящему WM (пример для Hyprland):

```bash
bind = , F9, keydown, exec, ~/.local/share/transcribe/transcribe.sh start
bind = , F9, keyup,   exec, ~/.local/share/transcribe/transcribe.sh stop
```

## Использование

### Горячая клавиша

- **нажми F9** — начать запись (пока удерживаешь — идёт запись)
- **отпусти F9** — остановить, распознать, вставить текст в текущую позицию курсора

### Распознавание файлов вручную

```bash
# конвертация в 16 кГц моно WAV при необходимости
ffmpeg -i input.mp3 -ar 16000 -ac 1 input.wav

~/.local/share/transcribe/transcribe-cli \
  -m ~/.local/share/transcribe/models/gigaam-v3-e2e-rnnt-Q8_0.gguf \
  input.wav
```

## Конфигурация

Все параметры задаются переменными в начале `install.sh`:

| Переменная | Значение по умолчанию |
|---|---|
| `INSTALL_DIR` | `~/.local/share/transcribe` |
| `MODEL_QUANT` | `Q8_0` |
| `MODEL_NAME` | `gigaam-v3-e2e-rnnt` |
| `REPO` | `handy-computer/transcribe.cpp` |

Бинарь всегда ставится из **последнего** релиза `REPO` (версия не хардкодится). Модель — последняя доступная под `MODEL_NAME` для выбранного `MODEL_QUANT`.

Доступные кванты модели (`MODEL_QUANT`): `F32`, `F16`, `Q8_0`, `Q6_K`, `Q5_K_M`, `Q4_K_M`.

## Переустановка

Удалить бинарь и модель, чтобы переустановить с нуля:

```bash
rm -rf ~/.local/share/transcribe
```

И убрать строку бинда F9 из `~/.config/hypr/hyprland.conf`.

## Лицензия

- `transcribe.cpp` — MIT
- GigaAM-v3 — MIT (на основе исходной модели)
