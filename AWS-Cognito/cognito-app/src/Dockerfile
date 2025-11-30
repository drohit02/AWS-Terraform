FROM node:lts-alpine as builder

WORKDIR /app

ENV PATH = /app/node_modules/.bin:$PATH

COPY pakage.json pakage-lock.json /app/

RUN apk add --no-cache --virtual .gyp \
    python3 \
    make \
    g++

RUN npm cache clean --force

RUN npm install -g serve@13.0.4
RUN npm clean install --silent

COPY . /app/

RUN npm run builde

FROM nginx:1.29-bookworm

WORKDIR /usr/share/nginx/html

COPY --from=builder /app/build /usr/share/nginx/html

#COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf

Expose 80

CMD ["nginx", "-g", "daemon off;"]