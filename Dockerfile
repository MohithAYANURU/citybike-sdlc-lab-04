# Stage 1: Build
FROM node:20 AS builder

ARG GITHUB_SHA=local-dev
ENV GITHUB_SHA=${GITHUB_SHA}

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# Stage 2: Runtime
FROM node:20-alpine

WORKDIR /app

COPY --chown=node:node server.js ./
COPY --chown=node:node public ./public
COPY --chown=node:node --from=builder /app/dist/build-manifest.json ./dist/build-manifest.json

USER node

EXPOSE 4173

CMD ["node", "server.js"]
