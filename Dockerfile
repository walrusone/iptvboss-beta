# syntax=docker/dockerfile:1

FROM debian:bookworm-slim AS release

ARG TARGETARCH
ARG IPTVBOSS_VERSION
ARG IPTVBOSS_RELEASE_REPOSITORY=walrusone/iptvboss-beta
ARG IPTVBOSS_SHA256_AMD64
ARG IPTVBOSS_SHA256_ARM64

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "${TARGETARCH}" in \
        amd64) \
            release_arch="amd64"; \
            expected_sha256="${IPTVBOSS_SHA256_AMD64}"; \
            ;; \
        arm64) \
            release_arch="aarch64"; \
            expected_sha256="${IPTVBOSS_SHA256_ARM64}"; \
            ;; \
        *) \
            echo "Unsupported Docker architecture: ${TARGETARCH}" >&2; \
            exit 1; \
            ;; \
    esac; \
    if [ -z "${IPTVBOSS_VERSION}" ]; then \
        echo "IPTVBOSS_VERSION must be provided" >&2; \
        exit 1; \
    fi; \
    if [ -z "${expected_sha256}" ]; then \
        echo "A SHA-256 checksum must be provided for ${TARGETARCH}" >&2; \
        exit 1; \
    fi; \
    artifact="iptvboss-${IPTVBOSS_VERSION}-linux-${release_arch}.tar.gz"; \
    url="https://github.com/${IPTVBOSS_RELEASE_REPOSITORY}/releases/download/${IPTVBOSS_VERSION}/${artifact}"; \
    curl --fail --location --retry 3 --output "/tmp/${artifact}" "${url}"; \
    echo "${expected_sha256}  /tmp/${artifact}" | sha256sum --check --strict; \
    mkdir -p /opt/iptvboss; \
    tar --extract --gzip --file "/tmp/${artifact}" --directory /opt/iptvboss --strip-components=1; \
    test -x /opt/iptvboss/bin/iptvboss-c

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl libstdc++6 tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 iptvboss \
    && useradd --uid 10001 --gid 10001 --home-dir /data --no-create-home --shell /usr/sbin/nologin iptvboss \
    && install --directory --owner=10001 --group=10001 /data

COPY --from=release --chown=10001:10001 /opt/iptvboss /opt/iptvboss

WORKDIR /data
USER 10001:10001

VOLUME ["/data"]
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl --fail --silent --show-error http://127.0.0.1:8001/healthz >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/iptvboss/bin/iptvboss-c", "-xcserver", "-directory", "/data"]
