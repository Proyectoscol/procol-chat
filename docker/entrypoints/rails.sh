#!/bin/sh

set -x

# Remove a potentially pre-existing server.pid for Rails.
rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

echo "Waiting for postgres to become ready...."

# Let DATABASE_URL env take presedence over individual connection params.
# This is done to avoid printing the DATABASE_URL in the logs
$(docker/entrypoints/helpers/pg_database_url.rb)
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

until $PG_READY
do
  sleep 2;
done

echo "Database ready to accept connections."

#install missing gems for local dev as we are using base image compiled for production
bundle install

BUNDLE="bundle check"

until $BUNDLE
do
  sleep 2;
done

# Procol Auditoria: prende el feature para la cuenta y reconcilia agentes en
# cada boot (ver lib/tasks/auditoria.rake) - no-op para cualquier deploy que
# no tenga esta variable seteada (p.ej. el procol-chat multi-tenant normal).
if [ -n "$AUDITORIA_ACCOUNT_ID" ]; then
  bundle exec rake auditoria:reconcile_agents ACCOUNT_ID="$AUDITORIA_ACCOUNT_ID" || echo "Auditoria: reconcile_agents fallo, continuando el boot"
fi

# Execute the main process of the container
exec "$@"
