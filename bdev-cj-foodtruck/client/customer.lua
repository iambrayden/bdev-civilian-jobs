-- Every player: walk up to an open food truck and order.

local MODEL = Config.Job.vehicle.model

local function order(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    local ok, data = lib.callback.await('bdev-cj-foodtruck:menu', false, netId)
    if not ok then return CivJobs.notify('This truck isn\'t serving right now.', 'error') end
    local fields = {}
    for _, m in ipairs(data.menu) do
        fields[#fields + 1] = { type = 'number', label = ('%s ($%d)'):format(m.label, m.price), default = 0, min = 0, max = 5 }
    end
    local input = lib.inputDialog(('%s\'s food truck'):format(data.vendor), fields)
    if not input then return end
    local cart = {}
    for i, m in ipairs(data.menu) do
        local n = tonumber(input[i]) or 0
        if n > 0 then cart[m.id] = n end
    end
    if next(cart) == nil then return end
    local done, res = lib.callback.await('bdev-cj-foodtruck:buy', false, netId, cart)
    if done then
        CivJobs.notify(('Order placed: $%d. Wait at the window while they cook it.'):format(res), 'success', 'Food truck')
    else
        CivJobs.notify(res or 'Couldn\'t place that order.', 'error', 'Food truck')
    end
end

exports.ox_target:addModel(MODEL, {
    {
        name = 'ft_buy', icon = 'fa-solid fa-utensils', label = 'Order food', distance = 3.0,
        canInteract = function(entity)
            local st = Entity(entity).state.foodtruck
            return st ~= nil and st.open == true and st.owner ~= cache.serverId
        end,
        onSelect = function(data) order(data.entity) end,
    },
})

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then exports.ox_target:removeModel(MODEL, 'ft_buy') end
end)
