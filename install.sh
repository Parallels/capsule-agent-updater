#!/bin/bash

set -euo pipefail

if [ -z "${USER:-}" ]; then
    USER=root
fi

OWNER="Parallels"
REPO="capsule-agent-updater"
USE_PRERELEASE=true
SERVICE_NAME="capsule-agent-updater"
TARGET_SERVICE_NAME="capsule-agent"
TARGET_SERVICE_REPO="capsule-agent"
TARGET_SERVICE_VERSION_URL="http://localhost:5000/api/version"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BINARY_PATH="/usr/local/bin/${SERVICE_NAME}"
ENV_FILE="/usr/local/bin/${SERVICE_NAME}.env"
HARDWARE_ID="unknown"
APPLICATION_ID="unknown"
USER_ID="unknown"
PD_LICENSE="unknown"
PD_LICENSE_TYPE="unknown"
PD_LICENSE_IS_TRIAL="unknown"
PD_LICENSE_IS_VOLUME="unknown"
PD_ID="unknown"
PD_ID="unknown"
ENVIRONMENT="stable"
API_URL=""
CHANNEL="stable"

function usage() {
    cat <<EOF >&2
Usage: $0 [install|update|uninstall] [options]

Commands:
  install            Install Capsule Agent Updater (default)
  update             Update Capsule Agent Updater binary in-place
  self-update        Update the binary only (used by auto-updater)
  uninstall          Remove Capsule Agent Updater service and binary

Options:
  --version <tag>    Use a specific release tag (e.g. v0.1.1)
  --pre-release      Allow prerelease versions (default: true)
  --target-service-version-url <url> URL to query for the target service version (default: http://localhost:5000/api/version)
  --target-service-name <name> Name of the target service to manage (default: capsule-agent)
  --target-service-repo <repo> GitHub repo of the target service (default: capsule-agent)
  --api-url <url>    URL of the Capsule Marketplace API (default: empty, uses GitHub)
  --channel <channel> Update channel (stable, beta, canary) (default: stable)
EOF
}

ACTION="install"
if [[ $# -gt 0 ]]; then
    case "$1" in
        install|update|self-update|uninstall|help|-h|--help)
            ACTION=$1
            shift
            if [[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
                usage
                exit 0
            fi
            ;;
    esac
fi

VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pre-release)
            USE_PRERELEASE=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --target-service-version-url)
            TARGET_SERVICE_VERSION_URL="$2"
            shift 2
            ;;
        --target-service-name)
            TARGET_SERVICE_NAME="$2"
            shift 2
            ;;
        --target-service-repo)
            TARGET_SERVICE_REPO="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --user-id)
            USER_ID="$2"
            shift 2
            ;;
        --hardware-id)
            HARDWARE_ID="$2"
            shift 2
            ;;
        --application-id)
            APPLICATION_ID="$2"
            shift 2
            ;;
        --pd-license)
            PD_LICENSE="$2"
            shift 2
            ;;
        --pd-license-type)
            PD_LICENSE_TYPE="$2"
            shift 2
            ;;
        --pd-license-is-trial)
            PD_LICENSE_IS_TRIAL="$2"
            shift 2
            ;;
        --pd-license-is-volume)
            PD_LICENSE_IS_VOLUME="$2"
            shift 2
            ;;
        --pd-id)
            PD_ID="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --api-url)
            API_URL="$2"
            shift 2
            ;;
        --channel)
            CHANNEL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

function ensure_requirements() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required" >&2
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ jq is required" >&2
        exit 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "❌ systemctl is required" >&2
        exit 1
    fi
}

function resolve_binary_name() {
    local arch
    arch=$(uname -m)
    local os
    os=$(uname -s)
    local binary_suffix=""

    case "$os" in
        Linux)
            binary_suffix="linux"
            ;;
        Darwin)
            binary_suffix="darwin"
            ;;
        *)
            echo "❌ Unsupported OS: $os" >&2
            exit 1
            ;;
    esac

    case "$arch" in
        x86_64)
            binary_suffix="${binary_suffix}-amd64"
            ;;
        aarch64|arm64)
            binary_suffix="${binary_suffix}-arm64"
            ;;
        *)
            echo "❌ Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac

    echo "${SERVICE_NAME}-${binary_suffix}"
}

