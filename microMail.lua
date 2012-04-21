--[[
	microPost
	
	Planned Features:
	
		Control over sent mail (Edit/Delete until it's been received)
		Mass mailing,
		Subject lines,
		Reference,
		Threads, (in the conversational sense)
		CC & BCC

]]
require "sim"
tMail = {
	[1] = "#Mail", --Nick
	[2] = "",  --Description
	[3] = "", --Email
	[4] = true, -- Operator?
	tConfig = {
		sMailFile = "Index.l-tbl";
	};
}

--{ [1] = {} --[[Sent]], [2] = {} --[[Received]], [3] = "amenay" --[[UserName]] } --Eventual table structure.

sPath = Core.GetPtokaXPath( ) ..  "scripts/data/Mail/"
--[[ sPre creates a formatted pattern readable by string.match in order to detect when PtokaX set prefixes are used. ]]
sPre = "^[" .. ( SetMan.GetString( 29 ):gsub( ( "%p" ), function ( p ) return "%" .. p end ) ) .. "]";
--[[ Less concatenation on the fly if you have the botname ready. ]]
sFromBot = "<" .. tMail[1] .. "> ";
--[[ See next block for an explanation of these three variables ]]
ActualUser, rcv, ins = "", true, true;

do
	--[[ Loading the mailfile, first load text into memory then execute it! tIndex should exist after this, but we don't bother testing that. nope. ]]
	local fMail = loadfile( sPath .. tMail.tConfig.sMailFile );
	if fMail then
		fMail( );
		fMail = nil;
	else
		--[[ The things we do when tIndex does not exist. ]]
		os.execute( "mkdir " .. sPath );
		tIndex = { Inbox = {}, Sent = {} };
	end
end

function OnStartup( )
	--[[ Register bot, load serialize function, and register interactive Lua mode ]]
	Core.RegBot( unpack( tMail ) );
	local f = assert( loadfile( Core.GetPtokaXPath( ) .. "scripts/data/Serialize.lua" ) );
	if f then
		f( );
		f = nil;
	end
	sim.hook_OnStartup( { "#SIM", "PtokaX Lua interface via ToArrival", "", true }, { "amenay", "generic" } );
end
	
function UserConnected( tUser )
	--[[ New mail? Notify user. ]]
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

function ToArrival( tUser, sData )
	local sToUser = sData:match( "^(%S+)", 6 );
	local nInitIndex = #sToUser + 18 + #tUser.sNick * 2;
	sim.hook_ToArrival( tUser, sData, sToUser, nInitIndex );
	if sData:match( sPre, nInitIndex ) then
		local sCmd = sData:match( "^(%w+)", nInitIndex + 1 )
		if sCmd then
			sCmd = sCmd:lower( )
			if tCommandArrivals[ sCmd ] then
				if tCommandArrivals[ sCmd ].Permissions[ tUser.iProfile ] then
					local sMsg;
					if ( nInitIndex + #sCmd ) <= #sData + 2 then sMsg = sData:sub( nInitIndex + #sCmd + 2 ) end
					return ExecuteCommand( tUser, sMsg, sCmd, true );
				else
					return Core.SendPmToUser( tUser, sHBName,  "*** Permission denied.\124" ), true;
				end
			end
		end
	end
end

function OnExit( )
	SaveToFile( sPath .. tMail.tConfig.sMailFile, tIndex, "tIndex", "w+" )
	sim.hook_OnExit()
end

OnError, OpDisconnected = sim.hook_OnError, sim.hook_OpDisconnected;

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

--[[ Gracefully removes a single entry from an array then moves everything up.
]]
function tremove( t, k )
	local tlen = #t;
	t[k] = nil;
	for i = k, tlen, 1 do
		t[i] = t[i+1];
	end
end

function IndexMail( ... ) 
end

tCommandArrivals = {	
	wmail = {
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
	local sRec, nInd = sMsg:match( "^(%S+)%s(%d+)|" );
	nInd = tonumber( nInd );
	if sRec and nInd then
		if tIndex[ sRec ] and tIndex[ sRec ][ nInd ] and ( ( tIndex[ sRec ][ nInd ][ 3 ] == tUser.sNick and tIndex[ sRec ][ nInd ][ 6 ] == false ) or sRec == tUser.sNick ) then
			tremove( tIndex[ sRec ], nInd );
			return true, "Success.", true, tMail[1];
		else
			return true, "You cannot delete this message.\124", true, tMail[1];
		end
	else
		return true, "Syntax error", true, tMail[1];
	end
	--]]
end

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
			if tIndex.Inbox[ sRec ] then
				tIndex.Inbox[ sRec ][ #tIndex.Inbox[ sRec ] + 1 ] = { os.time(), sRec, tUser.sNick, ""--[[placeholder]], sMail, false };
				tIndex.Inbox[ sRec ].nCounter = tIndex.Inbox[ sRec ].nCounter + 1; --Increments to keep track of messages regardless of standing of array.
				return true, "You sent the following message to " .. sRec .. ": " .. sMail;
			else
				tIndex.Inbox[ sRec ] = { { os.time(), sRec, tUser.sNick, ""--[[placeholder]], sMail, false }, nCounter = 1 };
				tIndex.Sent[ tUser.sNick ][ #tIndex.Sent[ tUser.sNick ] ] = tIndex.Inbox[ sRec ][ #tIndex.Inbox[ sRec ] ];
				return true, "You sent the following message to " .. sRec .. ": "  .. sMail;
			end
		else
			return true, "Syntax error, try !wmail recipient message here\124", false, tMail[1];
		end
	end
end

function tCommandArrivals.rmail:Action( tUser, sMsg )
	local sBox, sNick, nIndex = sMsg:match( "^(%S+)%s(%S+}%s(%d+)|" );
	if tIndex[ sBox ][ sNick ] then
		if tIndex[ sBox ][ sNick ][ nIndex ] then
			local tMsg = tIndex[ sBox ][ sNick ][ nIndex ];
			if sBox:lower() == "inbox" then tMsg[6], tIndex.Inbox[ tUser.sNick ].nCounter = true, tIndex.Inbox[ tUser.sNick ].nCounter - 1; end
			return true, "[" .. os.date( "%x - %X", tMsg[1] ) .. "] " .. nIndex .. "# <" .. tMsg[3] .. "> " .. tMsg[5] .. "\n", false, tMail[1];
		else
			return true, "*** Error, " .. sNick .. " does not have that many messages in your " .. sBox, false, tMail[1];
		end
	else
		return true, "Specified box is empty.", true, tMail[1];
	end
end
