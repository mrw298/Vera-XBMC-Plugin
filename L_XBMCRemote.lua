module("L_XBMCRemote", package.seeall)
_VERSION = "0.0.2"
_COPYRIGHT = ""

local dkjson = require("L_XBMCRemote_dkjson")
local socket = require("socket")


local ipAddress
local json_http_port
local json_tcp_port
local ping_interval
local serviceid = "urn:upnp-org:serviceId:XBMC1"
local deviceid
	
local DEBUG_MODE = true

local DEFAULT_XBMC_TCP_PORT = 9090
local DEFAULT_XBMC_HTTP_PORT = 80
local DEFAULT_PING_TIME = 18
local DEFAULT_UPDATE_IDLE_TIME = 15

local SOON = 5

local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

local XBMC_PLAYSTATE_ONPLAY = "OnPlay"
local XBMC_PLAYSTATE_ONSTOP = "OnStop"
local XBMC_PLAYSTATE_UNKNOWN = "--"


local function log(stuff, level)
	luup.log("XBMC: " .. stuff, (level or 50))
end

local function debug(stuff)
	if (DEBUG_MODE) then
		log("debug " .. stuff, 1)
	end
end

-- From the NEST plugin
local function task(text, mode)
  local mode = mode or TASK_ERROR
  if (mode ~= TASK_SUCCESS) then
	log("task: " .. text, 50)
  end
  taskHandle = luup.task(text, (mode == TASK_ERROR_PERM) and TASK_ERROR or mode, MSG_CLASS, taskHandle)
end

-- From the NEST plugin
local function readVariableOrInit(lul_device, serviceId, name, defaultValue) 
  local var = luup.variable_get(serviceId, name, lul_device)
  if (var == nil) then
	var = defaultValue
	luup.variable_set(serviceId, name, var, lul_device)
	log("Initialized variable: '" .. name .. "' = '" .. var .. "' SID is " .. serviceId )
  end
  return var
end

-- From the NEST plugin
local function writeVariable(lul_device, serviceId, name, value) 
  luup.variable_set(serviceId, name, value, lul_device)
end

-- Originally from the NEST plugin
local function writeVariableIfChanged(lul_device, serviceId, name, value)
  local curValue = luup.variable_get(serviceId, name, lul_device)
  
  -- convert to strings as numeric comparison of floats was hit
  -- and miss to say the least
  
  if (tostring(value) ~= tostring(curValue)) then
	writeVariable(lul_device, serviceId, name, value)
	log("Changed variable: '" .. name .. "' = '" .. value .. "' SID is " .. serviceId )
	return true
  else
	return false
  end
end

-- From http://lua-users.org/wiki/StringRecipes
function string.starts(String,Start)
	return string.sub(String,1,string.len(Start))==Start
end

function string.ends(String,End)
	return End=='' or string.sub(String,-string.len(End))==End
end

local function icmp_ping(address)
  local returnCode = os.execute("ping -c 1 " .. address)

  if (returnCode == 0) then
	-- everything is fine, we reached the host
	return true
  else
	return false
  end
end

-- Logic starts

function xbmc_json_call( meth, para, msg_id )
	--local cmd = '{"jsonrpc": "2.0", "method": "" .. meth .. "", "params": {" .. para .. "}, "id": 1}'
	
	if ( meth == nil ) then
		debug( "call to xbmc_json_call with nil method, ignore it")
		return false
	end
	
	local request = {
						jsonrpc = "2.0";
						id = msg_id or meth;
					}
					
	request.method = meth
	if (para ~= nil) and (type(para) == "table") then request.params = para end
	
	local cmd = json.encode(request)
	
	debug( "xbmc_json_call with: " .. cmd )
	
	return sendCommand(cmd)		
end

