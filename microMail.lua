--[[
	microPost
	
	Planned Features:
	
		Control over sent mail (Edit/Delete until it's been received)
		Mass mailing,
		Subject lines,
		Reference,
		Threads, (in the conversational sense)
		CC & BCC
		
		Short term todo:
			
			Command list that dynamically generates a listing of available commands based off profile permissions.
]]
require "sim"
tMail = {
	[1] = "#Mail", --Nick
	[2] = "",  --Description
	[3] = "", --Email
	[4] = true, -- Operator?
	tConfig = {
		nInboxSize = 40,
		nOutboxSize = 40,
		sMailFile = "Index.l-tbl";
	};
}

--{ [1] = {} --[[Sent]], [2] = {} --[[Received]], [3] = "amenay" --[[UserName]] } 

sPath = Core.GetPtokaXPath( ) ..  "scripts/data/Mail/"
sPre = "^[" .. ( SetMan.GetString( 29 ):gsub( ( "%p" ), function ( p ) return "%" .. p end ) ) .. "]";
sFromBot = "<" .. tMail[1] .. "> ";

function OnStartup( )
	Core.RegBot( unpack( tMail ) );
	local f = assert( loadfile( Core.GetPtokaXPath( ) .. "scripts/data/Serialize.lua" ) );
	if f then
		f( );
		f = nil;
	end
	local fMail = loadfile( sPath .. tMail.tConfig.sMailFile );
	if fMail then
		fMail( );
		fMail = nil;
	else
		os.execute( "mkdir " .. sPath );
		tIndex = { };
	end
	sim.hook_OnStartup( { "#SIM", "PtokaX Lua interface via ToArrival", "", true }, { "amenay", "Namebrand" } );
end
	
function UserConnected( tUser )
	if tIndex and tIndex[ tUser.sNick ] and tIndex[ tUser.sNick ].nCounter > 0 then
		Core.SendPmToUser( tUser, tMail[1], "You have " .. tIndex[ tUser.sNick ].nCounter .. " new messages in your inbox. Type !rmail to read.\124" );
	end
end

OpConnected, RegConnected = UserConnected, UserConnected;

function ChatArrival( tUser, sData )
	local nInitIndex = #tUser.sNick + 4;
	if sData:match( sPre, nInitIndex ) then
		local sCmd = sData:match( "^(%w+)", nInitIndex + 1 );
		if sCmd then
			sCmd = sCmd:lower( );
			if tCommandArrivals[ sCmd ] then
				local sMsg;
				if nInitIndex + #sCmd <= #sData + 1 then sMsg = sData:sub( nInitIndex + #sCmd + 2 ) end;
				return ExecuteCommand( tUser, sMsg, sCmd );
			else
				return false;
			end
		end
	end
end			

function OnExit( )
	SaveToFile( sPath .. tMail.tConfig.sMailFile, tIndex, "tIndex", "w+" )
	sim.hook_OnExit()
end

OnError, OpDisconnected, ToArrival = sim.hook_OnError, sim.hook_OpDisconnected, sim.hook_ToArrival;

function ExecuteCommand( tUser, sMsg, sCmd, bInPM )
	if tCommandArrivals[ sCmd ].Permissions[ tUser.iProfile ] then
		local bRet, sRetMsg, bInPM, sFrom = tCommandArrivals[ sCmd ]:Action( tUser, sMsg );
		if sRetMsg then
			if bInPM then
				if sFrom then
					return Core.SendPmToUser( tUser, sFrom, sRetMsg ), true;
				else
					return Core.SendPmToUser( tUser, sFromBot, sRetMsg ), true;
				end
			else
				if sFrom then
					return Core.SendToUser( tUser, "<" .. sFrom .. "> " .. sRetMsg ), true;
				else
					return Core.SendToUser( tUser, sFromBot .. sRetMsg ), true;
				end
			end
		else
			return bRet;
		end
	else
		return Core.SendToUser( tUser, sFromBot ..  "*** Permission denied.|" ), true;
	end
end


function IndexMail( ... ) 
end

tCommandArrivals = {	wmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Recipient> <Message> - Sends message to recipient of your choice.\n";
	},
	rmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " - PM's all messages sent to you from all users.\n";
	},
	mailstatus = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Recipient> - PM's you unread messages sent to recipient by yourself.\n";
	},
	mhelp = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " - PMs this message to you. (sort order of help is dynamic and may change at any time)\n";
	},
	dmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Recipient> <Index> - Deletes message number (as displayed when checking mail status)\n";
	},
}