function get_release_tag() {
    local tag
    if [[ -n "$VERSION" ]]; then
        echo "✅ Using version: $VERSION" >&2
        tag="$VERSION"
    else
        echo "✅ Using latest release" >&2
        echo "📦 Getting release information..." >&2

        if [[ "$USE_PRERELEASE" == true ]]; then
            echo "🔍 Including pre-releases in search..." >&2
            tag=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/releases" | jq -r 'map(select(.prerelease == true or .prerelease == false)) | sort_by(.created_at) | reverse | .[0].tag_name')
        else
            echo "🔍 Looking for stable releases only..." >&2
            tag=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/releases/latest" | jq -r '.tag_name')
        fi
    fi

    if [[ -z "$tag" || "$tag" == "null" ]]; then
        echo "❌ Failed to get release information" >&2
        exit 1
    fi

    echo "$tag"
}

function download_binary() {
    local release_tag=$1
    local binary_name=$2
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap '[ -n "${tmp_dir:-}" ] && rm -rf "$tmp_dir"' RETURN

    echo "📥 Downloading Capsule Agent Updater ${release_tag}..." >&2
    local download_url="https://github.com/$OWNER/$REPO/releases/download/${release_tag}/${binary_name}"
    local sig_url="${download_url}.sig"

    echo "Downloading from: $download_url" >&2
    
    local filename
    filename=$(basename "$download_url")
    local extracted_binary=""

    if [[ "$filename" == *.tar.gz || "$filename" == *.tgz ]]; then
        echo "📦 Detected tar.gz archive, extracting..." >&2
        curl -sSL -o "$tmp_dir/$filename" "$download_url"
        tar -xzf "$tmp_dir/$filename" -C "$tmp_dir"
    elif [[ "$filename" == *.zip ]]; then
        echo "📦 Detected zip archive, extracting..." >&2
        curl -sSL -o "$tmp_dir/$filename" "$download_url"
        unzip -q -o "$tmp_dir/$filename" -d "$tmp_dir"
    else
        # Direct binary download
        curl -sSL -o "$tmp_dir/$binary_name" "$download_url"
        extracted_binary="$tmp_dir/$binary_name"
    fi

    # If we extracted an archive, we need to find the binary
    if [[ -z "$extracted_binary" ]]; then
        # 1. Look for exact match of SERVICE_NAME (capsule-agent-updater)
        if [[ -f "$tmp_dir/$SERVICE_NAME" ]]; then
            extracted_binary="$tmp_dir/$SERVICE_NAME"
        # 2. Look for exact match of requested binary name (capsule-agent-updater-linux-amd64)
        elif [[ -f "$tmp_dir/$binary_name" ]]; then
            extracted_binary="$tmp_dir/$binary_name"
        else
            # 3. Look for file matching SERVICE_NAME* (e.g. capsule-agent-updater-linux-arm64)
            local regex_match
            regex_match=$(find "$tmp_dir" -maxdepth 1 -type f -name "${SERVICE_NAME}*" | head -n 1)

            if [[ -n "$regex_match" ]]; then
                extracted_binary="$regex_match"
            elif [[ -f "$tmp_dir/pd-auto-updater" ]]; then 
                 # 4. Fallback for legacy name
                 extracted_binary="$tmp_dir/pd-auto-updater"
            else
                # 5. Last resort: Find the first executable file that is not the archive itself
                extracted_binary=$(find "$tmp_dir" -maxdepth 1 -type f -perm +111 -not -name "*.tar.gz" -not -name "*.tgz" -not -name "*.zip" | head -n 1)
            fi
        fi
        
        if [[ -z "$extracted_binary" || ! -f "$extracted_binary" ]]; then
            echo "❌ Failed to find binary in archive" >&2
            ls -la "$tmp_dir" >&2
            exit 1
        fi

        echo "✅ Found binary: $extracted_binary" >&2
        # Move it to the expected binary name location so the rest of the script continues normally
        mv "$extracted_binary" "$tmp_dir/$binary_name"
    fi
    
    if [[ -n "$sig_url" && "$sig_url" != "null" ]]; then
         if [[ "$sig_url" == http* ]]; then
             curl -sSL -o "$tmp_dir/${binary_name}.sig" "$sig_url"
         fi
    fi

    # TODO: Add signature verification here if needed

    chmod +x "$tmp_dir/$binary_name"
    mv "$tmp_dir/$binary_name" "$BINARY_PATH"
}

