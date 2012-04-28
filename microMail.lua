--[[
	microPost 
	
	References now supported. Now I have to make dmail and cancel work properly.
	
	Planned Features:
	
		Control over sent mail (Edit/Delete until it's been received)
		Mass mailing,
		Subject lines,
		Reference,
		Threads, (in the conversational sense)
		CC & BCC
		cancel functionality
		mailbox storage limits.
		attachments?
		Make matches for sBox strictly match inbox or sent

]]

dofile( Core.GetPtokaXPath( ) .. "scripts/data/chill.table.lua" ) --Gives us table.load, table.save.
tMail = {
	[1] = "#Mail", --Nick
	[2] = "",  --Description
	[3] = "", --Email
	[4] = true, -- Operator?
	tConfig = {
		sMailFile = "Index.l-tbl";
	};
}

sPath = Core.GetPtokaXPath( ) ..  "scripts/data/Mail/"
--[[ sPre creates a formatted pattern readable by string.match in order to detect when PtokaX set prefixes are used. ]]
sPre = "^[" .. ( SetMan.GetString( 29 ):gsub( ( "%p" ), function ( p ) return "%" .. p end ) ) .. "]";
--[[ Less concatenation on the fly if you have the botname ready. ]]
sFromBot = "<" .. tMail[1] .. "> ";
--[[ Used to keep track of who is in the composing state ]]
tCompose = {};

do
	--[[ Loading the mailfile, first load text into memory then execute it! tBoxes should exist after this, but we don't bother testing that. nope. ]]
	tBoxes = table.load( sPath .. tMail.tConfig.sMailFile );
	if not tBoxes then
		--[[ The things we do when tBoxes does not exist. ]]
		os.execute( "mkdir " .. sPath );
		tBoxes = { inbox = {}, sent = {} };
	end
end

function OnStartup( )
	--[[ Register bot, load serialize function, and register interactive Lua mode ]]
	Core.RegBot( unpack( tMail ) );
end
	
function UserConnected( tUser )
	--[[ New mail? Notify user. ]]
	if tBoxes.inbox[ tUser.sNick:lower() ] and tBoxes.inbox[ tUser.sNick:lower() ].nCounter > 0 then
		Core.SendPmToUser( tUser, tMail[1], "You have " .. tBoxes.inbox[ tUser.sNick:lower() ].nCounter .. " new messages in your inbox. Type !inbox to read.\124" );
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
	if sToUser == tMail[1] then
		if tCompose[ tUser.sNick ] then
			if "cancel" == sData:lower():match( "^(%w+)", nInitIndex + 1 ) then
				tCompose[ tUser.sNick ] = nil;
				return Core.SendPmToUser( tUser, tMail[1], "You cancelled your current composition.\124" );
			end
			local bRet, sRetMsg, bInPM, sFrom = Send( tUser.sNick:lower(), tCompose[ tUser.sNick:lower() ][2], sData:sub( nInitIndex, -2 ), tCompose[ tUser.sNick:lower() ][4] );
			tCompose[ tUser.sNick ] = nil;
			return Core.SendPmToUser( tUser, sFrom, sRetMsg ), bRet;
		end
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
end

function OnExit( )
	table.save( tBoxes, sPath .. tMail.tConfig.sMailFile )
end

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

--[[ Gracefully removes a single entry from an array then moves everything up.]]
function tremove( t, k )
	local tlen = #t;
	t[k] = nil;
	for i = k, tlen, 1 do
		t[i] = t[i+1];
	end
end

function Send( sSender, sRec, sMsg, sSubj )
	sSender_low, sRec_low, sSubj = sSender:lower(), sRec:lower(), sSubj or "(No Subject)";
	if tBoxes.inbox[ sRec_low ] then
		tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] + 1 ] = { os.time(), sRec, sSender, sSubj, sMsg, false };
		tBoxes.inbox[ sRec_low ].nCounter = tBoxes.inbox[ sRec_low ].nCounter + 1; --Increments to keep track of messages regardless of standing of array.
		if tBoxes.sent[ sSender_low ] then
			tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];
		else
			tBoxes.sent[ sSender_low ] = { tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ] }
		end
		return true, "You sent the following message to " .. sRec .. ":\n\n" .. sSubj .. "\n\n"  .. sMsg, true, tMail[1];
	else
		tBoxes.inbox[ sRec_low ] = { { os.time(), sRec, sSender, sSubj, sMsg, false }, nCounter = 1 };
		if tBoxes.sent[ sSender_low ] then
			tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];
		else
			tBoxes.sent[ sSender_low ] = { tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ] }
		end
		return true, "You sent the following message to " .. sRec .. ":\n\n" .. sSubj .. "\n\n"  .. sMsg, true, tMail[1];
	end
