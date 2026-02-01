FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies (PHP, Git, Composer, NPM, Sudo)
RUN apt-get update && apt-get install -y \
    software-properties-common \
    curl \
    git \
    unzip \
    sudo \
    nodejs \
    npm \
    php-cli \
    php-xml \
    php-mbstring \
    php-curl \
    php-zip \
    php-sqlite3

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create 'forge' user simulating Forge setup
RUN useradd -ms /bin/bash forge && \
    usermod -aG sudo forge && \
    echo "forge ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up directory structure
WORKDIR /home/forge/default
RUN chown -R forge:forge /home/forge

# Switch to forge user
USER forge

# Add a dummy Laravel Artisan
RUN echo '#!/usr/bin/env php\n<?php echo "Artisan Mock Executed: " . implode(" ", array_slice($argv, 1)) . PHP_EOL;' > artisan && \
    chmod +x artisan && \
    git config --global --add safe.directory "*"

# Create a bare remote repository to simulate 'origin'
RUN mkdir -p /home/forge/repo.git && \
    cd /home/forge/repo.git && \
    git init --bare

# Init site repo
RUN git init && \
    git config --global user.email "forge@example.com" && \
    git config --global user.name "Forge" && \
    echo "APP_NAME=Laravel" > .env.example && \
    echo '{"name": "test/project", "require": {}}' > composer.json && \
    git add . && \
    git commit -m "Initial commit" && \
    git remote add origin /home/forge/repo.git && \
    git push -u origin master:main

# Set Env Vars needed for Automator
ENV FORGE_SITE_PATH=/home/forge/default
ENV FORGE_PHP=php
ENV FORGE_COMPOSER=composer
ENV FORGE_SITE_BRANCH=main

CMD ["bash"]
