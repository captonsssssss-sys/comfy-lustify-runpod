# syntax=docker/dockerfile:1.7

FROM farmerfarmit/bitcoin:v6

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV COMFYUI_PATH=/default-comfyui-bundle/ComfyUI

# Проверяем curl.
# Если его нет — устанавливаем через доступный пакетный менеджер.
RUN set -eux; \
    if command -v curl >/dev/null 2>&1; then \
        echo "curl already installed"; \
    elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update; \
        apt-get install -y --no-install-recommends curl ca-certificates; \
        rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache curl ca-certificates; \
    elif command -v dnf >/dev/null 2>&1; then \
        dnf install -y curl ca-certificates; \
        dnf clean all; \
    elif command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y curl ca-certificates; \
        microdnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
        yum install -y curl ca-certificates; \
        yum clean all; \
    else \
        echo "ERROR: curl отсутствует и пакетный менеджер не найден"; \
        exit 1; \
    fi; \
    curl --version

# Проверяем, что ComfyUI действительно находится в ожидаемой папке.
RUN set -eux; \
    test -d "${COMFYUI_PATH}"; \
    test -d "${COMFYUI_PATH}/models"; \
    echo "ComfyUI found at: ${COMFYUI_PATH}"

# Полностью очищаем старые workflow и пользовательские модели,
# которые могли находиться внутри базового образа.
RUN set -eux; \
    mkdir -p \
        "${COMFYUI_PATH}/user/default/workflows" \
        "${COMFYUI_PATH}/models/checkpoints" \
        "${COMFYUI_PATH}/models/loras/speed" \
        "${COMFYUI_PATH}/models/upscale_models"; \
    find "${COMFYUI_PATH}/user/default/workflows" \
        -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
    find "${COMFYUI_PATH}/models/checkpoints" \
        -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
    find "${COMFYUI_PATH}/models/loras" \
        -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
    find "${COMFYUI_PATH}/models/upscale_models" \
        -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
    mkdir -p "${COMFYUI_PATH}/models/loras/speed"

# Основной апскейлер.
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    "https://huggingface.co/shubhdotai/upscaler/resolve/main/4xNMKDSuperscale_4xNMKDSuperscale.pt" \
    -o "${COMFYUI_PATH}/models/upscale_models/4xNMKDSuperscale_4xNMKDSuperscale.pt"

# Апскейлер детализации кожи.
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/1x-ITF-SkinDiffDetail-Lite-v1.pth" \
    -o "${COMFYUI_PATH}/models/upscale_models/1x-ITF-SkinDiffDetail-Lite-v1.pth"

# Апскейлер контраста кожи.
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    "https://huggingface.co/notkenski/upscalers/resolve/main/1xSkinContrast-High-SuperUltraCompact.pth" \
    -o "${COMFYUI_PATH}/models/upscale_models/1xSkinContrast-High-SuperUltraCompact.pth"

# DMD2 SDXL 4-step LoRA.
RUN curl -L \
    --fail \
    --retry 5 \
    --retry-delay 5 \
    "https://huggingface.co/tianweiy/DMD2/resolve/main/dmd2_sdxl_4step_lora.safetensors" \
    -o "${COMFYUI_PATH}/models/loras/speed/dmd2_sdxl_4step_lora.safetensors"

# Lustify GGWP V7.
# Токен берётся из GitHub Secret и не сохраняется в Docker-образе.
RUN --mount=type=secret,id=CIVITAI_TOKEN,required=true \
    set -eux; \
    CIVITAI_TOKEN="$(cat /run/secrets/CIVITAI_TOKEN)"; \
    curl -L \
        --fail \
        --retry 5 \
        --retry-delay 5 \
        -H "Authorization: Bearer ${CIVITAI_TOKEN}" \
        "https://civitai.com/api/download/models/2155386" \
        -o "${COMFYUI_PATH}/models/checkpoints/lustify_7.safetensors"

# Добавляем только один workflow.
COPY LUSTIFY.json /tmp/LUSTIFY.json

RUN set -eux; \
    install -m 0644 \
        /tmp/LUSTIFY.json \
        "${COMFYUI_PATH}/user/default/workflows/LUSTIFY.json"; \
    rm -f /tmp/LUSTIFY.json

# Проверяем наличие всех файлов.
RUN set -eux; \
    test -s "${COMFYUI_PATH}/models/checkpoints/lustify_7.safetensors"; \
    test -s "${COMFYUI_PATH}/models/loras/speed/dmd2_sdxl_4step_lora.safetensors"; \
    test -s "${COMFYUI_PATH}/models/upscale_models/4xNMKDSuperscale_4xNMKDSuperscale.pt"; \
    test -s "${COMFYUI_PATH}/models/upscale_models/1x-ITF-SkinDiffDetail-Lite-v1.pth"; \
    test -s "${COMFYUI_PATH}/models/upscale_models/1xSkinContrast-High-SuperUltraCompact.pth"; \
    test -s "${COMFYUI_PATH}/user/default/workflows/LUSTIFY.json"

# Проверяем, что основной checkpoint скачался полностью.
RUN set -eux; \
    CHECKPOINT_SIZE="$(stat -c%s "${COMFYUI_PATH}/models/checkpoints/lustify_7.safetensors")"; \
    echo "Lustify checkpoint size: ${CHECKPOINT_SIZE} bytes"; \
    test "${CHECKPOINT_SIZE}" -gt 5000000000

# Проверяем, что в папке workflow остался только LUSTIFY.json.
RUN set -eux; \
    WORKFLOW_COUNT="$(find "${COMFYUI_PATH}/user/default/workflows" \
        -maxdepth 1 -type f | wc -l)"; \
    echo "Workflow count: ${WORKFLOW_COUNT}"; \
    test "${WORKFLOW_COUNT}" -eq 1; \
    test -f "${COMFYUI_PATH}/user/default/workflows/LUSTIFY.json"
