ARG BILLIONMAIL_CORE_VERSION=4.9.3

FROM golang:1.24-alpine AS builder
ARG TARGETARCH
WORKDIR /src

RUN apk add --no-cache ca-certificates git

COPY core/go.mod core/go.sum ./
RUN go mod download

COPY core/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags='-s -w' -o /out/billionmail main.go

FROM billionmail/core:${BILLIONMAIL_CORE_VERSION}

COPY --from=builder /out/billionmail /opt/billionmail/core/billionmail
COPY core/manifest /opt/billionmail/core/manifest
COPY core/languages /opt/billionmail/core/languages
COPY core/public /opt/billionmail/core/public
COPY core/resource /opt/billionmail/core/resource
COPY core/template /opt/billionmail/core/template

RUN chmod 0755 /opt/billionmail/core/billionmail
