# syntax=docker/dockerfile:1.7
# Experimental Frigate build for Intel J5005: TensorFlow CPU with AVX/AVX2/FMA disabled.
# Build the wheel in a separate Debian stage; only install the wheel into Frigate.

ARG FRIGATE_VERSION=0.18.2
ARG TF_VERSION=2.19.1
ARG TF_BUILD_JOBS=2
ARG TF_LOCAL_RAM_MB=4096

FROM debian:bookworm AS tensorflow-build
ARG TF_VERSION
ARG TF_BUILD_JOBS
ARG TF_LOCAL_RAM_MB
USER root

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PYTHON_BIN_PATH=/usr/bin/python3 \
    USE_DEFAULT_PYTHON_LIB_PATH=1 \
    TF_NEED_CUDA=0 \
    TF_NEED_ROCM=0 \
    TF_NEED_CLANG=1 \
    CLANG_COMPILER_PATH=/usr/lib/llvm-18/bin/clang \
    TF_DOWNLOAD_CLANG=0 \
    TF_NEED_OPENCL_SYCL=0 \
    TF_NEED_MPI=0 \
    TF_SET_ANDROID_WORKSPACE=0 \
    CC_OPT_FLAGS="-Wno-sign-compare -mno-avx -mno-avx2 -mno-fma -mno-avx512f"

# Keep compiler/build dependencies out of the Frigate runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg lsb-release software-properties-common \
    && curl -fsSL https://apt.llvm.org/llvm.sh -o /tmp/llvm.sh \
    && chmod 0755 /tmp/llvm.sh \
    && /tmp/llvm.sh 18 \
    && apt-get update && apt-get install -y --no-install-recommends \
      git build-essential python3 python3-dev python3-pip python3-venv \
      zip unzip openjdk-17-jdk-headless clang-18 \
    && rm -rf /var/lib/apt/lists/* /tmp/llvm.sh

RUN python3 -m pip install --no-cache-dir --upgrade \
      pip setuptools wheel packaging numpy==1.26.4

# Select the requested TensorFlow source tag.
RUN git clone --depth 1 --branch "v${TF_VERSION}" \
      https://github.com/tensorflow/tensorflow.git /src/tensorflow
WORKDIR /src/tensorflow

# Use the Bazel version specified by this exact TensorFlow source release.
# This avoids silently building a different TensorFlow version with a stale Bazel.
RUN set -eux; \
    BAZEL_VERSION="$(head -n 1 .bazelversion | sed 's/#.*//' | tr -d '\r' | xargs)"; \
    case "$BAZEL_VERSION" in \
      ''|*[!0-9.]*) echo "Invalid Bazel version: '$BAZEL_VERSION'" >&2; exit 1 ;; \
    esac; \
    echo "Using Bazel version: ${BAZEL_VERSION}"; \
    curl -fsSL \
      "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-linux-x86_64" \
      -o /usr/local/bin/bazel; \
    chmod 0755 /usr/local/bin/bazel; \
    bazel --version; \
    /usr/lib/llvm-18/bin/clang --version; \
    python3 --version

RUN ./configure

# BuildKit preserves Bazel's repository/action cache between failed attempts.
# Cache IDs are separated by TensorFlow version to avoid mixing source versions.
RUN --mount=type=cache,id=tf-bazel-${TF_VERSION},target=/root/.cache/bazel,sharing=locked \
    set -eux; \
    bazel build \
      --config=opt \
      --copt=-Wno-gnu-offsetof-extensions \
      --jobs="${TF_BUILD_JOBS}" \
      --local_ram_resources="${TF_LOCAL_RAM_MB}" \
      --repo_env=USE_PYWRAP_RULES=1 \
      --repo_env=WHEEL_NAME=tensorflow_cpu \
      //tensorflow/tools/pip_package:wheel; \
    mkdir -p /wheel; \
    find -L bazel-bin -type f -name "tensorflow_cpu-${TF_VERSION}-*.whl" -exec cp -v {} /wheel/ \;; \
    test -n "$(find /wheel -maxdepth 1 -type f -name '*.whl' -print -quit)"

FROM ghcr.io/blakeblackshear/frigate:${FRIGATE_VERSION} AS runtime
ARG FRIGATE_VERSION
ARG TF_VERSION
USER root
COPY --from=tensorflow-build /wheel/ /tmp/custom-tensorflow-wheel/

RUN set -eux; \
    wheel="$(find /tmp/custom-tensorflow-wheel -maxdepth 1 -type f -name "tensorflow_cpu-${TF_VERSION}-*.whl" -print -quit)"; \
    test -n "$wheel"; \
    PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --no-deps --force-reinstall "$wheel"; \
    rm -rf /tmp/custom-tensorflow-wheel

LABEL org.opencontainers.image.title="Frigate ${FRIGATE_VERSION} J5005 experimental no-AVX TensorFlow build"
LABEL org.opencontainers.image.description="Frigate ${FRIGATE_VERSION} with TensorFlow CPU ${TF_VERSION} rebuilt with AVX/AVX2/FMA disabled"

