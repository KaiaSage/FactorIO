require "calls"

local validation = {}
local tickRates = {}
local ramps = {}

maximumTickRate = 9999999

function entityHasPower(entity)
	return entity.electric_buffer_size and entity.electric_buffer_size > 0
end

function isElectricPole(entity)
	return entity.type == "electric-pole"
end

function isLogiChest(entity)
	return entity.type == "logistic-container"
end

function isTank(entity)
	return entity.type == "storage-tank"
end

function isChest(entity)
	return (entity.type == "container" or entity.type == "logistic-container")-- and entity.get_inventory(defines.inventory.chest)
end

function getTickRate(id)
	return tickRates[id]
end

function getRampRate(id)
	return ramps[id]
end

local function testIfEntityIsConnected(id, entity, wire, connection)
	local net = entity.circuit_connected_entities
	local clr = wire == defines.wire_type.red and "red" or "green"
	local data = net[clr]
	if data then
		for _,val in pairs(data) do
			if val == connection then
				return true
			end
		end
	end
	return false
end

local function testIfEntityIsStillConnected(entry)
	return testIfEntityIsConnected(entry.id, entry.entity, entry.wire, entry.connection)
end

local function checkEntityConnections(id, entity, wire)
	local net = entity.circuit_connected_entities
	local clr = wire == defines.wire_type.red and "red" or "green"
	local data = net[clr]
	if data then
		for _,val in pairs(data) do
			local connectValid = validation[id]
			if connectValid and connectValid(val) then
				--game.print("Found " .. val.name)
				return val
			end
		end
	end
end

local function findConnection(id, entity, wire)
	local ret = nil
	if wire ~= defines.wire_type.green then
		--game.print("Checking red connections")
		ret = checkEntityConnections(id, entity, defines.wire_type.red)
	end
	
	if not ret then
		if wire ~= defines.wire_type.red then
			ret = checkEntityConnections(id, entity, defines.wire_type.green)
		end
	end
	
	--game.print("Found a connection? " .. (ret and "yes" or "no"))
	
	return ret
end

local function setValue(entry, val)
	local params = {
		parameters = 
		{
			{
				index = 1,
				signal = {type = "virtual", name = entry.id},
				count = val
			}
		}
	}

	entry.entity.get_control_behavior().parameters = params
end

function tickCombinator(entry, tick)
	--game.print("Ticking " .. entry.id)
	
	if validation[entry.id] then --does it even need a connection?
		if entry.connection then
			if not entry.connection.valid then
				entry.connection = nil
			elseif tick%120 == 0 then
				if not testIfEntityIsStillConnected(entry) then
					entry.connection = nil
				end
			end
		end
	
		if not (entry.connection and entry.connection.valid) and tick%120 == 0 then
			local con, wire = findConnection(entry.id, entry.entity, entry.wire)
			entry.connection = con
			entry.wire = wire
		end
		
		if not (entry.connection and entry.connection.valid) then
			--game.print("No connection for " .. entry.id)
			setValue(entry, 0)
			return
		end
	end
	
	if not entry.data then entry.data = {} end
	
	local val = runCallback(entry.id, entry.entity, entry.data, entry.connection)
	
	if not val then val = 0 end
	
	if val > 2^31-1 then
		game.print("Sensor " .. entry.id .. " outputted a value of " .. val .. ", far more than is plausible or displayable!")
		val = 2^31-1
	elseif val < -(2^31-1) then
		game.print("Sensor " .. entry.id .. " outputted a value of " .. val .. ", far less than is plausible or displayable!")
		val = -(2^31-1)
	end
	
	val = math.floor(val+0.5)
	
	if entry.ramp_rate then
		--local old = entry.tick_rate
		if val > 0 then
			entry.tick_rate = math.max(entry.tick_rate - maximumTickRate, entry.base_tick_rate)
		else
			entry.tick_rate = math.min(entry.tick_rate + maximumTickRate, entry.ramp_rate)
		end
		--game.print("Ramped " .. entry.id .. " tick rate from " .. old .. " to " .. entry.tick_rate)
	end
	
	setValue(entry, val)
end

function addCombinator(variant, callFunc, validFunc, tickRate, rampedTickRate)
	registerCall(variant, callFunc)
	validation[variant] = validFunc
	tickRates[variant] = tickRate
	maximumTickRate = math.min(maximumTickRate, tickRate)
	if rampedTickRate then
		ramps[variant] = rampedTickRate
	end
	
	if data and data.raw and not game then
		local name = "combinator-" .. variant
		local ico = "__FactorIO__/graphics/icons/" .. variant .. ".png"
		local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
		entity.name = name
		entity.minable.result = name
		entity.icons = {
			{icon = entity.icon}, {icon = ico}
		}
		entity.localised_name = {"basic-combinator-name.name", {"signal-type." .. variant}}
		entity.energy_source = {type = "electric", usage_priority = "secondary-input"}
		entity.active_energy_usage = "4KW"
		local item = table.deepcopy(data.raw.item["constant-combinator"])
		item.name = name
		item.icons = entity.icons
		item.place_result = name
		item.localised_name = entity.localised_name
		local recipe = table.deepcopy(data.raw.recipe["constant-combinator"])
		recipe.name = name
		recipe.result = name
		table.insert(recipe.ingredients, {"advanced-circuit", 1})
		
		local signal = {
			type = "virtual-signal",
			name = variant,
			icon = ico,
			icon_size = 32,
			subgroup = "virtual-signal-special",
			order = variant,
			localised_name = {"signal-type." .. variant},
		}
		
		data:extend({entity, item, recipe, signal})
		
		table.insert(data.raw.technology["more-signals"].effects, {type = "unlock-recipe", recipe = name})
	end
end