end

tCommandArrivals = {	
	wmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Recipient> <Message> - Sends message to recipient of your choice.\n";
	},
	rmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Sender's Nick> <Message Number> - PM's all messages sent to you from all users. Type sent before user's name to see a sent message.\n";
	},
	mhelp = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " - PMs this message to you. (sort order of help is dynamic and may change at any time)\n";
	},
	dmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Recipient> <Index> - Deletes message number. (as displayed when checking inbox or sent commands)\n";
	},
	cmail = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " <Recipient> <Subject> - Starting compose mode. Followed by typing message and pressing enter. Can cancel with cancel command.\n"
	},
	inbox = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " - Lists all messages in inbox.\n"
	},
	sent = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " - Lists all sent messages.\n"
	},
	cancel = {
		Permissions = { [0] = true, true, true, true, true, },
		sHelp = " - Cancels compose mode. (for the moment)\n"
	},
}

function tCommandArrivals.mhelp:Action( tUser )
	local sRet = "\n\n**-*-** " .. ScriptMan.GetScript().sName .."  help (use one of these prefixes: " .. SetMan.GetString( 29 ) .. " Works in main or in PM to " .. tMail[1] .. " **-*-**\n\n";
	for name, obj in pairs( tCommandArrivals ) do
		if obj.Permissions[ tUser.iProfile ] then
			sRet = sRet .. name .. obj.sHelp;
		end
	end
	return true, sRet, true, tMail[1];
end

function tCommandArrivals.dmail:Action( tUser, sMsg )
	local sBox, nInd = sMsg:match( "^(%S-)%s-(%d+)|" );
	nInd, sNick, sBox = tonumber( nInd ), tUser.sNick:lower(), ( sBox:lower() == "inbox" or sBox:lower() == "sent" ) and sBox or "inbox";
	if sBox and nInd then
		if tBoxes[ sBox ][ sNick ] then
			if tBoxes[ sBox ][ sNick ][ nInd ] then
				if sBox == "inbox" and not tBoxes[ sBox ][ sNick ][ nInd ][6] then
					tBoxes[ sBox ][ sNick ].nCounter = tBoxes[ sBox ][ sNick ].nCounter - 1;
				end
				tremove( tBoxes[ sBox ][ sNick ], nInd );
				return true, "Successfully deleted message.", true, tMail[1];
			else
				return true, "Error, you don't have that many messages in this mailbox!\124", true, tMail[1];
			end
		else
			return true, "You don't have any messages to delete in this mailbox!\124", true, tMail[1];
		end
	else
		return true, "Syntax error", true, tMail[1];
	end
end

function tCommandArrivals.cancel:Action( tUser, sMsg )
	local sRec = sMsg:match( "^(%S+)|$" );
	local sRec_low, sNick = sRec and sRec:lower(), tUser.sNick:lower();
	if sRec then
		if tBoxes.inbox[ sRec_low ] then
			local t = tBoxes.inbox[ sRec_low ];
			for i = #t, 1, -1 do --Iterate over array in reverse to find last message.
				if t[i][ 3 ] == sNick then --Does the from field match the cancel command user?
					if not t[i][6] then --If so, has the recipient read the message?
						tremove( t, i ); --if not we go ahead and remove it, buttt carefullllly.
						return true, "You've successfully cancelled the message.\124", true, tMail[1];
					else
						return true, "You cannot cancel mail that's already been read\124", true, tMail[1];
					end
				end
			end
			return true, "You haven't sent " .. sRec .. " any messages.\124", true, tMail[1];
		else
			return true, "You haven't sent " .. sRec .. " any messages...\124", true, tMail[1];
		end
	else
		return true, "Syntax error, please check mhelp for proper arguments\124", true, tMail[1];
	end
end
				

function tCommandArrivals.inbox:Action( tUser )
	local ret = "\n\nYour messages are as follows: (Lines with * at the end are unread)\n\n # \t\tCommand" .. string.rep( " ", 30 ) .. "\t To" .. string.rep( " ", 9 ) .."\tFrom " .. string.rep( " ", 9 ) .. "\t\t Date & Time	\t\t\t    Subject\n" .. string.rep( "-", 192 ) .. "\n";
	if tBoxes.inbox[ tUser.sNick ] then
		for i, v in ipairs( tBoxes.inbox[ tUser.sNick ] ) do
			if not v[6] then
				ret = ret .. "[" .. i .. "] \tType '!rmail " .. i .. "' to view this message:\t" .. v[ 2 ] .. "\t" .. v[ 3 ] .. "\t\t" .. os.date( "%x - %X", v[ 1 ] ) .. " (-5 GMT)\t\t" .. v[ 4 ] .. "\t*\n" .. string.rep( "-", 192 ) .. "\n";
			else			
				ret = ret .. "[" .. i .. "]\tType '!rmail " .. i .. "' to view this message:\t" .. v[ 2 ] .. "\t" .. v[ 3 ] .. "\t\t" .. os.date( "%x - %X", v[ 1 ] ) .. " (-5 GMT)\t\t" .. v[ 4 ] .. "\n" .. string.rep( "-", 192 ) .. "\n";
			end
		end
		return true, ret, true, tMail[ 1 ];
	else
		return true, "Sorry, you have an empty inbox!\124", true, tMail[ 1 ];
	end
