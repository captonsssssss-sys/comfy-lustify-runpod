# syntax=docker/dockerfile:1.7

FROM ghcr.io/captonsssssss-sys/comfy-runpod:latest

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Инструменты для загрузки файлов
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Находим реальную папку ComfyUI в базовом образе
# и создаём единый путь /opt/ComfyUI
RUN set -eux; \
    COMFY=""; \
    for DIR in \
        /default-comfyui-bundle/ComfyUI \
        /ComfyUI \
        /workspace/ComfyUI \
        /opt/ComfyUI; \
    do \
        if [ -d "$DIR/models" ]; then \
            COMFY="$DIR"; \
            break; \
        fi; \
    done; \
    test -n "$COMFY"; \
    echo "ComfyUI found at: $COMFY"; \
    if [ "$COMFY" != "/opt/ComfyUI" ]; then \
        rm -rf /opt/ComfyUI; \
        ln -s "$COMFY" /opt/ComfyUI; \
    fi; \
    mkdir -p \
        /opt/ComfyUI/models/checkpoints \
        /opt/ComfyUI/models/loras/speed \
        /opt/ComfyUI/models/upscale_models \
        /opt/ComfyUI/user/default/workflows

# Основной апскейлер
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    "https://huggingface.co/shubhdotai/upscaler/resolve/main/4xNMKDSuperscale_4xNMKDSuperscale.pt" \
    -o "/opt/ComfyUI/models/upscale_models/4xNMKDSuperscale_4xNMKDSuperscale.pt"

# Апскейлер детализации кожи
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/1x-ITF-SkinDiffDetail-Lite-v1.pth" \
    -o "/opt/ComfyUI/models/upscale_models/1x-ITF-SkinDiffDetail-Lite-v1.pth"

# Апскейлер контраста кожи
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    "https://huggingface.co/notkenski/upscalers/resolve/main/1xSkinContrast-High-SuperUltraCompact.pth" \
    -o "/opt/ComfyUI/models/upscale_models/1xSkinContrast-High-SuperUltraCompact.pth"

# DMD2 SDXL 4-step LoRA
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    "https://huggingface.co/tianweiy/DMD2/resolve/main/dmd2_sdxl_4step_lora.safetensors" \
    -o "/opt/ComfyUI/models/loras/speed/dmd2_sdxl_4step_lora.safetensors"

# Lustify GGWP V7
# Civitai-токен берётся из GitHub Repository Secret
RUN --mount=type=secret,id=CIVITAI_TOKEN,required=true \
    CIVITAI_TOKEN="$(cat /run/secrets/CIVITAI_TOKEN)" && \
    curl -L \
        --fail \
        --retry 5 \
        --retry-delay 5 \
        --retry-all-errors \
        -H "Authorization: Bearer ${CIVITAI_TOKEN}" \
        "https://civitai.com/api/download/models/2155386" \
        -o "/opt/ComfyUI/models/checkpoints/lustify_7.safetensors"

# Добавляем workflow в рабочие процессы ComfyUI
COPY LUSTIFY.json /tmp/LUSTIFY.json

RUN install -m 0644 \
    /tmp/LUSTIFY.json \
    /opt/ComfyUI/user/default/workflows/LUSTIFY.json && \
    rm -f /tmp/LUSTIFY.json

# Проверяем наличие всех файлов
RUN test -s "/opt/ComfyUI/models/checkpoints/lustify_7.safetensors" && \
    test -s "/opt/ComfyUI/models/loras/speed/dmd2_sdxl_4step_lora.safetensors" && \
    test -s "/opt/ComfyUI/models/upscale_models/4xNMKDSuperscale_4xNMKDSuperscale.pt" && \
    test -s "/opt/ComfyUI/models/upscale_models/1x-ITF-SkinDiffDetail-Lite-v1.pth" && \
    test -s "/opt/ComfyUI/models/upscale_models/1xSkinContrast-High-SuperUltraCompact.pth" && \
    test -s "/opt/ComfyUI/user/default/workflows/LUSTIFY.json"

# Дополнительная проверка:
# checkpoint должен быть больше 5 ГБ,
# чтобы вместо модели случайно не сохранилась HTML-страница с ошибкой
RUN CHECKPOINT_SIZE="$(stat -c%s /opt/ComfyUI/models/checkpoints/lustify_7.safetensors)" && \
    echo "Lustify checkpoint size: ${CHECKPOINT_SIZE} bytes" && \
    test "${CHECKPOINT_SIZE}" -gt 5000000000
