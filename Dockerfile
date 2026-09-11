# Chit — static site served by nginx.
# Portable OCI image so it can run on ZopDay (or any container platform:
# Kubernetes, a plain VM, Cloud Run, ECS). No build step: plain HTML/CSS/JS.
FROM nginx:1.27-alpine

# The listen port is templated at boot so an auto-building platform can inject
# $PORT. 8080 by default: non-privileged, friendly to a Kubernetes securityContext.
ENV PORT=8080

COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY . /usr/share/nginx/html

# Never web-serve the build/config context
RUN rm -f /usr/share/nginx/html/Dockerfile \
          /usr/share/nginx/html/nginx.conf \
          /usr/share/nginx/html/.dockerignore \
          /usr/share/nginx/html/vercel.json \
          /usr/share/nginx/html/deploy.sh \
          /usr/share/nginx/html/DEPLOY.md \
          /usr/share/nginx/html/package.json \
    && rm -rf /usr/share/nginx/html/.vercel \
              /usr/share/nginx/html/api \
              /usr/share/nginx/html/node_modules

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- "http://127.0.0.1:${PORT}/healthz" || exit 1
