FROM nginx:1.28-alpine

RUN apk add --no-cache gettext \
 && mkdir -p /etc/nginx/certs /etc/nginx/templates /var/log/nginx \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

COPY docker/nginx/nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY docker/nginx/docker-entrypoint.sh /docker-entrypoint-nginx-upstream.sh

RUN chmod 755 /docker-entrypoint-nginx-upstream.sh

EXPOSE 80 443

ENTRYPOINT ["/docker-entrypoint-nginx-upstream.sh"]
