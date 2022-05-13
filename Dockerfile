FROM bitnami/postgresql:14.2.0

COPY pgdump.sh /pgdump.sh

USER root
RUN mkdir /data; chown 1001 /data
USER 1001

ENTRYPOINT while : ; do sleep 60 ; done

