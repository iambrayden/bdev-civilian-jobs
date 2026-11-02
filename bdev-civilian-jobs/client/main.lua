CJ.Current = nil -- the shift you are on: { job, netId, startedAt, earned, tasks, level, deposit }

function CJ.notify(msg, typ, title)
    lib.notify({ title = title or 'Civilian Jobs', description = msg, type = typ or 'inform', duration = 7000 })
end

function CJ.jobs()
    return GlobalState.civjobs or {}
end

function CJ.startJob(jobId)
    local ok, msg = lib.callback.await('bdev-civilian-jobs:start', false, jobId)
    if not ok and msg then CJ.notify(msg, 'error') end
    return ok
end

function CJ.stopJob()
    local job = CJ.Current and CJ.jobs()[CJ.Current.job]
    if job and job.vehicle and CJ.Current.netId then
        local veh = NetworkDoesNetworkIdExist(CJ.Current.netId) and NetToVeh(CJ.Current.netId) or 0
        local atDepot = veh ~= 0 and #(GetEntityCoords(veh) - job.depot.coords.xyz) < 40.0
        if not atDepot then
            local confirm = lib.alertDialog({
                header = 'End shift?',
                content = ('Your %s is not back at the depot, so you will **lose the %s deposit**.'):format(
                    job.vehicle.label, CJ.money(job.vehicle.deposit)),
                centered = true,
                cancel = true,
            })
            if confirm ~= 'confirm' then return false end
        end
    end
    local ok, msg = lib.callback.await('bdev-civilian-jobs:stop', false)
    if not ok and msg then CJ.notify(msg, 'error') end
    return ok
end

RegisterNetEvent('bdev-civilian-jobs:client:started', function(_, session)
    CJ.Current = session
end)

RegisterNetEvent('bdev-civilian-jobs:client:session', function(session)
    if CJ.Current and CJ.Current.job == session.job then CJ.Current = session end
end)

RegisterNetEvent('bdev-civilian-jobs:client:stopped', function()
    CJ.Current = nil
end)

RegisterNetEvent('bdev-civilian-jobs:client:copy', function(text)
    lib.setClipboard(text)
    CJ.notify('Copied to clipboard: ' .. text, 'success')
end)

exports('GetCurrentJob', function() return CJ.Current end)
exports('StartJob', CJ.startJob)
exports('StopJob', CJ.stopJob)
