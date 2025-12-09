FROM debian:13

RUN apt update && apt upgrade -y
RUN apt install postgresql-client -y 
RUN apt-get clean; rm -rf /var/lib/apt/lists/*

COPY pgdump.sh /pgdump.sh

RUN mkdir /data; chown 1001 /data
USER 1001

ENTRYPOINT ["sleep", "infinity" ]

# docker buildx build --platform linux/amd64 -t pgdump:0.7 . 
# docker tag pgdump:0.7 vvang/pgdump:0.7 
# docker push vvang/pgdump:0.7 

