FROM alpine

RUN apk add --no-cache bash
ADD mo /usr/local/bin/mo
RUN chmod +x /usr/local/bin/mo

ENTRYPOINT /usr/local/bin/mo