function tCommandArrivals.mhelp:Action( tUser )
	local sRet = "\n\n**-*-** " .. ScriptMan.GetScript().sName .."  help (use one of these prefixes: " .. SetMan.GetString( 29 ) .. " **-*-**\n\n";
	for name, obj in pairs( tCommandArrivals ) do
	sim.print( name, obj )
		if obj.Permissions[ tUser.iProfile ] then
			sRet = sRet .. name .. obj.sHelp;
		end
	end
	return true, sRet, true, tMail[1];
end

function tCommandArrivals.dmail:Action( tUser, sMsg )
	--return true, "This command has not been implemented yet";
	---[[ parse message, get username, get indice. use table.remove to remove. Send updated mailstatus to tUser.
	local sRec, nInd = sMsg:match( "^(%S+)%s(%d+)|" );
	if sRec and nInd then
		if tIndex[ sRec ] and tIndex[ sRec ][ nInd ] then
			table.remove( tIndex[ sRec ], nInd );
			return ( tCommandArrivals.mailstatus:Action( tUser, sMsg ) ), "Success", true, tMail[1];
		end
	else
		return true, "Syntax error", true, tMail[1];
	end
	--]]
end
	

--[[

tIndex = {

	amenay = {
		sent = { 
			[1] = { time, to, from, subject, msg, read},
			
		},
		recieved = {
			[1] = { time, to, from, subject, msg, read },
		},	
	},
}

Problem is we want sent messages to point towards user's recieved messages for the sake of memory savings. But once serialized and reloaded the table will contain two unique entries for the same
message (sent and received) I need to find a way to prevent it from serializing the references to the received messages, and just let it dynamically rebuild the received table with the unread
 entries.... perhaps a special version of serialize that tests the read condition while traversing the received table?


]]

function tCommandArrivals.mailstatus:Action( tUser, sMsg )
	local sRec = sMsg:match( "^(%S+)" )
	local sRet = sRec and sRec .. " has not read the following messages:\n\n" or "The following messages are still unread:\n\n";
	if sRec then
		for i,v in ipairs( tIndex[ sRec ] ) do
			if v[ 3 ] == tUser.sNick then
				if not v[ 6 ] then 
					sRet = sRet .. "[" .. os.date( "%x - %X", v[1] ) .. "] <" .. v[3] .. "> " .. v[5] .. "\n";
				end
			end
		end
		return true, sRet, true, tMail[1];
	else
		return true, "Syntax error, please specify a user\124", false, tMail[1];
	end
end

function tCommandArrivals.wmail:Action( tUser, sMsg )
	if sMsg then
		local sRec, sMail = sMsg:match( "^(%S+)%s(.*)|" )
		if sRec and sMail then
			--Check if tUser has a mailbox
			if tIndex[ sRec ] then
				tIndex[ sRec ][ #tIndex[ sRec ] + 1 ] = { os.time(), sRec, tUser.sNick, ""--[[placeholder]], sMail, false };
				tIndex[ sRec ].nCounter = tIndex[ sRec ].nCounter + 1; --Increments to keep track of messages regardless of standing of array.
				return true, "You sent the following message to " .. sRec .. ": " .. sMail;
			else
				tIndex[ sRec ] = { { os.time(), sRec, tUser.sNick, ""--[[placeholder]], sMail, false }, nCounter = 1 };
				return true, "You sent the following message to " .. sRec .. ": "  .. sMail;
			end
		else
			return true, "Syntax error, try !rmail recipient message here\124", false, tMail[1];
		end
	end
end

function tCommandArrivals.rmail:Action( tUser )
	if tIndex[ tUser.sNick ] then
		local sMsg = "\n\n";
		for i, v in ipairs( tIndex[ tUser.sNick ] ) do
			sMsg = sMsg .. "[" .. os.date( "%x - %X", v[1] ) .. "] <" .. v[3] .. "> " .. v[5] .. "\n";
			tIndex[ tUser.sNick ].nCounter = v[6] and tIndex[ tUser.sNick ].nCounter or tIndex[ tUser.sNick ].nCounter - 1;
			v[6] = v[6] or true;
		end
		return true, sMsg, true, tMail[1];
	else
		return true, "You have no messages at this time", true, tMail[1];
	end
end
