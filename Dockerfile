FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/agent-status-server ./cmd/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/agent-status-server /usr/local/bin/agent-status-server
ENV AGENT_STATUS_ADDR=:8080
EXPOSE 8080
ENTRYPOINT ["agent-status-server"]
