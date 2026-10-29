#!/usr/bin/env bash

# Copyright 2025-2026 Nils Knieling. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Install Docker and GitHub Actions Runner for Linux with x64 or ARM64 CPU architecture
# https://github.com/actions/runner
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#linux
# https://docs.docker.com/engine/install/ubuntu/

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Set default GitHub Actions Runner installation directory
readonly MY_RUNNER_DIR="/actions-runner"

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

# Function to exit the script with a failure message
exit_with_failure() {
	echo >&2 "FAILURE: $1"
	exit 1
}

# Detect CPU architecture early
case $(uname -m) in
	aarch64|arm64)
		readonly MY_ARCH="arm64"
		;;
	amd64|x86_64)
		readonly MY_ARCH="x64"
		;;
	*)
		exit_with_failure "Cannot determine CPU architecture!"
		;;
esac

# Install dependencies
echo "Installing system dependencies..."
sudo apt-get update -yq
sudo apt-get install -y \
	apt-transport-https \
	apt-utils \
	build-essential \
	ca-certificates \
	curl \
	dnsutils \
	git \
	gpg \
	jq \
	lsb-release \
	nodejs \
	npm \
	openssh-client \
	python3-crcmod \
	python3-openssl \
	python3-pip \
	python3-venv \
	software-properties-common \
	tar \
	unzip \
	zip

# Verify required commands are available
readonly REQUIRED_COMMANDS=(curl gzip jq sed tar)
for cmd in "${REQUIRED_COMMANDS[@]}"; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		exit_with_failure "Required command '$cmd' not found"
	fi
done

# Add Docker repository and install
echo "Installing Docker..."
sudo curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | sudo gpg --dearmor -o "/usr/share/keyrings/download.docker.com"
echo "deb [signed-by=/usr/share/keyrings/download.docker.com] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee "/etc/apt/sources.list.d/docker.list" >/dev/null
sudo apt-get update -yq
sudo apt-get install -y \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin

# Enable and start Docker service
sudo systemctl enable docker.service
sudo systemctl start docker.service

# Create runner user and add to docker und sudoers group
echo "Creating runner user..."
if ! id -u runner >/dev/null 2>&1; then
	sudo useradd -m runner
fi
sudo usermod -aG docker,google-sudoers runner

