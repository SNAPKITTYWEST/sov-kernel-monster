FROM scratch

COPY --chown=1000:1000 ./bin/sov-core /bin/sov-core
COPY ./etc/sov-config /etc/sov-config

USER 1000
ENTRYPOINT ["/bin/sov-core", "--local-only"]
