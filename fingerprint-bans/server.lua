-- ============================================================================
-- Collects ALL player identifiers + hardware tokens
-- Returns: { identifiers = { steam = ..., license = ..., ... },
--            tokens = { "token:...", ... },
--            all = { flat list of values for checkBan } }
-- ============================================================================
local IDENTIFIER_TYPES = {
    'steam', 'license', 'license2', 'discord',
    'xbl', 'live', 'fivem', 'ip'
}

local function getAllPlayerFingerprints(src)
    local result = {
        identifiers = {},
        tokens      = {},
        all         = {}
    }

    -- 1) Platform identifiers (steam, license, discord, ip, etc.)
    for _, idType in ipairs(IDENTIFIER_TYPES) do
        local val = GetPlayerIdentifierByType(src, idType)
        if val and val ~= '' then
            result.identifiers[idType] = val
            result.all[#result.all + 1] = val
        end
    end

    -- 2) Hardware tokens (hardware fingerprint from FiveM)
    local numTokens = GetNumPlayerTokens(src) or 0
    for i = 0, numTokens - 1 do
        local token = GetPlayerToken(src, i)
        if token and token ~= '' then
            result.tokens[#result.tokens + 1] = token
            result.all[#result.all + 1] = token
        end
    end

    return result
end

-- ============================================================================

local function checkBan(identifiers, callback)
    if #identifiers == 0 then
        return callback(nil)
    end

    local placeholders = {}
    for i = 1, #identifiers do
        placeholders[#placeholders + 1] = '?'
    end

    local query = string.format([[
        SELECT
            b.id,
            b.reason,
            b.expires_at,
            b.active,
            bf.type,
            bf.value
        FROM ban_fingerprints bf
        JOIN bans b ON b.id = bf.ban_id
        WHERE bf.value IN (%s)
          AND b.active = true
          AND (b.expires_at IS NULL OR b.expires_at > NOW())
        LIMIT 1
    ]], table.concat(placeholders, ','))

    oxmysql:single(query, identifiers, function(result)
        callback(result)
    end)
end

local function saveBanFingerprints(banId, serverFp, clientData)
    local rows = {}

    -- 1) Server-side platform identifiers (steam, license, discord, ip, etc.)
    if serverFp and serverFp.identifiers then
        for idType, val in pairs(serverFp.identifiers) do
            rows[#rows + 1] = { ban_id = banId, type = idType, value = val }
        end
    end

    -- 2) Server-side hardware tokens
    if serverFp and serverFp.tokens then
        for _, token in ipairs(serverFp.tokens) do
            rows[#rows + 1] = { ban_id = banId, type = 'token', value = token }
        end
    end

    -- 3) Client-side data (NUI + KVP)
    if clientData then
        if clientData.visitorId and clientData.visitorId ~= '' then
            rows[#rows + 1] = { ban_id = banId, type = 'visitorId', value = clientData.visitorId }
        end

        if clientData.localStorageId and clientData.localStorageId ~= '' then
            rows[#rows + 1] = { ban_id = banId, type = 'localStorage', value = clientData.localStorageId }
        end

        if clientData.kvpId and clientData.kvpId ~= '' then
            rows[#rows + 1] = { ban_id = banId, type = 'kvp', value = clientData.kvpId }
        end

        if clientData.devices then
            for _, dev in ipairs(clientData.devices) do
                if type(dev) == 'table' then
                    if dev.deviceId and dev.deviceId ~= '' then
                        rows[#rows + 1] = {
                            ban_id = banId,
                            type   = 'deviceId:' .. (dev.kind or 'unknown'),
                            value  = dev.deviceId
                        }
                    end
                elseif type(dev) == 'string' and dev ~= '' then
                    rows[#rows + 1] = {
                        ban_id = banId,
                        type   = 'deviceId',
                        value  = dev
                    }
                end
            end
        end
    end

    for _, row in ipairs(rows) do
        oxmysql:execute([[
            INSERT INTO ban_fingerprints (ban_id, type, value)
            VALUES (?, ?, ?)
            ON CONFLICT (type, value) DO NOTHING
        ]], { row.ban_id, row.type, row.value })
    end
end

local function banPlayer(src, reason, bannedBy, expiresAt, clientData)
    local serverFp = getAllPlayerFingerprints(src)
    local license  = serverFp.identifiers.license or 'unknown'
    local name     = GetPlayerName(src) or 'unknown'

    oxmysql:scalar([[
        INSERT INTO bans (license, name, reason, banned_by, expires_at)
        VALUES (?, ?, ?, ?, ?)
        RETURNING id
    ]], { license, name, reason, bannedBy, expiresAt }, function(banId)
        if not banId then return end

        saveBanFingerprints(banId, serverFp, clientData)

        DropPlayer(src, ('[CFXMAFIA] Banned: %s'):format(reason))
        print(('[CFXMAFIA] Banned %s (%s) | ban_id: %s'):format(name, license, banId))
    end)
end

RegisterServerEvent('cfxmafia:deviceIds')
AddEventHandler('cfxmafia:deviceIds', function(data)
    local src      = source
    local serverFp = getAllPlayerFingerprints(src)
    local license  = serverFp.identifiers.license or 'unknown'
    local name     = GetPlayerName(src) or 'unknown'

    -- Merge ALL: server-side ids + tokens + client-side fingerprints
    local toCheck = {}

    -- Server-side: identifiers + tokens
    for _, val in ipairs(serverFp.all) do
        toCheck[#toCheck + 1] = val
    end

    -- Client-side: localStorage, KVP, visitorId
    if data.localStorageId and data.localStorageId ~= '' then
        toCheck[#toCheck + 1] = data.localStorageId
    end

    if data.kvpId and data.kvpId ~= '' then
        toCheck[#toCheck + 1] = data.kvpId
    end

    if data.visitorId and data.visitorId ~= '' then
        toCheck[#toCheck + 1] = data.visitorId
    end

    -- Client-side: device IDs
    if data.devices then
        for _, dev in ipairs(data.devices) do
            if type(dev) == 'table' then
                if dev.deviceId and dev.deviceId ~= '' then
                    toCheck[#toCheck + 1] = dev.deviceId
                end
            elseif type(dev) == 'string' and dev ~= '' then
                toCheck[#toCheck + 1] = dev
            end
        end
    end

    checkBan(toCheck, function(ban)
        if ban then
            -- Save ALL new fingerprints to the existing ban
            saveBanFingerprints(ban.id, serverFp, data)

            print(('[CFXMAFIA] Ban evasion attempt | %s (%s) | match: [%s] = %s | ban_id: %s'):format(
                name, license, ban.type, ban.value, ban.id
            ))

            DropPlayer(src, ('[CFXMAFIA] You are banned. Reason: %s'):format(
                ban.reason or 'no reason'
            ))
            return
        end

        print(('[CFXMAFIA] Clean player: %s | ids: %d | tokens: %d | ls: %s | kvp: %s'):format(
            license,
            #serverFp.all - #serverFp.tokens,
            #serverFp.tokens,
            tostring(data.localStorageId),
            tostring(data.kvpId)
        ))
    end)
end)

exports('BanPlayer', banPlayer)
exports('GetAllPlayerFingerprints', getAllPlayerFingerprints)