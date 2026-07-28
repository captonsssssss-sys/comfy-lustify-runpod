# syntax=docker/dockerfile:1.7

FROM ghcr.io/captonsssssss-sys/comfy-runpod:latest

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Устанавливаем инструменты загрузки
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Находим ComfyUI внутри базового образа и создаём единый путь
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
    if [ "$COMFY" != "/opt/ComfyUI" ]; then \
        rm -rf /opt/ComfyUI; \
        ln -s "$COMFY" /opt/ComfyUI; \
    fi; \
    mkdir -p \
        /opt/ComfyUI/models/checkpoints \
        /opt/ComfyUI/models/loras/speed \
        /opt/ComfyUI/models/upscale_models

# Основной апскейлер
RUN curl -L --fail --retry 5 \
    "https://huggingface.co/shubhdotai/upscaler/resolve/main/4xNMKDSuperscale_4xNMKDSuperscale.pt" \
    -o "/opt/ComfyUI/models/upscale_models/4xNMKDSuperscale_4xNMKDSuperscale.pt"

# Апскейлер детализации кожи
RUN curl -L --fail --retry 5 \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/1x-ITF-SkinDiffDetail-Lite-v1.pth" \
    -o "/opt/ComfyUI/models/upscale_models/1x-ITF-SkinDiffDetail-Lite-v1.pth"

# Апскейлер контраста кожи
RUN curl -L --fail --retry 5 \
    "https://huggingface.co/notkenski/upscalers/resolve/main/1xSkinContrast-High-SuperUltraCompact.pth" \
    -o "/opt/ComfyUI/models/upscale_models/1xSkinContrast-High-SuperUltraCompact.pth"

# DMD2 SDXL 4-step LoRA
RUN curl -L --fail --retry 5 \
    "https://huggingface.co/tianweiy/DMD2/resolve/main/dmd2_sdxl_4step_lora.safetensors" \
    -o "/opt/ComfyUI/models/loras/speed/dmd2_sdxl_4step_lora.safetensors"

# Lustify GGWP V7 с Civitai.
# Токен будет передан через защищённый GitHub Secret.
RUN --mount=type=secret,id=CIVITAI_TOKEN,required=true \
    CIVITAI_TOKEN="$(cat /run/secrets/CIVITAI_TOKEN)" && \
    curl -L --fail --retry 5 \
    -H "Authorization: Bearer ${CIVITAI_TOKEN}" \
    "https://civitai.com/api/download/models/2155386" \
    -o "/opt/ComfyUI/models/checkpoints/lustify_7.safetensors"

# Проверяем, что файлы действительно загрузились
RUN test -s "/opt/ComfyUI/models/checkpoints/lustify_7.safetensors" && \
    test -s "/opt/ComfyUI/models/loras/speed/dmd2_sdxl_4step_lora.safetensors" && \
    test -s "/opt/ComfyUI/models/upscale_models/4xNMKDSuperscale_4xNMKDSuperscale.pt" && \
    test -s "/opt/ComfyUI/models/upscale_models/1x-ITF-SkinDiffDetail-Lite-v1.pth" && \
    test -s "/opt/ComfyUI/models/upscale_models/1xSkinContrast-High-SuperUltraCompact.pth"
