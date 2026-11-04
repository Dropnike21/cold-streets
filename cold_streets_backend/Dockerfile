# Cold Streets private Node.js staging API (packaging only; not deployed)
FROM node:24-bookworm-slim

ENV NODE_ENV=production \
    ENABLE_GAMEPLAY_API=false \
    ENABLE_UNSAFE_LEGACY_TIMERS=false

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY . .
USER node
EXPOSE 3000
CMD ["node", "server.js"]
