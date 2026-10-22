#!/usr/bin/env bash
set -euo pipefail

# Usage: ./build.sh [FRIGATE_VERSION] [TF_VERSION] [TF_BUILD_JOBS] [TF_LOCAL_RAM_MB]
# Examples:
#   ./build.sh
#   ./build.sh 0.18.2
#   ./build.sh 0.18.2 2.19.1
#   ./build.sh 0.18.2 2.19.1 4 8192

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

FRIGATE_VERSION="${1:-${FRIGATE_VERSION:-0.18.2}}"
TF_VERSION="${2:-${TF_VERSION:-2.19.1}}"
TF_BUILD_JOBS="${3:-${TF_BUILD_JOBS:-2}}"
TF_LOCAL_RAM_MB="${4:-${TF_LOCAL_RAM_MB:-4096}}"
IMAGE_NAME="${IMAGE_NAME:-frigate-j5005}"
IMAGE_TAG="${IMAGE_TAG:-${IMAGE_NAME}:${FRIGATE_VERSION}-noavx-tf${TF_VERSION}}"
SCREEN_SESSION="${SCREEN_SESSION:-frigate-build-${FRIGATE_VERSION}-tf${TF_VERSION}}"

if ! command -v screen >/dev/null 2>&1; then
    echo "ERROR: GNU Screen is not installed. Install it with: sudo apt install screen" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker command was not found." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    cat >&2 <<'MSG'
ERROR: Docker is unavailable with the current permissions.
Run this script with sudo if you normally use sudo for Docker, e.g.:
  sudo ./build.sh 0.18.2 2.19.1
When started with sudo, use 'sudo screen -r ...' to reattach from your normal account.
MSG
    exit 1
fi

if [[ ! "$TF_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: TF_BUILD_JOBS must be a positive integer (got '$TF_BUILD_JOBS')." >&2
    exit 1
fi
if [[ ! "$TF_LOCAL_RAM_MB" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: TF_LOCAL_RAM_MB must be a positive integer (got '$TF_LOCAL_RAM_MB')." >&2
    exit 1
fi

if screen -ls 2>/dev/null | grep -Fq ".${SCREEN_SESSION}"; then
    echo "ERROR: Screen session '${SCREEN_SESSION}' already exists." >&2
    if (( EUID == 0 )); then
        echo "Reattach with: screen -r '${SCREEN_SESSION}'" >&2
    else
        echo "Reattach with: screen -r '${SCREEN_SESSION}'" >&2
    fi
    exit 1
fi

LOG_DIR="${SCRIPT_DIR}/build-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/frigate-${FRIGATE_VERSION}-tf-${TF_VERSION}-$(date +%Y%m%d-%H%M%S).log"
export BUILD_LOG="$LOG_FILE"

BUILD_CMD=(
    docker build
    --progress=plain
    --pull
    --build-arg "FRIGATE_VERSION=${FRIGATE_VERSION}"
    --build-arg "TF_VERSION=${TF_VERSION}"
    --build-arg "TF_BUILD_JOBS=${TF_BUILD_JOBS}"
    --build-arg "TF_LOCAL_RAM_MB=${TF_LOCAL_RAM_MB}"
    -t "$IMAGE_TAG"
    "$SCRIPT_DIR"
)

printf '\nFrigate J5005 experimental build\n'
printf '  Frigate version : %s\n' "$FRIGATE_VERSION"
printf '  TensorFlow      : %s\n' "$TF_VERSION"
printf '  Parallel jobs   : %s\n' "$TF_BUILD_JOBS"
printf '  Bazel RAM budget: %s MB\n' "$TF_LOCAL_RAM_MB"
printf '  Image tag       : %s\n' "$IMAGE_TAG"
printf '  Screen session  : %s\n' "$SCREEN_SESSION"
printf '  Build log       : %s\n\n' "$LOG_FILE"

cat <<MSG
The build will now start in an attached GNU Screen session.
Detach without stopping the build: press Ctrl+A, then D.
MSG
if (( EUID == 0 )); then
    printf "Reattach from your normal account: sudo screen -r '%s'\n" "$SCREEN_SESSION"
    printf "Reattach from a root shell:         screen -r '%s'\n" "$SCREEN_SESSION"
else
    printf "Reattach: screen -r '%s'\n" "$SCREEN_SESSION"
fi
printf "List sessions: screen -ls\n"
printf "Read the log later: tail -f '%s'\n\n" "$LOG_FILE"
printf 'Starting build now...\n\n'

# The screen shell pipes output through tee so the complete log remains available
# even after the screen session exits when the build completes.
screen -S "$SCREEN_SESSION" bash -c \
    'set -o pipefail; "$@" 2>&1 | tee -a "$BUILD_LOG"; status=${PIPESTATUS[0]}; printf "\nDocker build exit code: %s\n" "$status" | tee -a "$BUILD_LOG"; exit "$status"' \
    build.sh "${BUILD_CMD[@]}"

