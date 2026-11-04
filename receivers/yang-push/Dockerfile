FROM rust:1.90-bookworm AS build
WORKDIR /src
# NetCalyx v0.3.0: build the unmodified upstream decoded UDP-Notif receiver.
ADD https://github.com/network-analytics/NetCalyx/archive/f1175e46a6164bfa103ef108385ba9beeff3d753.tar.gz /tmp/netcalyx.tar.gz
RUN tar -xzf /tmp/netcalyx.tar.gz --strip-components=1 \
    && cargo build --locked --release --jobs 2 \
       -p netcalyx-udp-notif-service --example udp-notif-print-decoded

FROM telegraf:1.36.4
USER root
RUN apt-get update && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/release/examples/udp-notif-print-decoded /usr/local/bin/netcalyx-udp-notif
COPY --from=build /src/LICENSE /src/NOTICE /usr/share/doc/netcalyx/
EXPOSE 9999/udp 9273/tcp
ENTRYPOINT ["/usr/bin/telegraf"]
CMD ["--config", "/etc/telegraf/telegraf.conf"]
