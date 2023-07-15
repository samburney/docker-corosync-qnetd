FROM ghcr.io/linuxserver/baseimage-debian:bookworm
LABEL maintainer="Sam Burney <sam@burney.io>"

RUN apt-get update \
    && apt-get install -y corosync-qnetd openssh-server \
    && apt-get clean

COPY docker/root /

EXPOSE 22/tcp
EXPOSE 5403//tcp

VOLUME /etc/ssh/keys
VOLUME /root