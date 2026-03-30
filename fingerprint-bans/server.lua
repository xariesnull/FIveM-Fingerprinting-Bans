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

local function saveBanFingerprints(banId, license, visitorId, devices)
    local rows = {}

    if license then
        rows[#rows + 1] = { ban_id = banId, type = 'license', value = license }
    end

    if visitorId then
        rows[#rows + 1] = { ban_id = banId, type = 'visitorId', value = visitorId }
    end

    if devices then
        for _, dev in ipairs(devices) do
            if dev.deviceId and dev.deviceId ~= '' then
                rows[#rows + 1] = {
                    ban_id = banId,
                    type   = 'deviceId:' .. (dev.kind or 'unknown'),
                    value  = dev.deviceId
                }
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

local function banPlayer(src, reason, bannedBy, expiresAt, fpData)
    local license = GetPlayerIdentifierByType(src, 'license') or 'unknown'
    local name    = GetPlayerName(src) or 'unknown'

    oxmysql:scalar([[
        INSERT INTO bans (license, name, reason, banned_by, expires_at)
        VALUES (?, ?, ?, ?, ?)
        RETURNING id
    ]], { license, name, reason, bannedBy, expiresAt }, function(banId)
        if not banId then return end

        saveBanFingerprints(banId, license, fpData and fpData.visitorId, fpData and fpData.devices)

        DropPlayer(src, ('[CFXMAFIA] Zbanowany: %s'):format(reason))
        print(('[CFXMAFIA] Zbanowano %s (%s) | ban_id: %s'):format(name, license, banId))
    end)
end

RegisterServerEvent('cfxmafia:fingerprint')
AddEventHandler('cfxmafia:fingerprint', function(data)
    local src     = source
    local license = GetPlayerIdentifierByType(src, 'license') or 'unknown'
    local name    = GetPlayerName(src) or 'unknown'

    local toCheck = { license }

    if data.visitorId then
        toCheck[#toCheck + 1] = data.visitorId
    end

    if data.devices then
        for _, dev in ipairs(data.devices) do
            if dev.deviceId and dev.deviceId ~= '' then
                toCheck[#toCheck + 1] = dev.deviceId
            end
        end
    end

    checkBan(toCheck, function(ban)
        if ban then
            -- Zapisz nowe identyfikatory do istniejącego bana
            -- Jeśli koleś zmienił konto/sprzęt, nowe UUIDs też wpadają do bazy
            -- Przy następnej próbie połączenia już nie przejdzie nawet z nowym sprzętem
            saveBanFingerprints(
                ban.id,
                license,
                data.visitorId,
                data.devices
            )

            print(('[CFXMAFIA] Ban evasion attempt | %s (%s) | match: [%s] = %s | nowe ID zapisane do ban_id: %s'):format(
                name, license, ban.type, ban.value, ban.id
            ))

            DropPlayer(src, ('[CFXMAFIA] Jesteś zbanowany. Powód: %s'):format(
                ban.reason or 'brak powodu'
            ))
            return
        end

        print(('[CFXMAFIA] Czysty gracz: %s | visitorId: %s'):format(
            license,
            tostring(data.visitorId)
        ))
    end)
end)

exports('BanPlayer', banPlayer)