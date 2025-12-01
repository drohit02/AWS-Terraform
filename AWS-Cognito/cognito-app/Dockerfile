# Stage 1: Build
FROM node:lts-alpine as builder

WORKDIR /app

ENV PATH=/app/node_modules/.bin:$PATH

COPY package.json package-lock.json /app/

RUN apk add --no-cache --virtual .gyp \
    python3 \
    make \
    g++

RUN npm cache clean --force

RUN npm clean install --silent

COPY . /app/

RUN npm run build

# Stage 2: Production
FROM nginx:1.29-bookworm

WORKDIR /usr/share/nginx/html

COPY --from=builder /app/build /usr/share/nginx/html

#COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]