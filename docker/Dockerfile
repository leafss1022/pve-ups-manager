FROM node:20-alpine

RUN apk add --no-cache nut nut-client curl

WORKDIR /app

COPY backend/package*.json /app/backend/
RUN cd /app/backend && npm install --production

COPY backend/ /app/backend/
COPY frontend/public/ /app/frontend/public/

RUN mkdir -p /etc/pve-ups-manager

EXPOSE 3456

WORKDIR /app/backend
CMD ["node", "app.js"]