FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      inotify-tools \
      libncurses5 \
      libstdc++6 \
      locales \
      openssl \
      unzip \
      wget \
      xz-utils \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    MISE_YES=1 \
    PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:${PATH}

USER ${USERNAME}

RUN curl https://mise.run | sh \
    && echo 'eval "$(mise activate bash)"' >> /home/${USERNAME}/.bashrc

WORKDIR /workspace/formentation
