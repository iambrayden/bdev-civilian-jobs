--[[
    bdev-civilian-jobs addon library.

    Load it in your job addon's fxmanifest:

        shared_scripts { '@ox_lib/init.lua', '@bdev-civilian-jobs/addon.lua', 'config.lua' }
        dependency 'bdev-civilian-jobs'

    Server:  CivJobs.register(def), CivJobs.onStart / onStop, CivJobs.reward, CivJobs.session,
             CivJobs.vehicle, CivJobs.near, CivJobs.throttle, CivJobs.status, CivJobs.endShift,
             CivJobs.onRequest / onRequestCancelled / onNpcRequest, CivJobs.completeRequest ...
    Client:  CivJobs.onStart / onStop, CivJobs.current, CivJobs.vehicle, CivJobs.minigame,
             CivJobs.carry / dropCarry, CivJobs.blip, CivJobs.notify, CivJobs.onRequest ...

    See docs/ADDONS.md for the full guide.
]]

CivJobs = CivJobs or {}
CivJobs.BASE = 'bdev-civilian-jobs'
local BASE = CivJobs.BASE

if IsDuplicityVersion() then
    ----------------------------------------------------------------------------
    -- SERVER
    ----------------------------------------------------------------------------
    local defs = {}

    local function push(def)
        local ok, err = exports[BASE]:RegisterJob(def)
        if not ok then print(('^1[%s] could not register job "%s": %s^0'):format(GetCurrentResourceName(), tostring(def.id), tostring(err))) end
        return ok
    end

    --- Registers a job with the base. Safe to call at resource start.
    function CivJobs.register(def)
        defs[#defs + 1] = def
        if GetResourceState(BASE) == 'started' then push(def) end
    end

    -- the base (re)started: register again
    AddEventHandler('bdev-civilian-jobs:ready', function()
        for _, def in ipairs(defs) do push(def) end
    end)

    function CivJobs.onStart(jobId, fn)
        AddEventHandler('bdev-civilian-jobs:server:started', function(src, id, session)
            if id == jobId then fn(src, session) end
        end)
    end

    --- fn(src, reason)
    function CivJobs.onStop(jobId, fn)
        AddEventHandler('bdev-civilian-jobs:server:stopped', function(src, id, reason)
            if id == jobId then fn(src, reason) end
        end)
    end

    --- The player's current shift, optionally only if it is `jobId`.
    function CivJobs.session(src, jobId)
        local s = exports[BASE]:GetSession(src)
        if s and (jobId == nil or s.job == jobId) then return s end
    end

    --- Pays the player. opts = { pay, xp, label, task = false }
    function CivJobs.reward(src, jobId, opts)
        return exports[BASE]:Reward(src, jobId, opts)
    end

    function CivJobs.endShift(src, reason)
        return exports[BASE]:EndSession(src, reason)
    end

    --- Short line shown on the player's Gigs "Shift" tab.
    function CivJobs.status(src, text)
        return exports[BASE]:SetShiftStatus(src, text)
    end

    function CivJobs.level(src, jobId)
        return exports[BASE]:GetLevel(src, jobId)
    end

    --- The player's job vehicle entity (or nil).
    function CivJobs.vehicle(src)
        local s = exports[BASE]:GetSession(src)
        if not s or not s.netId then return nil end
        local ent = NetworkGetEntityFromNetworkId(s.netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    end

    function CivJobs.entity(netId)
        if not netId then return nil end
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    end

    function CivJobs.coords(src)
        return GetEntityCoords(GetPlayerPed(src))
    end

    function CivJobs.near(src, coords, dist)
        return #(CivJobs.coords(src) - vec3(coords.x, coords.y, coords.z)) <= dist
    end

    function CivJobs.notify(src, msg, typ, title)
        TriggerClientEvent('ox_lib:notify', src, { title = title, description = msg, type = typ or 'inform', duration = 7000 })
    end

    local throttles = {}
    --- true at most once per `ms` per player + key
    function CivJobs.throttle(src, key, ms)
        local k = src .. ':' .. key
        local now = GetGameTimer()
        if throttles[k] and now - throttles[k] < ms then return false end
        throttles[k] = now
        return true
    end

    -- service requests -----------------------------------------------------
    --- A worker accepted a player's request. fn(workerSrc, request)
    function CivJobs.onRequest(jobId, fn)
        AddEventHandler('bdev-civilian-jobs:server:requestAccepted', function(src, id, req)
            if id == jobId then fn(src, req) end
        end)
    end

    --- The requester cancelled (or left). fn(workerSrc|nil, requestId, request)
    function CivJobs.onRequestCancelled(jobId, fn)
        AddEventHandler('bdev-civilian-jobs:server:requestCancelled', function(src, id, reqId, req)
            if id == jobId then fn(src, reqId, req) end
        end)
    end

    --- Nobody was on duty: send an NPC. fn(request)
    function CivJobs.onNpcRequest(jobId, fn)
        AddEventHandler('bdev-civilian-jobs:server:npcRequest', function(id, req)
            if id == jobId then fn(req) end
        end)
    end

    function CivJobs.getRequest(id) return exports[BASE]:GetRequest(id) end
    function CivJobs.requestWorking(id) return exports[BASE]:SetRequestWorking(id) end
    function CivJobs.completeRequest(id, opts) return exports[BASE]:CompleteRequest(id, opts) end
    function CivJobs.releaseRequest(id, msg) return exports[BASE]:ReleaseRequest(id, msg) end
    function CivJobs.cancelRequest(id, msg) return exports[BASE]:CancelRequest(id, msg) end
    function CivJobs.completeNpcRequest(id, success) return exports[BASE]:CompleteNpcRequest(id, success) end
else
    ----------------------------------------------------------------------------
    -- CLIENT
    ----------------------------------------------------------------------------

    --- fn(session) when this player starts a shift for `jobId`
    function CivJobs.onStart(jobId, fn)
        RegisterNetEvent('bdev-civilian-jobs:client:started', function(id, session)
            if id == jobId then CreateThread(function() fn(session) end) end
        end)
    end

    --- fn(reason)
    function CivJobs.onStop(jobId, fn)
        RegisterNetEvent('bdev-civilian-jobs:client:stopped', function(id, reason)
            if id == jobId then fn(reason) end
        end)
    end

    --- fn(request) when this worker accepted a request
    function CivJobs.onRequest(jobId, fn)
        RegisterNetEvent('bdev-civilian-jobs:client:requestAccepted', function(id, req)
            if id == jobId then CreateThread(function() fn(req) end) end
        end)
    end

    --- fn(requestId) when the request this worker took was cancelled / given back
    function CivJobs.onRequestCancelled(jobId, fn)
        RegisterNetEvent('bdev-civilian-jobs:client:requestCancelled', function(id, reqId)
            if id == jobId then fn(reqId) end
        end)
    end

    function CivJobs.current(jobId)
        local s = exports[BASE]:GetCurrentJob()
        if s and (jobId == nil or s.job == jobId) then return s end
    end

    function CivJobs.vehicle()
        local s = exports[BASE]:GetCurrentJob()
        if s and s.netId and NetworkDoesNetworkIdExist(s.netId) then
            local v = NetToVeh(s.netId)
            if v ~= 0 and DoesEntityExist(v) then return v end
        end
    end

    function CivJobs.notify(msg, typ, title)
        lib.notify({ title = title, description = msg, type = typ or 'inform', duration = 7000 })
    end

    --- Runs a minigame from the base kit. Returns { success, quality, mistakes, cancelled, ... }
    function CivJobs.minigame(name, opts)
        return exports[BASE]:Minigame(name, opts)
    end

    --- Blip with an optional GPS route.
    function CivJobs.blip(coords, label, sprite, color, route)
        local b = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(b, sprite or 1)
        SetBlipColour(b, color or 5)
        SetBlipScale(b, 0.9)
        if route then
            SetBlipRoute(b, true)
            SetBlipRouteColour(b, color or 5)
        end
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(label or 'Job')
        EndTextCommandSetBlipName(b)
        return b
    end

    function CivJobs.removeBlip(b)
        if b and DoesBlipExist(b) then RemoveBlip(b) end
    end

    --- Ground height at x/y (falls back to the given z).
    function CivJobs.groundZ(coords)
        local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
        return found and z or coords.z
    end

    function CivJobs.playAnim(dict, anim, duration, flag)
        local ped = cache.ped
        if not pcall(lib.requestAnimDict, dict, 5000) then return end
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration or -1, flag or 1, 0, false, false, false)
        RemoveAnimDict(dict)
    end

    -- carrying props --------------------------------------------------------
    local carry

    --- Carries a prop in the hands. opts = { dict, anim, bone, offset = vec3, rot = vec3, flag }
    function CivJobs.carry(model, opts)
        CivJobs.dropCarry()
        opts = opts or {}
        local ped = cache.ped
        local ok, hash = pcall(lib.requestModel, model, 5000)
        local obj
        if ok and hash then
            local c = GetEntityCoords(ped)
            obj = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
            SetModelAsNoLongerNeeded(hash)
            local off, rot = opts.offset or vec3(0.0, 0.0, 0.0), opts.rot or vec3(0.0, 0.0, 0.0)
            AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, opts.bone or 57005), off.x, off.y, off.z, rot.x, rot.y, rot.z,
                true, true, false, true, 1, true)
        end
        local state = { obj = obj, model = model, dict = opts.dict, anim = opts.anim, flag = opts.flag or 49 }
        carry = state
        if state.dict and not pcall(lib.requestAnimDict, state.dict, 5000) then state.dict = nil end
        CreateThread(function()
            while carry == state do
                if state.dict and not IsEntityPlayingAnim(cache.ped, state.dict, state.anim, 3) then
                    TaskPlayAnim(cache.ped, state.dict, state.anim, 8.0, -8.0, -1, state.flag, 0, false, false, false)
                end
                DisableControlAction(0, 21, true) -- sprint
                DisableControlAction(0, 22, true) -- jump
                DisableControlAction(0, 23, true) -- enter vehicle
                DisableControlAction(0, 24, true) -- attack
                DisableControlAction(0, 25, true) -- aim
                Wait(0)
            end
        end)
        return obj
    end

    function CivJobs.dropCarry()
        local state = carry
        if not state then return end
        carry = nil
        if state.obj and DoesEntityExist(state.obj) then
            DetachEntity(state.obj, true, true)
            DeleteEntity(state.obj)
        end
        if state.dict then
            StopAnimTask(cache.ped, state.dict, state.anim, 1.0)
            RemoveAnimDict(state.dict)
        end
    end

    function CivJobs.isCarrying(model)
        return carry ~= nil and (model == nil or carry.model == model)
    end

    -- spawning helpers -------------------------------------------------------

    --- A networked mission vehicle parked at the side of the nearest road to `spot`.
    function CivJobs.spawnRoadsideVehicle(model, spot, opts)
        opts = opts or {}
        local found, node, heading = GetClosestVehicleNodeWithHeading(spot.x, spot.y, spot.z, 1, 3.0, 0)
        if not found then node, heading = vec3(spot.x, spot.y, spot.z), spot.w or 0.0 end
        local p = node
        if opts.roadside ~= false then
            local onSide, side = GetPointOnRoadSide(node.x, node.y, node.z, 1)
            if onSide then p = side end
        end
        local ok, hash = pcall(lib.requestModel, model, 10000)
        if not ok or not hash then return nil end
        local v = CreateVehicle(hash, p.x, p.y, p.z + 0.5, heading, true, false)
        local deadline = GetGameTimer() + 3000
        while not NetworkGetEntityIsNetworked(v) and GetGameTimer() < deadline do Wait(0) end
        SetModelAsNoLongerNeeded(hash)
        SetEntityAsMissionEntity(v, true, true)
        SetVehicleOnGroundProperly(v)
        if opts.plate then SetVehicleNumberPlateText(v, opts.plate) end
        if opts.locked then SetVehicleDoorsLocked(v, 2) end
        return v, heading
    end

    --- A networked mission ped that ignores the world around it.
    function CivJobs.spawnPed(model, coords, heading, scenario)
        local ok, hash = pcall(lib.requestModel, model, 10000)
        if not ok or not hash then return nil end
        local p = CreatePed(4, hash, coords.x, coords.y, coords.z, heading or 0.0, true, false)
        SetModelAsNoLongerNeeded(hash)
        SetEntityAsMissionEntity(p, true, true)
        SetBlockingOfNonTemporaryEvents(p, true)
        SetPedFleeAttributes(p, 0, false)
        if scenario then TaskStartScenarioInPlace(p, scenario, 0, true) end
        return p
    end

    function CivJobs.deleteEntity(e)
        if e and DoesEntityExist(e) then
            SetEntityAsMissionEntity(e, true, true)
            DeleteEntity(e)
        end
    end

    --- Lets a ped get into `veh`, drive away and despawn a bit later.
    function CivJobs.driveAway(ped, veh, despawnMs)
        CreateThread(function()
            if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
            if not IsPedInVehicle(ped, veh, false) then
                ClearPedTasks(ped)
                TaskEnterVehicle(ped, veh, 10000, -1, 1.5, 1, 0)
                local deadline = GetGameTimer() + 12000
                while DoesEntityExist(ped) and not IsPedInVehicle(ped, veh, false) and GetGameTimer() < deadline do Wait(250) end
                if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end
                if not IsPedInVehicle(ped, veh, false) then SetPedIntoVehicle(ped, veh, -1) end
            end
            SetVehicleEngineOn(veh, true, true, false)
            TaskVehicleDriveWander(ped, veh, 17.0, 786603)
            SetPedKeepTask(ped, true)
            Wait(despawnMs or 40000)
            CivJobs.deleteEntity(ped)
            CivJobs.deleteEntity(veh)
        end)
    end

    --[[
        NPC visit: an NPC worker drives out, walks up to the target, works, then drives off.
        Used for "nobody is on duty" fallbacks. Runs on the requester's client.

        CivJobs.npcVisit({
            target = entity or vector3,           -- follows the entity if it moves
            vehicle = 'utillitruck3', ped = 's_m_m_autoshop_01',
            label = 'NPC mechanic', sprite = 446, color = 47,
            spawnDistance = 140, driveTimeout = 120, workTime = 20,
            scenario = 'PROP_HUMAN_BUM_BIN',       -- or anim = { dict, clip }
            standAt = function(targetPos, targetEntity) return vector3 end, -- default: in front of it
            onWorkStart = function() return true end, -- false = give up (e.g. a server callback)
            onWorkEnd = function() return true end,
            onFinish = function(success, message) end,
        })  --> handle with :abort()
    ]]
    function CivJobs.npcVisit(opts)
        local job = { aborted = false }
        function job.abort() job.aborted = true end

        local function targetPos()
            if type(opts.target) == 'number' then
                if DoesEntityExist(opts.target) then return GetEntityCoords(opts.target) end
                return nil
            end
            return opts.target
        end

        local function waitFor(cond, ms)
            local deadline = GetGameTimer() + ms
            while not job.aborted and not cond() and GetGameTimer() < deadline do Wait(250) end
            return not job.aborted and cond()
        end

        local function finish(success, msg)
            if job.blip and DoesBlipExist(job.blip) then RemoveBlip(job.blip) end
            lib.hideTextUI()
            if job.aborted then
                CivJobs.deleteEntity(job.ped)
                CivJobs.deleteEntity(job.veh)
            else
                CivJobs.driveAway(job.ped, job.veh, 30000)
            end
            if opts.onFinish then opts.onFinish(success, msg, job.aborted) end
        end

        CreateThread(function()
            local pos = targetPos()
            if not pos then return finish(false, 'The NPC couldn\'t find you.') end
            local dist = opts.spawnDistance or 140.0
            local a = math.random() * math.pi * 2
            local probe = vec4(pos.x + math.cos(a) * dist, pos.y + math.sin(a) * dist, pos.z, 0.0)
            local veh = CivJobs.spawnRoadsideVehicle(opts.vehicle, probe, { roadside = false })
            if not veh then return finish(false, 'The NPC is unavailable.') end
            local okP, pHash = pcall(lib.requestModel, opts.ped, 10000)
            if not okP then
                CivJobs.deleteEntity(veh)
                return finish(false, 'The NPC is unavailable.')
            end
            local driver = CreatePedInsideVehicle(veh, 4, pHash, -1, true, false)
            SetModelAsNoLongerNeeded(pHash)
            SetEntityAsMissionEntity(driver, true, true)
            SetBlockingOfNonTemporaryEvents(driver, true)
            job.veh, job.ped = veh, driver
            if job.aborted then return finish(false) end

            local b = AddBlipForEntity(veh)
            SetBlipSprite(b, opts.sprite or 1)
            SetBlipColour(b, opts.color or 5)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(opts.label or 'NPC')
            EndTextCommandSetBlipName(b)
            job.blip = b
            lib.showTextUI((opts.label or 'NPC') .. ' on the way')

            -- drive over; if it gets stuck, move it to the nearest road
            TaskVehicleDriveToCoordLongrange(driver, veh, pos.x, pos.y, pos.z, 16.0, 786603, 10.0)
            local function close()
                local p = targetPos()
                return p ~= nil and #(GetEntityCoords(veh) - p) < 15.0
            end
            if not waitFor(close, (opts.driveTimeout or 120) * 1000) then
                if job.aborted then return finish(false) end
                local p = targetPos()
                if not p then return finish(false, 'The NPC couldn\'t find you.') end
                local f2, n2, h2 = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 1, 3.0, 0)
                if f2 then
                    SetEntityCoords(veh, n2.x, n2.y, n2.z + 0.5, false, false, false, false)
                    SetEntityHeading(veh, h2)
                end
            end
            if job.aborted then return finish(false) end

            -- park, walk up
            TaskVehicleTempAction(driver, veh, 27, 2000)
            Wait(1500)
            TaskLeaveVehicle(driver, veh, 0)
            waitFor(function() return not IsPedInAnyVehicle(driver, false) end, 6000)
            local p = targetPos()
            if not p then return finish(false, 'The NPC couldn\'t find you.') end
            local stand
            if opts.standAt then
                stand = opts.standAt(p, type(opts.target) == 'number' and opts.target or nil)
            elseif type(opts.target) == 'number' then
                local _, max = GetModelDimensions(GetEntityModel(opts.target))
                stand = GetOffsetFromEntityInWorldCoords(opts.target, 0.0, max.y + 0.9, 0.0)
            else
                stand = p
            end
            TaskGoStraightToCoord(driver, stand.x, stand.y, stand.z, 1.0, 15000, 0.0, 0.5)
            if not waitFor(function() return #(GetEntityCoords(driver) - stand) < 1.5 end, 15000) then
                if job.aborted then return finish(false) end
                SetEntityCoords(driver, stand.x, stand.y, stand.z - 1.0, false, false, false, false)
            end
            if type(opts.target) == 'number' and DoesEntityExist(opts.target) then
                TaskTurnPedToFaceEntity(driver, opts.target, 1000)
            else
                TaskTurnPedToFaceCoord(driver, p.x, p.y, p.z, 1000)
            end
            Wait(1000)

            -- work
            if opts.onWorkStart and not opts.onWorkStart() then return finish(false) end
            if opts.anim then
                if pcall(lib.requestAnimDict, opts.anim.dict, 5000) then
                    TaskPlayAnim(driver, opts.anim.dict, opts.anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
                end
            else
                TaskStartScenarioInPlace(driver, opts.scenario or 'PROP_HUMAN_BUM_BIN', 0, true)
            end
            local endsAt = GetGameTimer() + (opts.workTime or 20) * 1000
            while GetGameTimer() < endsAt and not job.aborted do
                lib.showTextUI(('%s working… %ds'):format(opts.label or 'NPC', math.ceil((endsAt - GetGameTimer()) / 1000)))
                Wait(1000)
            end
            if job.aborted then return finish(false) end
            ClearPedTasks(driver)
            if opts.onWorkEnd and not opts.onWorkEnd() then return finish(false, 'The NPC couldn\'t finish the job.') end
            finish(true)
        end)
        return job
    end

    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() then CivJobs.dropCarry() end
    end)
end
