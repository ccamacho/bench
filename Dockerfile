# Use official Python 3.9 slim image
FROM python:3.9-slim

# Set environment variables
#ENV PYTHONDONTWRITEBYTECODE=1 \
#    PYTHONUNBUFFERED=1 \
#    PIP_NO_CACHE_DIR=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    git \
    build-essential \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip

# Install guidellm from GitHub, then pin httpx to a compatible version
RUN pip install --no-cache-dir \
      git+https://github.com/vllm-project/guidellm.git \
      pandas numpy scipy bottleneck \
 && pip install --no-cache-dir httpx==0.23.3

# Set working directory
WORKDIR /app
