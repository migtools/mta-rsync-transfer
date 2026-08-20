######################################################################
# Establish a common builder image for all golang-based images
FROM registry.redhat.io/ubi9/go-toolset:1.25 AS golang-builder
USER root
WORKDIR /workspace
# We don't vendor modules. Enforce that behavior
ENV GOFLAGS=-mod=readonly
ENV GO111MODULE=on
ARG TARGETOS
ARG TARGETARCH
ENV GOOS=${TARGETOS:-linux}
ENV GOARCH=${TARGETARCH}

######################################################################
# Build block binary
FROM golang-builder AS blockrsync-builder

# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

# Copy the go source
COPY cmd/ cmd/
COPY ./pkg/. pkg/

# Build
RUN CGO_ENABLED=0 go build -o blockrsync ./cmd/blockrsync/main.go
RUN CGO_ENABLED=0 go build -o proxy ./cmd/proxy/main.go
RUN CGO_ENABLED=0 go build -o rclone ./cmd/rclone/main.go

######################################################################
# Final container
FROM registry.redhat.io/ubi9/ubi-minimal:latest
RUN microdnf update -y
RUN microdnf -y install openssh-server stunnel rsync nmap && microdnf clean all
COPY sshd_config /etc/ssh/sshd_config
COPY stunnel.conf /etc/stunnel/stunnel.conf
COPY LICENSE /licenses/
USER 65534:65534

WORKDIR /

##### blockrsync
COPY --from=blockrsync-builder /workspace/blockrsync /blockrsync
COPY --from=blockrsync-builder /workspace/proxy /proxy
COPY --from=blockrsync-builder /workspace/rclone /usr/local/bin/rclone

# Smoke test — verify binaries are functional
RUN /blockrsync --help && \
    rclone --version && \
    rsync --version

LABEL \
    description="MTA-Ops rsync transfer image for PVC data migration" \
    io.k8s.description="MTA-Ops rsync transfer image for PVC data migration" \
    io.k8s.display-name="MTA-Ops Rsync Transfer" \
    io.openshift.maintainer.project="MTA" \
    io.openshift.tags="migration,modernization,konveyor,rsync,transfer" \
    summary="MTA-Ops rsync transfer"
