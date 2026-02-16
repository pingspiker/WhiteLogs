local vector = require("vector")
local ffi = require("ffi")

local hitgroup_names = { "generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "?", "gear" }

local last_shot_data = {
    vector = vector(0, 0, 0),
    damage = nil,
    hgroup = nil,
    bt = nil,
    lc = nil,
    dt = nil,
    tp = nil,
    simtime = nil,
}

local players_shift_data = { }

local gram_create = (function(value, count) local gram = { }; for i=1, count do gram[i] = value; end return gram; end)
local gram_update = (function(tab, value, forced) local new_tab = tab; if forced or new_tab[#new_tab] ~= value then table.insert(new_tab, value); table.remove(new_tab, 1); end; tab = new_tab; end)
local get_average = (function(tab) local elements, sum = 0, 0; for k, v in pairs(tab) do sum = sum + v; elements = elements + 1; end return sum / elements; end)

local GetNetChannelInfo = vtable_bind("engine.dll", "VEngineClient014", 78, "void* (__thiscall*)(void* ecx)")
local GetLatency = vtable_thunk(9, "float(__thiscall*)(void*, int)")

local function clamp(value, min, max)
    if value > max then
        return max;
    end
    if value < min then
        return min;
    end
    return value;
end

local function lerp_time()
    if cvar.cl_interpolate:get_int() > 0 then
        local ratio = cvar.cl_interp_ratio:get_float();

        if cvar.sv_client_max_interp_ratio and cvar.sv_client_min_interp_ratio then
            local min = cvar.sv_client_min_interp_ratio:get_float();
            local max = cvar.sv_client_max_interp_ratio:get_float();

            ratio = clamp(ratio, min, max);
        end

        local update_rate = cvar.cl_updaterate:get_float();

        if cvar.sv_maxupdaterate and cvar.sv_minupdaterate then
            local min = cvar.sv_minupdaterate:get_float();
            local max = cvar.sv_maxupdaterate:get_float();

            update_rate = clamp(update_rate, min, max);
        end

        local interp = cvar.cl_interp:get_float();
        local final_interp = ratio / update_rate;

        return interp > final_interp and interp or final_interp;
    end

    return 0;
end

local function is_tick_valid(simtime)
    local nci = GetNetChannelInfo();

    local correct = GetLatency(nci, 0) + lerp_time();

    local deltatime = correct - (globals.curtime() - simtime);

    if math.abs(deltatime) >= 0.2 then
        return false;
    end

    return true;
end

local function get_entities(enemy_only, alive_only)
    local enemy_only = enemy_only ~= nil and enemy_only or false
    local alive_only = alive_only ~= nil and alive_only or true

    local result = {}

    local me = entity.get_local_player()
    local player_resource = entity.get_player_resource()

    for player = 1, globals.maxplayers() do
        local is_enemy, is_alive = true, true

        if enemy_only and not entity.is_enemy(player) then is_enemy = false end
        if is_enemy then
            if alive_only and entity.get_prop(player_resource, 'm_bAlive', player) ~= 1 then is_alive = false end
            if is_alive then table.insert(result, player) end
        end
    end

    return result
end

client.set_event_callback("net_update_end", function()
    local players = get_entities(true, true)
    for k, player in pairs(players) do
        if (player == nil) then goto skip end

        if players_shift_data[player] == nil then
            players_shift_data[player] = {
                shift = 0,
                old_simtime = 0,
                old_origin = vector(0, 0, 0),
                teleport_data = gram_create(0, 3),
                teleport = 0,
            }
        end
    
        if entity.is_alive(player) and not entity.is_dormant(player) then
            local simtime = entity.get_prop(player, "m_flSimulationTime")
            local origin = vector(entity.get_origin(player))
            if simtime ~= players_shift_data[player].old_simtime then
                players_shift_data[player].shift = ((simtime/globals.tickinterval()) - globals.tickcount())*-1
                players_shift_data[player].old_simtime = simtime
    
                if (players_shift_data[player].old_origin ~= nil) then
                    players_shift_data[player].teleport = (origin-players_shift_data[player].old_origin):length2dsqr()
        
                    gram_update(players_shift_data[player].teleport_data, players_shift_data[player].teleport, true)
                end
    
                players_shift_data[player].old_origin = origin
            end
        end
        ::skip::
    end
end)

client.set_event_callback("aim_fire", function(e)
    local player = e.target

    if players_shift_data[player] == nil then return end

    last_shot_data.vector = vector(e.x, e.y, e.z)
    last_shot_data.damage = e.damage
    last_shot_data.hgroup = e.hitgroup
    last_shot_data.bt = (globals.tickcount() - e.tick)
    last_shot_data.lc = e.teleported
    last_shot_data.dt = (players_shift_data[player].shift >= 1)
    last_shot_data.tp = ((get_average(players_shift_data[player].teleport_data) > 3200) and (players_shift_data[player].shift <= 0)) or ((get_average(players_shift_data[player].teleport_data) > 115) and (players_shift_data[player].shift >= 1))
    last_shot_data.simtime = entity.get_prop(player, "m_flSimulationTime")
end)

client.set_event_callback("aim_miss", function(e)
    local player = e.target

    if player == nil then return end
    if players_shift_data[player] == nil then return end

    local name = entity.get_player_name(player)

    local wanted_damage = last_shot_data.damage
    local wanted_hgroup = hitgroup_names[last_shot_data.hgroup + 1]

    local bt_str = last_shot_data.bt < 0 and "ext="..math.abs(last_shot_data.bt) or "bt="..math.abs(last_shot_data.bt)
    local simtime_not_valid = (is_tick_valid(last_shot_data.simtime) == false) and (last_shot_data.bt > 0)
    local is_lc = last_shot_data.lc
    local is_tp = last_shot_data.tp

    local is_x_discharge = last_shot_data.dt and (players_shift_data[player].shift <= 0) and (get_average(players_shift_data[player].teleport_data) > 100)
    local is_lagcomp_broke = last_shot_data.lc and (get_average(players_shift_data[player].teleport_data) > 100)

    local lc_error = is_x_discharge or is_lagcomp_broke or simtime_not_valid
    local lag_error = is_tp or ((get_average(players_shift_data[player].teleport_data) > 3200) and (players_shift_data[player].shift <= 0)) or ((get_average(players_shift_data[player].teleport_data) > 115) and (players_shift_data[player].shift >= 1))

    local flag_str = lc_error and (is_x_discharge and " flags : (tp)" or (is_lagcomp_broke and " flags : (lc)" or " flags : (bt)")) or (lag_error and ((players_shift_data[player].shift >= 1) and " flags : (dt)" or " flags : (fl)") or "")

    local reason = (lc_error and e.reason == "?") and "lagcompensation error" or ((lag_error and e.reason == "?") and "player lag" or ((e.reason == "?") and "resolver" or e.reason))

    if e.reason == "unregistered shot" then
        client.log("Missed shot due to unregistered shot")
    elseif e.reason == "death" then
        client.log("Missed shot due to death")
    else
        client.log("Missed shot due to "..reason.." at "..name.."'s "..wanted_hgroup.." for "..wanted_damage.." ("..bt_str..")"..flag_str)
    end
end)

client.set_event_callback("aim_hit", function(e)
    local player = e.target

    if player == nil then return end
    if players_shift_data[player] == nil then return end

    local name = entity.get_player_name(player)

    local wanted_damage = last_shot_data.damage
    local wanted_hgroup = hitgroup_names[last_shot_data.hgroup + 1]

    local damage = e.damage
    local hgroup = hitgroup_names[e.hitgroup + 1]

    local bt_str = last_shot_data.bt < 0 and "ext="..math.abs(last_shot_data.bt) or "bt="..math.abs(last_shot_data.bt)
    local is_lc = last_shot_data.lc
    local is_tp = last_shot_data.tp

    local is_x_discharge = last_shot_data.dt and (players_shift_data[player].shift <= 0) and (get_average(players_shift_data[player].teleport_data) > 100)
    local is_lagcomp_broke = last_shot_data.lc and (get_average(players_shift_data[player].teleport_data) > 100)

    local lag_error = is_tp or ((get_average(players_shift_data[player].teleport_data) > 3200) and (players_shift_data[player].shift <= 0)) or ((get_average(players_shift_data[player].teleport_data) > 115) and (players_shift_data[player].shift >= 1))

    local flag_str = is_x_discharge and " flags : (tp)" or (is_lagcomp_broke and " flags : (lc)" or (lag_error and ((players_shift_data[player].shift >= 1) and " flags : (dt)" or " flags : (fl)") or ""))

    if wanted_damage == damage and wanted_hgroup == hgroup then
        client.log("Registered shot at "..name.."'s "..hgroup.." for "..damage.." ("..bt_str..")"..flag_str)
    else
        client.log("Registered shot at "..name.."'s "..hgroup.." for "..damage.." aimed="..wanted_hgroup.."("..wanted_damage..") ("..bt_str..")"..flag_str)
    end
end)