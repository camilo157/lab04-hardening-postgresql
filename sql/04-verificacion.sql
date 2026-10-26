SHOW listen_addresses;
SHOW ssl;
SHOW password_encryption;
SHOW log_connections;
SHOW log_disconnections;
SHOW idle_in_transaction_session_timeout;

SELECT line_number, type, database, user_name, address, auth_method, error
FROM pg_hba_file_rules;

SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname !~ '^pg_'
ORDER BY rolname;

SELECT name, setting, pending_restart
FROM pg_settings
WHERE name IN ('listen_addresses', 'ssl', 'log_connections',
               'log_disconnections', 'idle_in_transaction_session_timeout');

SELECT a.pid, a.usename, a.client_addr, s.ssl, s.version, s.cipher
FROM pg_stat_ssl s
JOIN pg_stat_activity a ON a.pid = s.pid
WHERE s.pid = pg_backend_pid();