function XBMCall (action)
	local method = ""
	local params = nil
	
	debug( "XBMCall: " .. action )

	--PING
	if (action == "ping" ) then
		method = "JSONRPC.Ping"
	
	--LEFT
	elseif(action == "left") then
		method = "Input.Left"	
	
	--RIGHT
	elseif (action == "right") then
		method = "Input.Right"

	--UP
	elseif (action == "up") then
		method = "Input.Up"

	--DOWN
	elseif (action == "down") then
		method = "Input.Down"
	
	--BACK
	elseif (action == "back") then
		method = "Input.Back"		

	--HOME
	elseif (action == "home") then
		method = "Input.Home"
	
	--ENTER
	elseif (action == "enter") then
		method = "Input.Select"

	--PLAY / PAUSE
	elseif (action == "playpause") then
		method = "Player.PlayPause"
		params = {
			playerid = "1";
		}

	--STOP
	elseif (action == "stop") then
		method = "Player.Stop"
		params = {
			playerid = "1";
		}

	--MUTE
	elseif (action == "mute") then
		method = "Application.SetMute"
		params = {
			mute = "toggle";
		}
	
	--REBOOT
	elseif (action == "reboot") then
		method = "System.Reboot"
	
	--SUSPEND
	elseif (action == "suspend") then
		method = "System.Suspend"
	
	--SHUTDOWN
	elseif (action == "shutdown") then
		method = "System.Shutdown"
	
	--AUDIO LIBRARY UPDATE
	elseif (action == "audioupdate") then
		method = "AudioLibrary.Scan"
	
	--AUDIO LIBRARY CLEAN
	elseif (action == "audioclean") then
		method = "AudioLibrary.Clean"
	
	--VIDEO LIBRARY SCAN
	elseif (action == "videoupdate") then
		method = "VideoLibrary.Scan"
	
	--VIDEO LIBRARY CLEAN
	elseif (action == "videoclean") then
		method = "VideoLibrary.Clean"
	
	--NEXT
	elseif (action == "next") then
		method = "Player.GoNext"
		params = {
			playerid = "1";
		}
	
	--PREVIOUS
	elseif (action == "prev") then
		method = "Player.GoPrevious"
		params = {
			playerid = "1";
		}
	
	--FASTER
	elseif (action == "faster") then
		method = "Player.SetSpeed"
		params = {
			playerid = "1";
			speed = "increment";
		}
	
	--SLOWER
	elseif (action == "slower") then
		method = "Player.SetSpeed"
		params = {
			playerid = "1";
			speed = "decrement";
		}		
	
	--VOLUME UP
	elseif (action == "vup") then
		method = "Application.SetVolume"
		params = {
			volume = "100";
		}
	
	--VOLUME DOWN
	elseif (action == "vdown") then
		method = "Application.SetVolume"
		params = {
			volume = "0";
		}
	
	--ERROR
	else
		debug("XBMCall Command not found! action: " .. action)		
	end

	local dbg_str = ""
	if (action ~= nil) then dbg_str = dbg_str .. "action: " .. action end
	if (method ~= nil) then dbg_str = dbg_str .. " method: " .. method end
	if (params ~= nil) then dbg_str = dbg_str .. " params: " .. table.concat(params) end		
	debug( dbg_str )
	
	--curlcall (method, params)
	return xbmc_json_call( method, params )
end


function sendCommand(command)
	debug( "in sendCommand" )
	local result = luup.io.write(command)
	if (result == nil) or (result == false) then
		log("Cannot send command " .. command .. " communications error")
--			luup.set_failure(true)
		return false
	end
	debug( "sendCommand = success" )
	return true
end

local function nextchar(result)
	return coroutine.yield(result)
end

local function JSONRPC_Process_Coroutine(ch)
	while true do
		local result
		if ( '{' == ch ) then
				local open_braces_found = 1
				result = ch
				while true do
					next_ch = nextchar()

					result = result .. next_ch

					if (next_ch == "{") then open_braces_found = open_braces_found + 1 end
					if (next_ch == "}") then open_braces_found = open_braces_found - 1 end

					if ( open_braces_found <= 0 ) then break end

				end
		end

		--if ( result ~= nil) then debug( "result: " .. result ) end
		ch = nextchar(result)
	end
end

local JSONRPC_Process = coroutine.wrap(JSONRPC_Process_Coroutine)

function xbmc_ping()
	
	--local ping_cmd ="{\"jsonrpc\": \"2.0\", \"method\": \"JSONRPC.Ping\", \"id\": 1}"		
	--local result = sendCommand(ping_cmd)
	
	local result = XBMCall( "ping" )
	
	return result
end

function xbmc_getActivePlayers()
	method = "Player.GetActivePlayers"
	
	return xbmc_json_call( method )		
end

function xbmc_getWhatsOnPlayer( player_id )

	local method = "Player.GetItem"
	local params = {
		properties = { "title" };
		playerid = player_id;
	}
	
	-- buffer any new data
	xbmc_json_call( method, params, "XBMCRemote.GetWhatsPlaying" )				
end

function getStopTime()
	return luup.variable_get(serviceid, "StopTime", deviceid)
end

function setStopTime(stop_time)
	return writeVariableIfChanged(deviceid, serviceid, "StopTime", stop_time)
end

function getPlayerStatus()
	return luup.variable_get(serviceid, "PlayerStatus", deviceid)
end

