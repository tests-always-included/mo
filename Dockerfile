FROM alpine:3.13.4

COPY ./mo .
RUN apk add --update bash && \
    chmod +x mo &&\
    mv mo /usr/local/bin/mo && \
    rm -rf /var/cache/apk/*

WORKDIR /opt

ENTRYPOINT ["/usr/local/bin/mo"]