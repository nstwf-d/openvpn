FROM d3vilh/openvpn-ui:latest AS ui-provider

FROM alpine:latest

WORKDIR /opt/app

RUN apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add \
    bash \
    bind-tools \
    oath-toolkit-oathtool \
    curl \
    ip6tables \
    iptables \
    sqlite \
    openvpn \
    easy-rsa \
    openssl \
    libc6-compat \
    ca-certificates

COPY --from=ui-provider /opt/openvpn-ui /opt/openvpn-ui

COPY bin /opt/app/bin
COPY config /opt/app/config
COPY config/server.conf /opt/app/server.conf
COPY docker-entrypoint.sh /opt/app/docker-entrypoint.sh
COPY config/openssl-easyrsa.cnf /opt/app/easy-rsa/

RUN mkdir -p /opt/app/clients \
    /opt/app/db \
    /opt/app/log \
    /opt/app/pki \
    /opt/app/staticclients \
    /etc/openvpn \
    /var/log/openvpn \
    /opt/scripts

RUN ln -s /opt/app/bin/genclient.sh /opt/scripts/genclient.sh && \
    ln -s /opt/app/bin/genclient.sh /opt/scripts/generate_client.sh && \
    ln -s /opt/app/bin/revoke.sh /opt/scripts/revoke.sh && \
    ln -s /opt/app/bin/revoke.sh /opt/scripts/revoke_client.sh && \
    ln -s /opt/app/bin/rmcert.sh /opt/scripts/rmcert.sh && \
    ln -s /opt/app/bin/rmcert.sh /opt/scripts/rmcert_client.sh && \
    ln -s /opt/app/bin/oath.sh /opt/scripts/oath.sh && \
    ln -s /opt/app/bin/oath-sec-gen.sh /opt/scripts/oath-sec-gen.sh

RUN chmod +x /opt/app/bin/* && chmod +x /opt/app/docker-entrypoint.sh

EXPOSE 1194/udp 8080/tcp

ENTRYPOINT ["/opt/app/docker-entrypoint.sh"]