function setPlayerStatus(status)

	local current_StopTime = getStopTime()

	if ((status == XBMC_PLAYSTATE_ONSTOP) or (status == "OnEnded")) and (current_StopTime == "--") then
		setStopTime( socket.gettime() )
	elseif (status == XBMC_PLAYSTATE_ONPLAY) or (status == XBMC_PLAYSTATE_UNKNOWN) then
		setStopTime( "--" )
		set_idle_time( "--" )
	end

	return writeVariableIfChanged(deviceid, serviceid, "PlayerStatus", status)
end

-- regular ping
function scheduled_ping_ok()
	writeVariableIfChanged(deviceid, serviceid, "PingStatus", "up")
end

function scheduled_ping_fail(msg)

	local status_msg = msg or "down"

	writeVariableIfChanged(deviceid, serviceid, "PingStatus", status_msg)
	setPlayerStatus(XBMC_PLAYSTATE_UNKNOWN)
	set_idle_time("--")
end

function set_idle_time(idle_time)
	return writeVariableIfChanged(deviceid, serviceid, "IdleTime", idle_time)
end

function get_idle_time()
	return luup.variable_get(serviceid, "IdleTime", deviceid)
end

function update_idle_time()
	local idle_time = "--"
	local stop_time = getStopTime()
	
--	debug( "in update_idle_time - stop_time: " .. (stop_time or "nil") )
	
	if (stop_time ~= nil) and (tostring(stop_time) ~= "--") then
		idle_time = socket.gettime() - stop_time
		set_idle_time(idle_time)
	else
		set_idle_time("--")
	end
	
	-- call update_idle_time again
	luup.call_timer("update_idle_time", 1, DEFAULT_UPDATE_IDLE_TIME, "", "")
end

function scheduled_ping()
	log("sending routine ping")

	-- do an icmp ping and if it fails don't attempt the rest of the connection
	local ping = icmp_ping( ipAddress )
	if ( ping == false ) then
		debug("icmp ping failed")
		
		scheduled_ping_fail()
		
		-- just reschedule the ping
		luup.call_timer("scheduled_ping", 1, ping_interval, "", "")
		return false
	end

	
	-- check whether we're still connected
	if (luup.io.is_connected(deviceid) == false) then
		scheduled_ping_fail("down - no JSON")
	
		log( "io.is_connected is false - No longer connected in scheduled ping, attempt to reconnect")
		xbmc_connect()

		-- if we can ping, no JSON we might be waiting for XBMC to start lets try to connect again shortly
		luup.call_timer("scheduled_ping", 1, SOON, "", "")
		return false			
	end
			
	-- this really only checks we can send to a port
	local result = xbmc_getActivePlayers()
	if (result == true) then
		scheduled_ping_ok()
		debug("XBMCRemote is UP!")
	else
		scheduled_ping_fail()
		debug("XBMCRemote is DOWN!")
	end
	
	luup.call_timer("scheduled_ping", 1, ping_interval, "", "")
end

local function XBMC_processNotification( method, params)
	debug( "XBMC_processNotification: " .. method )

	if (string.starts(method, "Player.")) then
		-- Player states
		local state = string.sub(method,-(string.len(method)-7))
		debug( "Player state is: " .. state )
		
		setPlayerStatus( state )
		
		if (state == XBMC_PLAYSTATE_ONPLAY ) then 
			-- in here send a request for more information on what's playing
			-- then process it in the event handler
		
			if ( params.data ~= nil ) and ( params.data.player ~= nil ) then
				local player = params.data.player
				xbmc_getWhatsOnPlayer( player.playerid)
			end
					
		elseif ( state == XBMC_PLAYSTATE_ONSTOP) then
			-- dont think this is correct
--			setPlayerStatus("--")
		end
	end
	
end

local function XBMC_IncomingMessage_XBMCRemote_GetWhatsPlaying(oMsg)
	if (oMsg.result ~= nil) and (oMsg.result.item ~= nil) then		
		local item = oMsg.result.item
		
		if ( item.type ~= nil) and (item.title ~= nil) then
			local playing = item.type .. ": " .. item.title
			writeVariableIfChanged(deviceid, serviceid, "CurrentPlaying", playing )
		end
	end
end

local function XBMC_IncomingMessage_Player_GetActivePlayers(oMsg)
	if (oMsg.result ~= nil) then
		-- if the results variable is present but empty then nothing is playing
		if (next(oMsg.result) == nil) then
			debug( "nothing playing in GetActivePlayers")
			setPlayerStatus(XBMC_PLAYSTATE_ONSTOP)
		elseif (oMsg.result[1].playerid ~= nil) then
			debug("found an active player")
			setPlayerStatus(XBMC_PLAYSTATE_ONPLAY)
		else
			debug( "unknown response to the GetActivePlayers request")
		end
	end
