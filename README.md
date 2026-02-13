# Flutter Docker Environment for Android Studio

This Docker environment provides a complete Flutter development setup with:
- **Flutter 3.16.5**
- **Java 17** (OpenJDK)
- **Dart 2.x** (included with Flutter)
- **Android SDK** with command-line tools

## Prerequisites

- Docker installed on your system

## Quick Start

### 1. Build image and export SDKs from Docker

First, build the Docker image and export Java SDK, Android SDK, and Flutter SDK from the container into a local `sdk` folder:

```bash
make setup-sdk
```

This will:
- **Java JDK 17** to `sdk/java/jdk-17`
- **Android SDK** to `sdk/android`
- **Flutter SDK 3.16.5** to `sdk/flutter`
- **Dart SDK** to `sdk/dart`

### 2. Start the Docker Container

```bash
# Complete setup: export SDKs, start, and verify
make setup
```

Or step by step:

```bash
# Build the Docker image
make build

# Run the container
make start
```

### 3. Access the Container

```bash
make access
```

Or directly:

```bash
docker compose exec android bash
```

## Using Makefile (Recommended)

The project includes a Makefile with convenient commands for common tasks:

### Quick Setup

```bash
# Complete setup: install SDKs, build, start, and verify
make setup
```

This command will:
1. Build the Docker image (if needed)
2. Export Java, Android, and Flutter SDKs from the image to the local `./sdk/` folder
3. Start the container
4. Run Flutter doctor to verify installation

### Common Commands

```bash
# Build the Docker image
make build

# Copy Java JDK 17 to ./packages folder
make copy-java

# Access the container shell
make access
# or
make shell

# Run Flutter doctor
make doctor

# Run Flutter commands
make pub-get              # flutter pub get
make clean                # flutter clean
make run                  # flutter run
make test                 # flutter test
make build-apk            # flutter build apk
make build-appbundle      # flutter build appbundle

# Run any Flutter command
make flutter FLUTTER_ARGS="create my_app"
make flutter FLUTTER_ARGS="build apk --release"

# Container management
make start                # Start container
make stop                 # Stop container
make restart              # Restart container
make logs                 # View container logs

# Version information
make version              # Flutter version
make info                 # All version info

# Cleanup
make clean-all            # Clean everything including volumes
```

### See All Available Commands

```bash
make help
```

## Usage with Android Studio

The SDKs installed in the `sdk/` folder can be used directly in Android Studio:

### Configure Android Studio to Use Local SDKs

1. **Java JDK**:
   - Go to **Settings → Build, Execution, Deployment → Build Tools → Gradle**
   - Set **Gradle JDK** to: `./sdk/java/jdk-17` (or full path: `/home/tnchben/workspace/flutter-docker/sdk/java/jdk-17`)

2. **Android SDK**:
   - Go to **Settings → Appearance & Behavior → System Settings → Android SDK**
   - Set **Android SDK Location** to: `./sdk/android` (or full path: `/home/tnchben/workspace/flutter-docker/sdk/android`)

3. **Flutter SDK**:
   - Go to **Settings → Languages & Frameworks → Flutter**
   - Set **Flutter SDK path** to: `./sdk/flutter` (or full path: `/home/tnchben/workspace/flutter-docker/sdk/flutter`)

4. **Dart SDK**:
   - Go to **Settings → Languages & Frameworks → Dart**
   - Set **Dart SDK path** to: `./sdk/dart` (or full path: `/home/tnchben/workspace/flutter-docker/sdk/dart`)

### Benefits

- **Shared SDKs**: The same SDKs are used by both Docker container and Android Studio
- **No duplication**: SDKs are stored once in the project's `sdk/` folder
- **Version consistency**: Docker and Android Studio use identical SDK versions
- **Easy updates**: Update SDKs once, and both environments benefit

### Using Docker for Development

You can use the container for command-line operations while Android Studio uses the same SDKs:

```bash
# Access the container
make access

# Create a new Flutter project inside the container
flutter create my_app

# Run Flutter commands
flutter pub get
flutter run
```

## Verify Installation

Once inside the container, verify the installation:

```bash
# Check Flutter version
flutter --version

# Check Java version
java -version

# Check Dart version (included with Flutter)
dart --version

# Run Flutter doctor
flutter doctor
```

## Project Structure

```
flutter-docker/
├── .env.example           # Environment variables example
├── Dockerfile             # Main Docker image definition
├── docker-compose.yml     # Docker Compose configuration
├── Makefile               # Convenient commands for common tasks
├── .dockerignore          # Files to exclude from Docker build
├── .gitignore             # Git ignore rules (excludes sdk/ folder)
├── bin/                   # Local executables
├── packages/              # Local packages
│   ├── java-17/           # Java JDK 17
├── sdk/                   # Local SDKs folder (created by make setup-sdk)
│   ├── java/              # Java JDK 17
│   ├── android/           # Android SDK
│   ├── flutter/           # Flutter SDK
│   └── dart/              # Dart SDK
└── README.md              # This file
```

**Note**: The `sdk/` folder is excluded from git (see `.gitignore`) as it contains large binary files.

## Environment Variables

The container sets up the following environment variables (SDKs are installed inside the image):
- `JAVA_HOME`: `/usr/lib/jvm/java-17-openjdk-amd64`
- `ANDROID_HOME`: `/opt/android-sdk`
- `ANDROID_SDK_ROOT`: `/opt/android-sdk`
- `FLUTTER_HOME`: `/opt/flutter`
- `DART_HOME`: `/opt/flutter/bin/cache/dart-sdk`
- `PATH`: Includes all necessary tool paths

The Docker container installs the SDKs internally at build time. The `make setup-sdk` target then copies those SDKs from the container into the local `sdk/` folder so Android Studio can use them.

### Host Environment Variables

```bash
export JAVA_HOME="$PWD/sdk/java/jdk-17..."
export ANDROID_SDK_ROOT="$PWD/sdk/android"
export FLUTTER_HOME="$PWD/sdk/flutter"
export DART_HOME="$PWD/sdk/dart"
export PATH="$FLUTTER_HOME/bin:$DART_HOME/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
```

Add these to your `~/.zshrc` or `~/.bashrc` to use the SDKs from the command line outside of Docker.

## Troubleshooting

### Flutter doctor shows issues
Run `flutter doctor` inside the container to see what needs to be configured. Most Android-related issues should be resolved, but you may need to accept additional licenses.


### Android licenses
If you need to accept Android licenses manually:
```bash
make android-licenses
# or
docker compose exec flutter-android sdkmanager --licenses
```

## Notes

- The SDKs are installed **inside the Docker image**, and `make setup-sdk` exports them into the local `sdk/` folder for Android Studio
- This setup ensures version consistency between Docker and Android Studio, since both use SDKs derived from the same image
- For GUI applications, you'll need X11 forwarding configured (commented out in docker-compose.yml)
- The `sdk/` folder is git-ignored, so each developer runs `make setup-sdk` to export SDKs locally

## Building for Production

To build a production-ready image:

```bash
docker build -t flutter-android:3.16.5 .
```

