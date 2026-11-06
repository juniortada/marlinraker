FROM debian:stable-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends nsis imagemagick librsvg2-bin dpkg-dev lintian file \
    && rm -rf /var/lib/apt/lists/*