# Install GitHub Actions Runner
echo "Installing GitHub Actions Runner..."
MY_RUNNER_VERSION=$(curl -fsSL "https://api.github.com/repos/actions/runner/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
if [[ -z "$MY_RUNNER_VERSION" || "$MY_RUNNER_VERSION" == "null" ]]; then
	exit_with_failure "Could not retrieve the latest GitHub Actions Runner version"
fi
echo "Installing GitHub Actions Runner version: v${MY_RUNNER_VERSION}"

# Download and extract runner
sudo mkdir -p "$MY_RUNNER_DIR"
cd "$MY_RUNNER_DIR"
sudo curl -fsSL -O "https://github.com/actions/runner/releases/download/v${MY_RUNNER_VERSION}/actions-runner-linux-${MY_ARCH}-${MY_RUNNER_VERSION}.tar.gz"
sudo tar xzf "actions-runner-linux-${MY_ARCH}-${MY_RUNNER_VERSION}.tar.gz"

# Run the installation script
sudo ./bin/installdependencies.sh
echo "GitHub Actions Runner installed successfully"

# Android SDK. GitHub-hosted `ubuntu-24*` images ship this preinstalled; this
# image did not, so AGP failed at configuration time with "SDK location not
# found" before any task ran.
echo "Installing the Android SDK..."

# sdkmanager is a Java program with no bundled runtime. Kept after the build
# because the Maestro lane installs its system image at job time.
sudo apt-get install -y --no-install-recommends openjdk-17-jdk-headless

# Same path the GitHub-hosted images use, so their hardcoded fallbacks and
# third-party actions that assume it still resolve.
readonly MY_ANDROID_SDK_DIR="/usr/local/lib/android/sdk"
sudo mkdir -p "$MY_ANDROID_SDK_DIR"

# Owned by `runner`, and packages installed *as* `runner` rather than installed
# as root and chowned, so the runtime `sdkmanager --install` can write here.
sudo chown -R runner:runner "$MY_ANDROID_SDK_DIR"

# Resolved from the SDK repository rather than pinned. `commandlinetools-linux-
# <build>_latest.zip` is a permanent URL, so a stale pin never 404s - it just
# keeps handing back an old sdkmanager that refuses newer platforms.
readonly MY_ANDROID_REPO="https://dl.google.com/android/repository/repository2-3.xml"
readonly MY_CMDLINE_TOOLS_FALLBACK="commandlinetools-linux-16111833_latest.zip"
MY_CMDLINE_TOOLS=$(curl -fsSL "$MY_ANDROID_REPO" \
	| grep -o 'commandlinetools-linux-[0-9]*_latest\.zip' | sort -Vu | tail -n1)
MY_CMDLINE_TOOLS="${MY_CMDLINE_TOOLS:-$MY_CMDLINE_TOOLS_FALLBACK}"
echo "Using Android command line tools: $MY_CMDLINE_TOOLS"

MY_TMP_DIR=$(mktemp -d)
# mktemp is 0700 as root here; everything below unpacks as `runner`.
sudo chown runner:runner "$MY_TMP_DIR"
curl -fsSL -o "$MY_TMP_DIR/cmdline-tools.zip" "https://dl.google.com/android/repository/$MY_CMDLINE_TOOLS"
# The archive unpacks to `cmdline-tools/`; sdkmanager only accepts the versioned
# `cmdline-tools/latest/` layout, so the rename is required, not cosmetic.
sudo -u runner -H unzip -q "$MY_TMP_DIR/cmdline-tools.zip" -d "$MY_TMP_DIR/extract"
sudo -u runner mkdir -p "$MY_ANDROID_SDK_DIR/cmdline-tools"
sudo -u runner mv "$MY_TMP_DIR/extract/cmdline-tools" "$MY_ANDROID_SDK_DIR/cmdline-tools/latest"
rm -rf "$MY_TMP_DIR"

readonly MY_SDKMANAGER="$MY_ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager"

# `platforms;android-37.0`, not `android-37`: since the minor-SDK scheme an API
# level is addressed `<major>.<minor>`, and bare `compileSdk = 37` resolves to
# exactly `.0`. There is no `platforms;android-37` package, and a host carrying
# only `android-37.1` still fails with "Failed to find target with hash string
# 'android-37'". build-tools 36.0.0 is AGP 9.4's default, which it downloads at
# build time when absent; both are installed so no build needs to fetch.
readonly MY_ANDROID_PACKAGES=(
	"platform-tools"
	"platforms;android-37.0"
	"build-tools;36.0.0"
	"build-tools;37.0.0"
)

# `yes |` and pipefail do not mix - when sdkmanager exits, `yes` takes SIGPIPE
# and pipefail turns a successful accept into 141. The block below is what
# actually proves the install worked.
set +o pipefail
yes | sudo -u runner -H "$MY_SDKMANAGER" --sdk_root="$MY_ANDROID_SDK_DIR" --licenses >/dev/null || true
set -o pipefail

sudo -u runner -H "$MY_SDKMANAGER" --sdk_root="$MY_ANDROID_SDK_DIR" "${MY_ANDROID_PACKAGES[@]}"

# Fail the image build rather than the first job that needs the piece.
for required in \
	"cmdline-tools/latest/bin/sdkmanager" \
	"platforms/android-37.0/android.jar" \
	"build-tools/36.0.0/aapt2" \
	"build-tools/37.0.0/aapt2" \
	"platform-tools/adb"; do
	test -e "$MY_ANDROID_SDK_DIR/$required" \
		|| exit_with_failure "Android SDK is missing $required"
done
echo "Android SDK installed at $MY_ANDROID_SDK_DIR"

# Libraries the downloaded emulator binary links against; a missing one kills
# it at startup without saying so. Installed per package because apt is atomic -
# one renamed package should not take down the Lint and unit-test lanes too.
# Note `libasound2t64`: bare `libasound2` does not exist on noble.
for lib in libasound2t64 libnss3 libpulse0 libxcomposite1 libxdamage1 libxtst6 xdotool; do
	sudo apt-get install -y --no-install-recommends "$lib" \
		|| echo "WARNING: could not install emulator runtime library '$lib'" >&2
done

# Publish ANDROID_HOME to every job step.
#
# `config.sh` sources `env.sh`, which seeds the runner root's `.env` from the
# ambient environment but skips any key it already finds, so a baked `.env`
# wins. It is `.env` rather than profile.d because the agent runs from a
# non-login shell that never sources profile.d.
#
# Owned by `runner`: `env.sh` appends to this file as `runner`, so a root-owned
# `.env` fails the day a key needs appending - silently, until then.
sudo tee /actions-runner/.env >/dev/null <<EOF
ANDROID_HOME=$MY_ANDROID_SDK_DIR
ANDROID_SDK_ROOT=$MY_ANDROID_SDK_DIR
EOF
sudo chown runner:runner /actions-runner/.env

# `env.sh` also does `echo $PATH > .path`, overwriting it from the registering
# shell, so nothing written to `.path` survives. Reachable by bare name goes
# here instead.
sudo ln -sf "$MY_ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager
sudo ln -sf "$MY_ANDROID_SDK_DIR/platform-tools/adb" /usr/local/bin/adb

# For `gcloud compute ssh` debugging sessions only; no job reads this.
sudo tee /etc/profile.d/android-sdk.sh >/dev/null <<EOF
export ANDROID_HOME=$MY_ANDROID_SDK_DIR
export ANDROID_SDK_ROOT=$MY_ANDROID_SDK_DIR
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"
EOF

# Cleanup: Clear package cache and temporary files
echo "Cleaning up..."
sudo apt-get clean
sudo rm -rf /tmp/* /root/.cache

# Cleanup: Rotate and vacuum journal logs
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s

# Cleanup: Remove compressed and rotated log files, then truncate remaining logs
sudo find /var/log -type f \( -name "*.gz" -o -regex ".*\.[0-9]$" \) -delete
sudo find /var/log -type f -exec truncate -s 0 {} +

echo "Setup completed successfully"

# Shutdown VM
sudo shutdown -h now
