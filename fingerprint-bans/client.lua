AddEventHandler('esx:playerLoaded', function()
    SendNUIMessage({ action = 'run' })
end)

RegisterNUICallback('deviceIds', function(data, cb)
    local ids = data.ids or {}
    if #ids > 0 then
        TriggerServerEvent('cfxmafia:deviceIds', ids)
    end
    cb('1337')
end)