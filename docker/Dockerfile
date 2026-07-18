FROM node:20-alpine

# Install NUT and apcupsd clients for monitoring
RUN apk add --no-cache nut-client apcupsd bash

WORKDIR /app

COPY backend/package*.json ./
RUN npm install --production

COPY backend/ ./
COPY frontend/public/ /app/frontend/public/
COPY scripts/ /app/scripts/

EXPOSE 13456

ENV PORT=13456

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:13456/api/system/info || exit 1

CMD ["node", "app.js"]
