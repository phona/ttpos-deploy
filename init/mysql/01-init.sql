-- TTPOS Local Development MySQL Initialization
-- This script runs on first container startup

-- Create application database
CREATE DATABASE IF NOT EXISTS ttpos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create Nacos database (for service discovery)
CREATE DATABASE IF NOT EXISTS nacos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Grant permissions for application user
GRANT ALL PRIVILEGES ON ttpos.* TO 'ttpos'@'%';

-- Grant permissions for Nacos
GRANT ALL PRIVILEGES ON nacos.* TO 'root'@'%';

FLUSH PRIVILEGES;

-- Log completion
SELECT 'MySQL initialization complete' AS status;