function create_env_file() {
  # if the use_prerelease is true then setting the LXC_AGENT_UPDATER_USE_CANARY= to true otherwiuse false
  if [ "$USE_PRERELEASE" = true ] ; then
    USE_CANARY="LXC_AGENT_UPDATER_USE_CANARY=true"
  else
    USE_CANARY="LXC_AGENT_UPDATER_USE_CANARY=false"
  fi
    cat <<EOF > "$ENV_FILE"
LXC_AGENT_UPDATER_GITHUB_OWNER=$OWNER
LXC_AGENT_UPDATER_GITHUB_REPO=$TARGET_SERVICE_REPO
$USE_CANARY
LXC_AGENT_UPDATER_CHECK_INTERVAL=1h
LXC_AGENT_UPDATER_VERSION_URL=$TARGET_SERVICE_VERSION_URL
LXC_AGENT_UPDATER_LINUX_SERVICE_NAME=$TARGET_SERVICE_NAME
LXC_AGENT_APP_ENVIRONMENT=$ENVIRONMENT
LXC_AGENT_USER_ID=$USER_ID
LXC_AGENT_TELEMETRY_HARDWARE_ID=$HARDWARE_ID
LXC_AGENT_TELEMETRY_APPLICATION_ID=$APPLICATION_ID
LXC_AGENT_TELEMETRY_USER_ID=$USER_ID
LXC_AGENT_TELEMETRY_PD_LICENSE=$PD_LICENSE
LXC_AGENT_TELEMETRY_PD_LICENSE_TYPE=$PD_LICENSE_TYPE
LXC_AGENT_TELEMETRY_PD_LICENSE_IS_TRIAL=$PD_LICENSE_IS_TRIAL
LXC_AGENT_UPDATER_PD_LICENSE_IS_VOLUME=$PD_LICENSE_IS_VOLUME
LXC_AGENT_UPDATER_PD_ID=$PD_ID
LXC_AGENT_UPDATER_API_URL=$API_URL
LXC_AGENT_UPDATER_CHANNEL=$CHANNEL
EOF
}

function update_env_value() {
    local key="$1"
    local value="$2"
    if [[ -f "$ENV_FILE" ]] && [[ -n "$value" ]]; then
        if grep -q "^${key}=" "$ENV_FILE"; then
            local current_value
            current_value=$(grep "^${key}=" "$ENV_FILE" | cut -d= -f2-)
            if [[ "$current_value" != "$value" ]]; then
                sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
                echo "  ✓ Updated $key" >&2
                return 0  # Value was changed
            fi
        else
            echo "${key}=${value}" >> "$ENV_FILE"
            echo "  ✓ Added $key" >&2
            return 0  # Value was added
        fi
    fi
    return 1  # No change
}

function update_env_file_if_needed() {
    echo "📝 Checking for environment updates..." >&2
    local updated=false

    if [[ -n "$API_URL" ]]; then
        if update_env_value "LXC_AGENT_UPDATER_API_URL" "$API_URL"; then
            updated=true
        fi
    fi
    if [[ "$CHANNEL" != "stable" ]] && [[ -n "$CHANNEL" ]]; then
        if update_env_value "LXC_AGENT_UPDATER_CHANNEL" "$CHANNEL"; then
            updated=true
        fi
    fi
    if [[ "$ENVIRONMENT" != "stable" ]] && [[ -n "$ENVIRONMENT" ]]; then
        if update_env_value "LXC_AGENT_APP_ENVIRONMENT" "$ENVIRONMENT"; then
            updated=true
        fi
    fi
    if [[ "$USER_ID" != "unknown" ]] && [[ -n "$USER_ID" ]]; then
        if update_env_value "LXC_AGENT_USER_ID" "$USER_ID"; then
            updated=true
        fi
        if update_env_value "LXC_AGENT_TELEMETRY_USER_ID" "$USER_ID"; then
            updated=true
        fi
    fi
    if [[ "$HARDWARE_ID" != "unknown" ]] && [[ -n "$HARDWARE_ID" ]]; then
        if update_env_value "LXC_AGENT_TELEMETRY_HARDWARE_ID" "$HARDWARE_ID"; then
            updated=true
        fi
    fi
    if [[ "$APPLICATION_ID" != "unknown" ]] && [[ -n "$APPLICATION_ID" ]]; then
        if update_env_value "LXC_AGENT_TELEMETRY_APPLICATION_ID" "$APPLICATION_ID"; then
            updated=true
        fi
    fi
    if [[ "$PD_LICENSE" != "unknown" ]] && [[ -n "$PD_LICENSE" ]]; then
        if update_env_value "LXC_AGENT_TELEMETRY_PD_LICENSE" "$PD_LICENSE"; then
            updated=true
        fi
    fi
    if [[ "$PD_LICENSE_TYPE" != "unknown" ]] && [[ -n "$PD_LICENSE_TYPE" ]]; then
        if update_env_value "LXC_AGENT_TELEMETRY_PD_LICENSE_TYPE" "$PD_LICENSE_TYPE"; then
            updated=true
        fi
    fi
    if [[ "$PD_LICENSE_IS_TRIAL" != "unknown" ]] && [[ -n "$PD_LICENSE_IS_TRIAL" ]]; then
        if update_env_value "LXC_AGENT_TELEMETRY_PD_LICENSE_IS_TRIAL" "$PD_LICENSE_IS_TRIAL"; then
            updated=true
        fi
    fi
    if [[ "$PD_LICENSE_IS_VOLUME" != "unknown" ]] && [[ -n "$PD_LICENSE_IS_VOLUME" ]]; then
        if update_env_value "LXC_AGENT_UPDATER_PD_LICENSE_IS_VOLUME" "$PD_LICENSE_IS_VOLUME"; then
            updated=true
        fi
    fi
    if [[ "$PD_ID" != "unknown" ]] && [[ -n "$PD_ID" ]]; then
        if update_env_value "LXC_AGENT_UPDATER_PD_ID" "$PD_ID"; then
            updated=true
        fi
    fi

    if [[ "$updated" == "true" ]]; then
        echo "  ✓ Environment file updated, restarting service..." >&2
        return 0
    else
        echo "  No environment updates needed" >&2
        return 1
    fi
}

