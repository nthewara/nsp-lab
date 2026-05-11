-- Idempotent seed: create the events table and grant the UAMI access.
-- Run as the Entra admin (the agent SP), connected to the *database* db-nsp-lab.
--   sqlcmd -G -S <sql_server_fqdn> -d db-nsp-lab -i seed.sql

IF OBJECT_ID(N'dbo.events', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.events (
        id         INT IDENTITY(1,1) PRIMARY KEY,
        source     NVARCHAR(64)  NOT NULL,
        message    NVARCHAR(400) NOT NULL,
        created_at DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Create the UAMI as a contained user. Replace <UAMI_NAME> at deploy time via sed.
-- The script `seed-from-jump.sh` rewrites this placeholder.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'__UAMI_NAME__')
BEGIN
    CREATE USER [__UAMI_NAME__] FROM EXTERNAL PROVIDER;
END
GO

ALTER ROLE db_datareader ADD MEMBER [__UAMI_NAME__];
ALTER ROLE db_datawriter ADD MEMBER [__UAMI_NAME__];
GO
