# Database Server Web - landing + admin panel
FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./
COPY public ./public

ENV NODE_ENV=production
ENV PORT=3390
EXPOSE 3390

CMD ["node", "server.js"]
