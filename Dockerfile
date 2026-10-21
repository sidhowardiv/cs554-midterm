FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src
COPY --chown=node:node test ./test
USER node
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
