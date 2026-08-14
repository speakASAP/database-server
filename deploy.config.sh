# deploy.config.sh — declaration consumed by shared/scripts/deploy.sh.
#
# SCOPE: this config deploys ONLY database-server-frontend (the landing/admin
# panel built from web/). It deliberately does NOT touch the datastores.
#
# scripts/deploy.sh remains the authoritative path for db-server-postgres and
# db-server-redis. That script manages StatefulSet-backed shared datastores
# that every service in the ecosystem depends on; it has no docker build and
# should not gain one. Do not merge the two paths.
#
# Why this exists: database-server-frontend was outside every deploy path.
#   - k8s/frontend.yaml is not in scripts/deploy.sh's manifest loop (the loop
#     lists deployment.yaml/service.yaml/ingress.yaml, none of which exist in
#     k8s/, and an `if [ -f ]` guard skips them silently)
#   - database-server-frontend is not in DB_DEPLOYMENTS, so it never restarts
#   - nothing ever ran `docker build` for it
# The running pod therefore survives only from a past manual apply, pinned to
# :latest. Changes under web/ could not reach production at all.
#
# frontend.yaml carries Deployment + Service + Ingress in one file, so it is
# the only manifest listed here. DEPLOYMENTS names the deployment so
# `kubectl set image` replaces the hardcoded :latest with the SHA tag.

SERVICE_NAME="database-server-frontend"
PORT="3390"

IMAGES=(
  "database-server-frontend|web||"
)

DEPLOYMENTS=(
  "database-server-frontend|app|database-server-frontend"
)

MANIFESTS=(frontend.yaml)
