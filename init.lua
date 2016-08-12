
local mobs_redo = false
--if mobs.mod and mobs.mod == "redo" then
--	mobs_redo = true
--end

--
-- Helper functions
--

local function is_group(pos, group)
	local nn = minetest.get_node(pos).name
	return minetest.get_item_group(nn, group) ~= 0
end

local function get_sign(i)
	i = i or 0
	if i == 0 then
		return 0
	else
		return i / math.abs(i)
	end
end

local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return {x = x, y = y, z = z}
end

local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end

local function force_detach(player)
	local attached_to = player:get_attach()
	if attached_to and attached_to:get_luaentity() then
		local entity = attached_to:get_luaentity()
		if entity.driver then
			entity.driver = nil
		end
		player:set_detach()
	end
	default.player_attached[player:get_player_name()] = false
	player:set_eye_offset({x=0, y=0, z=0}, {x=0, y=0, z=0})
end

-------------------------------------------------------------------------------


minetest.register_on_leaveplayer(function(player)
	force_detach(player)
end)

minetest.register_on_shutdown(function()
    local players = minetest.get_connected_players()
	for i = 1,#players do
		force_detach(players[i])
	end
end)

minetest.register_on_dieplayer(function(player)
	force_detach(player)
	return true
end)

-------------------------------------------------------------------------------


lib_mount = {}

local half_a_pie = math.pi/2

function lib_mount.attach(entity, player, attach_at, eye_offset, rotation)
	eye_offset = eye_offset or {x=0, y=0, z=0}
	rotation = rotation or {x=0, y=0, z=0}
	force_detach(player)
	entity.driver = player
	player:set_attach(entity.object, "", attach_at, rotation)
	
	player:set_properties({visual_size = {x=1, y=1}})
	
	player:set_eye_offset(eye_offset, {x=0, y=0, z=0})
	default.player_attached[player:get_player_name()] = true
	minetest.after(0.2, function()
		default.player_set_animation(player, "sit" , 30)
	end)
	player:set_look_yaw(entity.object:getyaw())
end

function lib_mount.detach(player, offset)
	force_detach(player)
	default.player_set_animation(player, "stand" , 30)
	local pos = player:getpos()
	pos = {x = pos.x + offset.x, y = pos.y + 0.2 + offset.y, z = pos.z + offset.z}
	minetest.after(0.1, function()
		player:setpos(pos)
	end)
end

function lib_mount.drive(entity, dtime, moving_anim, stand_anim, jump_height, can_fly)
	if can_fly and can_fly == true then
		jump_height = 0
	end
	
	local acce_y = 0

	local velo = entity.object:getvelocity()
	entity.v = get_v(velo) * get_sign(entity.v)

	-- process controls
	if entity.driver then
		local ctrl = entity.driver:get_player_control()
		if ctrl.up then
			if get_sign(entity.v) >= 0 then
				entity.v = entity.v + entity.accel/10
			else
				entity.v = entity.v + entity.braking/10
			end
		elseif ctrl.down then
			if get_sign(entity.v) < 0 then
				entity.v = entity.v - entity.accel/10
			else
				entity.v = entity.v - entity.braking/10
			end
		end
		if ctrl.aux1 then
			entity.object:setyaw(entity.driver:get_look_yaw() - half_a_pie)
		else
			local yaw = entity.object:getyaw()
			if ctrl.left then
				entity.object:setyaw(entity.object:getyaw()+get_sign(entity.v)*math.rad(1+dtime)*entity.turn_spd)
			elseif ctrl.right then
				entity.object:setyaw(entity.object:getyaw()-get_sign(entity.v)*math.rad(1+dtime)*entity.turn_spd)
			end
		end
		if ctrl.jump then
			if jump_height > 0 and velo.y == 0 then
				velo.y = velo.y + (jump_height * 3) + 1
				acce_y = acce_y + (acce_y * 3) + 1
			end
			if can_fly and can_fly == true then
				velo.y = velo.y + 1
				acce_y = acce_y + 1
			end
		end
	end

	-- animation?
	if entity.v == 0 and velo.x == 0 and velo.y == 0 and velo.z == 0 then
		if stand_anim and stand_anim ~= nil and mobs_redo == true then
			set_animation(entity, stand_anim)
		end
		return
	end
	if moving_anim and moving_anim ~= nil and mobs_redo == true then
		set_animation(entity, moving_anim)
	end
	
	-- Stop!
	local s = get_sign(entity.v)
	entity.v = entity.v - 0.03 * s
	if s ~= get_sign(entity.v) then
		entity.object:setvelocity({x=0, y=0, z=0})
		entity.v = 0
		return
	end

	-- enforce speed limit forward and reverse
	local max_spd = entity.max_spd_r
	if get_sign(entity.v) >= 0 then
		max_spd = entity.max_spd_f
	end
	if math.abs(entity.v) > max_spd then
		entity.v = entity.v - get_sign(entity.v)
	end
	
	-- Set position, velocity and acceleration	
	local p = entity.object:getpos()
	local new_velo = {x=0, y=0, z=0}
	local new_acce = {x=0, y=0, z=0}
	
	local group_check = "crumbly"
	if entity.is_boat then
		group_check = "water"
	end
	
	p.y = p.y - 0.5

	if not is_group(p, group_check) then
		local nodedef = minetest.registered_nodes[minetest.get_node(p).name]
		if (not nodedef) or nodedef.walkable then
			entity.v = 0
			new_acce = {x = 0, y = 1, z = 0}
		else
			new_acce = {x = 0, y = -9.8, z = 0}
		end
		new_velo = get_velocity(entity.v, entity.object:getyaw(), velo.y)
	else
		p.y = p.y + 1
		if is_group(p, group_check) then
			local y = velo.y
			if y >= 5 then
				y = 5
			elseif y < 0 then
				new_acce = {x = 0, y = 20, z = 0}
			else
				new_acce = {x = 0, y = 5, z = 0}
			end
			new_velo = get_velocity(entity.v, entity.object:getyaw(), y)
		else
			new_acce = {x = 0, y = 0, z = 0}
			if math.abs(velo.y) < 1 then
				local pos = entity.object:getpos()
				pos.y = math.floor(pos.y) + 0.5
				new_velo = get_velocity(entity.v, entity.object:getyaw(), 0)
			else
				new_velo = get_velocity(entity.v, entity.object:getyaw(), velo.y)
			end
		end
	end

	new_acce.y = new_acce.y + acce_y
	entity.object:setvelocity(new_velo)
	entity.object:setacceleration(new_acce)
end