function create_service_file() {
    tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Capsule Agent Updater Service
After=network-online.target lxc-net.service
Wants=network-online.target
Requires=lxc-net.service

[Service]
Type=simple
ExecStart=${BINARY_PATH} -env ${ENV_FILE}
Restart=always
RestartSec=10
User=root

StandardOutput=append:/var/log/capsule-agent-updater.log
StandardError=append:/var/log/capsule-agent-updater.log

[Install]
WantedBy=multi-user.target
EOF
}

function stop_service_if_exists() {
    if [[ -f "$SERVICE_FILE" ]]; then
        echo "🛑 Stopping Capsule Agent Updater service..." >&2
        systemctl stop "$SERVICE_NAME" || true
    fi
}

function start_service() {
    echo "🚀 Starting Capsule Agent Updater service..." >&2
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME.service"
    systemctl start "$SERVICE_NAME.service"
}

function ensure_service_running() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ Capsule Agent Updater service is running" >&2
    else
        echo "❌ Capsule Agent Updater service failed to start" >&2
        systemctl status "$SERVICE_NAME.service" --no-pager || true
        exit 1
    fi
}

function install_capsule_agent() {
    ensure_requirements
    echo "🔧 Installing Capsule Agent Updater..." >&2
    local binary_name
    binary_name=$(resolve_binary_name)
    local release_tag
    release_tag=$(get_release_tag)
    echo "📌 Selected release: ${release_tag}"

    download_binary "$release_tag" "$binary_name"
    create_env_file
    create_service_file
    start_service
    ensure_service_running
}

function update_capsule_agent() {
    ensure_requirements
    echo "♻️  Updating Capsule Agent Updater..." >&2

    if [[ ! -x "$BINARY_PATH" ]]; then
        echo "❌ Capsule Agent Updater is not installed. Run install first." >&2
        exit 1
    fi

    local binary_name
    binary_name=$(resolve_binary_name)
    local release_tag
    release_tag=$(get_release_tag)
    echo "📌 Selected release: ${release_tag}" >&2

    stop_service_if_exists
    download_binary "$release_tag" "$binary_name"
    
    if update_env_file_if_needed; then
        echo "🔄 Restarting Capsule Agent Updater service due to config changes..." >&2
    else
        echo "🔄 Restarting Capsule Agent Updater service..." >&2
    fi
    
    systemctl restart "$SERVICE_NAME.service"
    ensure_service_running
}

function uninstall_capsule_agent() {
    ensure_requirements
    echo "🧹 Uninstalling Capsule Agent Updater..." >&2

    stop_service_if_exists
    systemctl disable "$SERVICE_NAME.service" >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload

    rm -f "$BINARY_PATH"
    rm -f "$ENV_FILE"

    echo "✅ Capsule Agent Updater removed" >&2
}

function self_update_capsule_agent() {
    ensure_requirements
    echo "♻️  Self-updating Capsule Agent Updater..." >&2

    if [[ ! -x "$BINARY_PATH" ]]; then
        echo "❌ Capsule Agent Updater is not installed. Run install first." >&2
        exit 1
    fi

    local binary_name
    binary_name=$(resolve_binary_name)
    local release_tag
    release_tag=$(get_release_tag)
    echo "📌 Selected release: ${release_tag}" >&2

    stop_service_if_exists
    download_binary "$release_tag" "$binary_name"

    echo "🔄 Restarting Capsule Agent Updater service..." >&2
    start_service
    ensure_service_running
}

case "$ACTION" in
    install)
        install_capsule_agent
        ;;
    update)
        update_capsule_agent
        ;;
    self-update)
        self_update_capsule_agent
        ;;
    uninstall)
        uninstall_capsule_agent
        ;;
    *)
        usage
        exit 1
        ;;
esac
