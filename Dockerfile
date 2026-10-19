FROM ghcr.io/linuxserver/baseimage-debian:trixie
LABEL maintainer="Sam Burney <sam@burney.io>"

RUN apt-get update \
    && apt-get install -y --no-install-recommends corosync-qnetd openssh-server \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_*

COPY docker/root /

EXPOSE 22/tcp
EXPOSE 5403/tcp

VOLUME /etc/corosync/qnetd
VOLUME /etc/ssh/keys
VOLUME /root
