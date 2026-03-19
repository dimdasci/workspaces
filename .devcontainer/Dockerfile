FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG KASMVNC_VERSION=1.3.3

# Chromium/Playwright deps + Docker CLI + media tools + terminal tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Chromium/Playwright dependencies
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0 \
    # Docker CLI (socket passthrough to host daemon)
    docker.io \
    # Media processing
    ffmpeg \
    imagemagick \
    libimage-exiftool-perl \
    webp \
    poppler-utils \
    ghostscript \
    qpdf \
    jq \
    unzip \
    age \
    # Browser (for gh auth, OAuth flows in KasmVNC desktop)
    chromium \
    # KasmVNC Perl dependency
    libdatetime-perl \
    # Terminal tools
    tmux \
    mosh \
    && rm -rf /var/lib/apt/lists/*

# Add vscode user to docker group
RUN usermod -aG docker vscode

# XFCE desktop environment
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

# KasmVNC — pinned to KASMVNC_VERSION, supports amd64 and arm64
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL -o /tmp/kasmvnc.deb \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_bookworm_${KASMVNC_VERSION}_${ARCH}.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/kasmvnc.deb \
    && rm /tmp/kasmvnc.deb \
    && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Silence login banner
RUN touch /home/vscode/.hushlogin
