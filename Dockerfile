# ComfyUI Dockerfile for Serverless GPU Deployment
# Base image with CUDA 12.8 and Python 3.12
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies including Python 3.12
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    # Python 3.12 and dev tools
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    # Build tools for packages that need compilation
    build-essential \
    pkg-config \
    libffi-dev \
    # Cairo for pycairo (required by svglib -> comfyui_controlnet_aux)
    libcairo2-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/python3.12 /usr/bin/python3

# Install uv (fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Set working directory
WORKDIR /app

# Clone the repository
RUN git clone https://github.com/my04team/ComfyUIDefurnish.git .

# Create virtual environment using system Python
RUN python -m venv uv

# Set virtual environment path
ENV VIRTUAL_ENV=/app/uv
ENV PATH="/app/uv/bin:$PATH"

# Upgrade pip in venv
RUN pip install --upgrade pip

# Install PyTorch with CUDA 12.8 support first
RUN uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# Install main ComfyUI requirements
RUN uv pip install -r requirements.txt

# Install custom node requirements (in order of dependency)
RUN uv pip install -r custom_nodes/comfyui_controlnet_aux/requirements.txt
RUN uv pip install -r custom_nodes/ComfyUI-GGUF/requirements.txt
RUN uv pip install -r custom_nodes/comfyui-kjnodes/requirements.txt
RUN uv pip install -r custom_nodes/comfyui-manager/requirements.txt
RUN uv pip install -r custom_nodes/comfyui_pulid_flux_ll/requirements.txt
RUN uv pip install -r custom_nodes/nunchaku_nodes/requirements.txt
RUN uv pip install -r custom_nodes/teacache/requirements.txt

# Install nunchaku (required by nunchaku_nodes, not listed in its requirements.txt)
RUN uv pip install "https://github.com/nunchaku-tech/nunchaku/releases/download/v0.3.1/nunchaku-0.3.1+torch2.8-cp312-cp312-linux_x86_64.whl"

# Install xformers for memory-efficient attention (optional but recommended)
RUN uv pip install xformers

# Download model weights from HuggingFace
WORKDIR /app/models

# CLIP models (text encoder)
RUN mkdir -p clip && \
    wget -q --show-progress -O clip/t5xxl_fp8_e4m3fn_scaled.safetensors \
        "https://huggingface.co/my04-team/comfyui-models/resolve/main/t5xxl_fp8_e4m3fn_scaled.safetensors" && \
    wget -q --show-progress -O clip/clip_l.safetensors \
        "https://huggingface.co/my04-team/comfyui-models/resolve/main/clip_l.safetensors"

# VAE model
RUN mkdir -p vae && \
    wget -q --show-progress -O vae/ae.safetensors \
        "https://huggingface.co/my04-team/comfyui-models/resolve/main/ae.safetensors"

# Nunchaku quantized FLUX model (store in diffusion_models for compatibility)
RUN mkdir -p diffusion_models && \
    wget -q --show-progress -O diffusion_models/svdq-int4_r32-flux.1-kontext-dev.safetensors \
        "https://huggingface.co/my04-team/comfyui-models/resolve/main/svdq-int4_r32-flux.1-kontext-dev.safetensors"

# Return to app directory
WORKDIR /app

# Create output and input directories
RUN mkdir -p output input

# Expose ComfyUI port
EXPOSE 8188

# Set environment variables for ComfyUI
ENV COMFYUI_PATH=/app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8188/system_stats || exit 1

# Default command to run ComfyUI
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