end

XBMC_INCOMING_MESSAGE_HANDLERS = { 
	XBMCRemote_GetWhatsPlaying 	= XBMC_IncomingMessage_XBMCRemote_GetWhatsPlaying;
	Player_GetActivePlayers	 	= XBMC_IncomingMessage_Player_GetActivePlayers;
}


local function XBMC_processIncomingMessage(msg)
	debug( "XBMC_processIncomingMessage: " .. msg )
	
	-- if we got a notification we must be up, so log the device as up
	scheduled_ping_ok()
	
	local oMsg = json.decode(msg)
	
	if ((oMsg == nil) or (type(oMsg) ~= "table")) then 
		debug( "Couldn't decode returned message" )
		return false 
	end
	
	
	if( oMsg.id == nil) and (oMsg.method ~= nil) then
		debug( "found a notification" )
		XBMC_processNotification( oMsg.method, oMsg.params )
	elseif( oMsg.id ~= nil) then
		-- convert the inbound id to our lookup table format
		local idLookup = string.gsub(oMsg.id, "%.", "_")
		debug( "Parsed incoming message id " .. idLookup)
		if ( XBMC_INCOMING_MESSAGE_HANDLERS[idLookup] ~= nil) then
			-- here we use a reference table to hold handlers that know how to process incoming messages
			-- retrieve the reference to the function in the reference table
			-- then execute it
			local f = XBMC_INCOMING_MESSAGE_HANDLERS[idLookup]		
			f(oMsg)
		else
			debug( "unhandled message type" )
		end
	else
		-- shouldn't really get here
		debug( "got a responce in XBMC_processIncomingMessage I didn't know what to do with")
	end
end


	-- processed byte by byte
function processIncoming(s)
	if (luup.is_ready(deviceid) == false) then
		return
	end

	local msg = JSONRPC_Process( s )

	if ( msg ~= nil ) then			
		XBMC_processIncomingMessage(msg)
	end
end

function xbmc_connect()
	log("Connecting to XBMC host on: " .. ipAddress .. ":" .. json_tcp_port )
	luup.io.open(deviceid, ipAddress, json_tcp_port)
	
	if (luup.io.is_connected(deviceid) == false) then
		log("Cannot connect. Confirm the IP address is correct, will attempt to reconnect in scheduled ping.")
		-- task( "couldn't connect", TASK_ERROR )
	else
		log("connected to XBMC succesfully")
	end
end


function init(lul_device)
		deviceid = lul_device
		ipAddress = luup.devices[deviceid].ip
		
		json_tcp_port = readVariableOrInit(deviceid, serviceid, "XBMC_TCP_port", DEFAULT_XBMC_TCP_PORT)
		json_http_port = readVariableOrInit(deviceid, serviceid, "XBMC_HTTP_port", DEFAULT_XBMC_HTTP_PORT)		
		ping_interval = readVariableOrInit(deviceid, serviceid, "PingInterval", DEFAULT_PING_TIME)

		log("starting device: " .. tostring(deviceid))

		
		if (ipAddress == nil or ipAddress == "") then
			return false, "IP Address is required in Device's Advanced Settings!", "XBMCRemote"
		else
			local PingStatus1 = readVariableOrInit( deviceid, serviceid, "PingStatus", "--")
			local IdleTime1 = readVariableOrInit( deviceid, serviceid, "IdleTime", "--")
			local StopTime1 = readVariableOrInit( deviceid, serviceid, "StopTime", "--")
			local PlayerStatus1 = readVariableOrInit( deviceid, serviceid, "PlayerStatus", "--")
			local CurrentPlaying = readVariableOrInit( deviceid, serviceid, "CurrentPlaying", "--")
		end
		
		if (ipAddress == "") or (json_tcp_port == "") then
			return false,'No IP and JSON port supplied, please enter the IP/port to connect to.','XBMC'
		end
		
		-- at startup do the first ping nearly immediately without waiting for the usual interval
		-- so that the connection is established
		log( "ping scheduled in " .. SOON .. " seconds" )
		luup.call_timer("scheduled_ping", 1, SOON, "", "")
		
		log("update idle time scheduled every " .. DEFAULT_UPDATE_IDLE_TIME .. " seconds" )
		luup.call_timer("update_idle_time", 1, DEFAULT_UPDATE_IDLE_TIME, "", "")
		
		log("startup complete: " .. tostring(deviceid))
		
		return true,'ok','XBMC'
end
