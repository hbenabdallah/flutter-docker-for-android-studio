FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive


# Build arguments for user configuration
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER=user

# Install basic dependencies including sudo for user management
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    wget \
    ca-certificates \
    sudo \
    adb \
    && rm -rf /var/lib/apt/lists/*

# Create entrypoint script to clean sdk folder on container start
# This script will use sudo to run as root, bypassing permission issues
# It only deletes contents inside /sdk, not the /sdk folder itself
RUN echo '#!/bin/bash\n\
set -e\n\
# Clean sdk folder contents at container start (runs with sudo to bypass permission issues)\n\
if [ -d "/sdk" ]; then\n\
    echo "Cleaning sdk folder contents..."\n\
    # Use find to delete all contents (files and directories) inside /sdk\n\
    sudo find /sdk -mindepth 1 -delete 2>/dev/null || true\n\
    echo "sdk folder cleaned"\n\
fi\n\
# Execute the original command\n\
exec "$@"' > /usr/local/bin/cleanup-sdk-entrypoint.sh && \
    chmod +x /usr/local/bin/cleanup-sdk-entrypoint.sh

# Install Java 17 inside the container
RUN apt-get update && apt-get install -y \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Set Java environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin

# Install Android SDK command-line tools and core components inside the container
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    cd /tmp && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /dev/null -O cmdline-tools.zip && \
    unzip -q cmdline-tools.zip && \
    rm cmdline-tools.zip && \
    mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    mv cmdline-tools/* ${ANDROID_SDK_ROOT}/cmdline-tools/latest/ && \
    yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses && \
    yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} \
        "platform-tools" \
        "platforms;android-34" \
        "build-tools;34.0.0" \
        "cmdline-tools;latest"
ENV PATH=$PATH:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools

# Create user and group with specified IDs (handle case where group/user might exist)
RUN (groupadd -g ${GROUP_ID} ${USER} 2>/dev/null || true) && \
    (useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash ${USER} 2>/dev/null || \
     usermod -u ${USER_ID} -g ${GROUP_ID} -d /home/${USER} -m -s /bin/bash ${USER} 2>/dev/null || true) && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set HOME_PATH based on user
ENV HOME_PATH=/home/${USER}

# Install Flutter 3.16.5 inside the container
ENV FLUTTER_VERSION=3.16.5
ENV FLUTTER_HOME=/opt/flutter
ENV DART_HOME=$FLUTTER_HOME/bin/cache/dart-sdk
ENV PUB_CACHE=${HOME_PATH}/.pub-cache
ENV PATH=$PATH:$FLUTTER_HOME/bin:$DART_HOME/bin:${HOME_PATH}/.pub-cache/bin

# Install Flutter as root first, then change ownership
# Remove existing Flutter installation if it exists (from previous builds)
RUN rm -rf ${FLUTTER_HOME} 2>/dev/null || true && \
    git clone --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME} && \
    chown -R ${USER}:${USER} ${FLUTTER_HOME}

# Switch to user for Flutter doctor and FVM installation
USER ${USER}
WORKDIR ${HOME_PATH}

# Run flutter doctor and install FVM as the user
RUN flutter doctor && \
    dart pub global activate fvm

# Switch back to root to ensure cache directories exist and have correct ownership
USER root

# Ensure cache directories exist as directories (not files) for volume mounting
# Remove if they exist as files, then create as directories with correct ownership
RUN rm -rf ${HOME_PATH}/.flutter ${HOME_PATH}/.android ${HOME_PATH}/.gradle ${HOME_PATH}/.pub-cache /workspace 2>/dev/null || true && \
    mkdir -p ${HOME_PATH}/.flutter ${HOME_PATH}/.android ${HOME_PATH}/.gradle ${HOME_PATH}/.pub-cache /workspace && \
    chown -R ${USER}:${USER} ${HOME_PATH}/.flutter ${HOME_PATH}/.android ${HOME_PATH}/.gradle ${HOME_PATH}/.pub-cache /workspace && \
    chmod -R 755 ${HOME_PATH}/.flutter ${HOME_PATH}/.android ${HOME_PATH}/.gradle ${HOME_PATH}/.pub-cache /workspace

# Switch back to user for runtime
USER ${USER}

# Set working directory
WORKDIR /workspace

# Expose common ports for Flutter development
EXPOSE 8080 3000 5000

# Set entrypoint to clean sdk folder before running commands
ENTRYPOINT ["/usr/local/bin/cleanup-sdk-entrypoint.sh"]

# Default command
CMD ["/bin/bash"]

