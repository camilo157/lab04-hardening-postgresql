ALTER SYSTEM SET ssl = 'on';
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET idle_in_transaction_session_timeout = '60s';

-- este cambio solo se aplica al reiniciar
ALTER SYSTEM SET listen_addresses = 'localhost';

SELECT pg_reload_conf();

SELECT name, setting, pending_restart
FROM pg_settings
WHERE name IN ('ssl', 'log_connections', 'log_disconnections',
               'idle_in_transaction_session_timeout', 'listen_addresses');