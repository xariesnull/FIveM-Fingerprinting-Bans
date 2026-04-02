CREATE TABLE bans (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license     TEXT,
    name        TEXT,
    reason      TEXT,
    banned_by   TEXT,
    banned_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at  TIMESTAMP NULL,
    active      BOOLEAN DEFAULT true
);

CREATE TABLE ban_fingerprints (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ban_id      UUID NOT NULL REFERENCES bans(id) ON DELETE CASCADE,
    type        TEXT NOT NULL, -- 'license' | 'license2' | 'steam' | 'discord' | 'xbl' | 'live' | 'fivem' | 'ip' | 'token' | 'visitorId' | 'deviceId' | 'localStorage' | 'kvp'
    value       TEXT NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(type, value)
);

CREATE INDEX idx_ban_fingerprints_value ON ban_fingerprints(value);
CREATE INDEX idx_ban_fingerprints_type  ON ban_fingerprints(type);