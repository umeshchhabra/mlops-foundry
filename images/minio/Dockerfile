FROM alpine:3.20

ARG TARGETARCH
ARG MINIO_RELEASE=RELEASE.2025-09-07T16-13-09Z
ARG MC_RELEASE=RELEASE.2025-08-13T08-35-41Z

RUN set -eux; \
    case "$TARGETARCH" in amd64|arm64) ;; *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; esac; \
    apk add --no-cache ca-certificates curl; \
    minio_name="minio.linux-${TARGETARCH}.${MINIO_RELEASE}"; \
    mc_name="mc.linux-${TARGETARCH}.${MC_RELEASE}"; \
    curl -fsSLO "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/${minio_name}"; \
    curl -fsSLO "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/${minio_name}.sha256sum"; \
    printf '%s  %s\n' "$(awk '{print $1}' "${minio_name}.sha256sum")" "$minio_name" | sha256sum -c -; \
    curl -fsSLO "https://github.com/minio/mc/releases/download/${MC_RELEASE}/${mc_name}"; \
    curl -fsSLO "https://github.com/minio/mc/releases/download/${MC_RELEASE}/${mc_name}.sha256sum"; \
    printf '%s  %s\n' "$(awk '{print $1}' "${mc_name}.sha256sum")" "$mc_name" | sha256sum -c -; \
    install -m 0755 "$minio_name" /usr/local/bin/minio; \
    install -m 0755 "$mc_name" /usr/local/bin/mc; \
    rm -f "$minio_name" "${minio_name}.sha256sum" "$mc_name" "${mc_name}.sha256sum"

ENTRYPOINT ["minio"]