end

function tCommandArrivals.sent:Action( tUser )
	local ret = "\n\nYour messages are as follows: (Lines with * at the end have not been read by the recipient)\n\n # \t\tCommand" .. string.rep( " ", 30 ) .. "\t To" .. string.rep( " ", 9 ) .."\tFrom " .. string.rep( " ", 9 ) .. "\t\t Date & Time	\t\t\t    Subject\n" .. string.rep( "-", 192 ) .. "\n";
	if tBoxes.sent[ tUser.sNick ] then
		for i, v in ipairs( tBoxes.sent[ tUser.sNick ] ) do
			if not v[6] then
				ret = ret .. "[" .. i .. "]\tType '!rmail sent " .. i .. "' to view this message:\t" .. v[ 2 ] .. "\t " .. v[ 3 ] .. "\t\t" .. os.date( "%x - %X", v[ 1 ] ) .. " (-5 GMT)\t\t" .. v[ 4 ] .. "\t*\n" .. string.rep( "-", 192 ) .. "\n";
			else	
				ret = ret .. "[" .. i .. "]\tType '!rmail sent " .. i .. "' to view this message:\t" .. v[ 2 ] .. "\t " .. v[ 3 ] .. "\t\t" .. os.date( "%x - %X", v[ 1 ] ) .. " (-5 GMT)\t\t" .. v[ 4 ] .. "\n" .. string.rep( "-", 192 ) .. "\n";
			end
		end
		return true, ret, true, tMail[ 1 ] ;
	else
		return true, "Sorry, you have yet to send any messages!\124", true, tMail[1];
	end
end

function tCommandArrivals.wmail:Action( tUser, sMsg )
	if sMsg then
		local sRec, sMail = sMsg:match( "^(%S+)%s(.*)|" );
		if sRec and sMail then
			return Send( tUser.sNick, sRec, sMail );
		else
			return true, "Syntax error, try !wmail recipient message here\124", true, tMail[1];
		end
	end
end

function tCommandArrivals.cmail:Action( tUser, sMsg )
	local sRec, sSubj = sMsg:match( "^(%S+)%s?(.-)|$" );
	if sRec then
		sSubj = ( #sSubj > 0 and sSubj ) or "(No Subject)";
		tCompose[ tUser.sNick:lower() ] = { 0, sRec, tUser.sNick, sSubj, "", false };
		return true, "*** Composing message, please type message and press enter to send.\124", true, tMail[1];
	else
		return true, "Syntax error, you must specify a recipient.\124", true, tMail[1];
	end
end
	

function tCommandArrivals.rmail:Action( tUser, sMsg )
	local sBox, nIndex = sMsg:lower():match( "^(%S-)%s?(%d-)|$" );
	local sNick, sBox = tUser.sNick:lower(), sBox and sBox:lower();
	if type( tonumber ( nIndex ) ) == "number" then
		if sBox ~= "sent" and sBox ~= "inbox" then
			sBox, nIndex = "inbox", tonumber( nIndex );
		else
			nIndex = tonumber( nIndex );
		end
	else
		return true, "Syntax error, please check mhelp for proper arguments.\124", true, tMail[1];
	end
	if tBoxes[ sBox ][ sNick ] then
		if tBoxes[ sBox ][ sNick ][ nIndex ] then
			local tMsg = tBoxes[ sBox ][ sNick ][ nIndex ];
			if sBox == "inbox" then tMsg[6], tBoxes.inbox[ tUser.sNick:lower() ].nCounter = true, tBoxes.inbox[ tUser.sNick ].nCounter - 1; end
			return true, "\nSent on " .. os.date( "%x at %X", tMsg[1] ) ..  "\nFrom: " .. tMsg[ 3 ] .. "\nSubject: " .. tMsg[4] .. "\n\n" .. tMsg[5], true, tMail[1];
		else
			return true, "*** Error, you do not have that many messages.\124", true, tMail[1];
		end
	else
		return true, "Specified box is empty.", true, tMail[1];
	end
end

