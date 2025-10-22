# Use official Python 3.9 slim image
FROM python:3.9-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install system build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      git \
      gcc \
      build-essential \
      libffi-dev \
      libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and install PEP-517 build tools (quote the <3 spec!)
RUN pip install --upgrade pip \
 && pip install build "setuptools>=61.0" "setuptools-git-versioning>=2.0,<3"

# Clone guidellm, checkout PR #211 (multiturn support), build wheel, and install
WORKDIR /tmp
RUN git clone --branch feat/adv_prefix https://github.com/vllm-project/guidellm.git \
 && cd guidellm \
 && echo "Building guidellm with multiturn support from feat/adv_prefix branch..." \
 && python -m build --wheel --no-isolation \
 && pip install dist/guidellm-*.whl \
 && pip install --upgrade "httpx==0.23.3" \
 && cd /tmp && rm -rf guidellm

# Install any additional runtime dependencies
RUN pip install pandas numpy scipy bottleneck

# Prepare cache and output directories for your Job
RUN mkdir /cache /output

# Switch to app directory
WORKDIR /app

# Default to bash (override in your Job YAML)
CMD ["bash"]
