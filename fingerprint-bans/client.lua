local KVP_KEY = 'cfxmafia_fingerprint_uid'

local function getOrCreateKvpId()
    local existing = GetResourceKvpString(KVP_KEY)
    if existing and existing ~= '' then
        return existing
    end

    -- Generate new UUID
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    local uuid = string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)

    SetResourceKvp(KVP_KEY, uuid)
    return uuid
end

AddEventHandler('esx:playerLoaded', function()
    SendNUIMessage({ action = 'run' })
end)

RegisterNUICallback('deviceIds', function(data, cb)
    local ids            = data.ids or {}
    local localStorageId = data.localStorageId or nil
    local kvpId          = getOrCreateKvpId()

    if #ids > 0 or localStorageId or kvpId then
        TriggerServerEvent('cfxmafia:deviceIds', {
            devices        = ids,
            localStorageId = localStorageId,
            kvpId          = kvpId
        })
    end

    cb('1337')
end)