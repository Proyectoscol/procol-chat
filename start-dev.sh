#!/bin/bash
# Script para levantar el servidor de desarrollo localmente (fuera de Docker)
export PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH"
export POSTGRES_HOST=localhost
export POSTGRES_USERNAME=camilocastillo
export POSTGRES_PASSWORD=
export REDIS_URL=redis://localhost:6379
export VITE_RUBY_HOST=localhost

cd "$(dirname "$0")"

echo "Starting Vite dev server..."
VITE_RUBY_HOST=localhost bin/vite dev > /tmp/vite-dev.log 2>&1 &
VITE_PID=$!

echo "Starting Rails server..."
VITE_RUBY_HOST=localhost bundle exec rails s -p 3000 > /tmp/rails-dev.log 2>&1 &
RAILS_PID=$!

echo "Vite PID: $VITE_PID  Rails PID: $RAILS_PID"
echo "Logs: /tmp/rails-dev.log  /tmp/vite-dev.log"
echo ""
echo "Waiting for Rails to boot..."
sleep 10
curl -s -o /dev/null -w "Rails: %{http_code}\n" http://localhost:3000/
echo "App at http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop both servers"

trap "kill $VITE_PID $RAILS_PID 2>/dev/null; echo 'Servers stopped.'" EXIT
wait
