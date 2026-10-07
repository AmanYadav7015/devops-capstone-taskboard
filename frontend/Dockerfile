FROM node:22-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

FROM nginx:1.31-alpine AS runtime

RUN apk upgrade --no-cache \
 && apk add --no-cache --virtual .build-deps libcap \
 && setcap cap_net_bind_service=+ep /usr/sbin/nginx \
 && apk del .build-deps \
 && mkdir -p /var/cache/nginx /var/run \
 && touch /var/run/nginx.pid \
 && chown -R nginx:nginx /var/cache/nginx /var/log/nginx /var/run/nginx.pid /etc/nginx/conf.d /usr/share/nginx/html

COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf

USER nginx
EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=6 \
  CMD wget --quiet --spider --tries=1 http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
