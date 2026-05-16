-- =============================================================
-- Migration: Profil-Erweiterung, Nutzertypen & Rollen
-- Fügt user_type (private/business), phone, company_name
-- und email_notifications zu allen Schemas hinzu.
-- =============================================================

DO $migration$
DECLARE
  schemas TEXT[] := ARRAY['auktivo_dev', 'auktivo_test', 'auktivo_prod'];
  s TEXT;
BEGIN
  FOREACH s IN ARRAY schemas LOOP

    -- user_type: private | business
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS user_type text NOT NULL DEFAULT ''private'' CHECK (user_type IN (''private'', ''business''))',
      s
    );

    -- phone number (optional)
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS phone text',
      s
    );

    -- company name for business accounts
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS company_name text',
      s
    );

    -- email notification preference
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS email_notifications boolean NOT NULL DEFAULT true',
      s
    );

    -- Index for user_type lookups
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS profiles_%s_user_type_idx ON %I.profiles (user_type)',
      replace(s, '-', '_'), s
    );

  END LOOP;
END $migration$;
-- =============================================================
-- Migration: Profil-Erweiterung, Nutzertypen & Rollen
-- Fügt user_type (private/business), phone, company_name
-- und email_notifications zu allen Schemas hinzu.
-- =============================================================

DO $migration$
DECLARE
  schemas TEXT[] := ARRAY['auktivo_dev', 'auktivo_test', 'auktivo_prod'];
  s TEXT;
BEGIN
  FOREACH s IN ARRAY schemas LOOP

    -- user_type: private | business
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS user_type text NOT NULL DEFAULT ''private'' CHECK (user_type IN (''private'', ''business''))',
      s
    );

    -- phone number (optional)
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS phone text',
      s
    );

    -- company name for business accounts
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS company_name text',
      s
    );

    -- email notification preference
    EXECUTE format(
      'ALTER TABLE %I.profiles ADD COLUMN IF NOT EXISTS email_notifications boolean NOT NULL DEFAULT true',
      s
    );

    -- Index for user_type lookups
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS profiles_%s_user_type_idx ON %I.profiles (user_type)',
      replace(s, '-', '_'), s
    );

  END LOOP;
END $migration$;
