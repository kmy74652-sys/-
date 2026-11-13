FROM node:22-bookworm-slim

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
ENV NODE_ENV=production

RUN corepack enable && corepack prepare pnpm@11.25.0 --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json ./
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json

RUN pnpm install --frozen-lockfile

COPY apps ./apps
COPY scripts ./scripts
COPY supabase ./supabase
COPY README.md plan.md TODO.md ./

RUN pnpm build

ENV PORT=3000
EXPOSE 3000

CMD ["node", "apps/api/dist/server.js"]
