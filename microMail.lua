--[[
	Script Name: microPost 
	Author: amenay
	
	Planned Features:
	
		Mass mailing,
		Reference,
		Threads, (in the conversational sense)
		CC & BCC
		attachments?
		Administrative tools, both automated and manual.

		Notes on commenting style: Single line comments are comments on that line. Block comments are comments on code that follows.
		
]]
dofile( Core.GetPtokaXPath( ) .. "scripts/data/chill.table.lua" ) --Gives us table.load, table.save.
tMail = {
	[1] = "#Mail", 		--Nick
	[2] = "",  			--Description
	[3] = "", 			--Email
	[4] = true, 		-- Operator?
	nInboxLimit = 200,
	nSentLimit = 200,
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
	--[[ Things we do before OnStartup (this code runs immediately.) Loading the mailfile, first load text into memory then execute it! tBoxes should exist after this, but we don't bother testing that. nope. ]]
	tBoxes = table.load( sPath .. tMail.tConfig.sMailFile );
	if not tBoxes then
		--[[ The things we do when tBoxes does not exist. ]]
		os.execute( "mkdir \"" .. sPath .. "\"" );
		tBoxes = { inbox = {}, sent = {} };
	end
end

	--[[ Register bot, load serialize function, and register interactive Lua mode.]]
	
function OnStartup( )
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
	local nInitIndex = #tUser.sNick + 4
	if sData:match( sPre, nInitIndex ) then
		local sCmd = sData:match( "^(%w+)", nInitIndex + 1 )
		if sCmd then
			sCmd = sCmd:lower( )
			if tCommandArrivals[ sCmd ] then
				if tCommandArrivals[ sCmd ].Permissions[ tUser.iProfile ] then 
					local sMsg
					if nInitIndex + #sCmd <= #sData + 1 then sMsg = sData:sub( nInitIndex + #sCmd + 2 ) end
					return ExecuteCommand( tUser, sMsg, sCmd )
				else
					return Core.SendPmToUser( tUser, tConfig.sNick,  "*** Permission denied.\124" ), true;
				end
			else
				return false
			end
		end
	end
end				

function ToArrival( tUser, sData )
	local sToUser = sData:match( "^(%S+)", 6 );											--Capture begins at the 6th char, ends at the first space after the 1st non-space character. Receiving user, per nmdc prot.
	local nInitIndex = #sToUser + 18 + #tUser.sNick * 2; 								--A bit of math to mark the first character of the actual message sent.
	if sToUser == tMail[1] then
		if tCompose[ tUser.sNick ] then													--This is where we check to see if a user is composing.
			if "cancel" == sData:lower():match( "^(%w+)", nInitIndex + 1 ) then 		--If they are we check for cancel
				tCompose[ tUser.sNick ] = nil;											--Done composing, removing user from compose state.
				return Core.SendPmToUser( tUser, tMail[1], "You cancelled your current composition.\124" )
			end
			
			--[[Here we call Send to do work. Notice we use values from tCompose which perserved case, unlike table keys.
			We dont want to make the user worry about case, or see the side effect of making all table keys lowercase.
			Sent has return values in the same format as ExecuteCommand, so we get consistant behavior with people using compose,
			which doesn't use a command for the comitting of a message.]]
			
			local bRet, sRetMsg, bInPM, sFrom = Send( tUser.sNick:lower(), tCompose[ tUser.sNick ][2], sData:sub( nInitIndex, -2 ), tCompose[ tUser.sNick ][4] );
			tCompose[ tUser.sNick ] = nil;
			return Core.SendPmToUser( tUser, sFrom, sRetMsg ), bRet;
		end
		if sData:match( sPre, nInitIndex ) then						 					--Uses our premade pattern match to see if the first char of the message is a prefix.
			local sCmd = sData:match( "^(%w+)", nInitIndex + 1 ) 	 					--It is, so, we capture alphanumeric matches immediately following said prefix.
			if sCmd then 																--was someone just shouting expletives?
				sCmd = sCmd:lower( ) 													--again users shouldnt have to worry about case.
				if tCommandArrivals[ sCmd ] then 										--checks all available commands
					if tCommandArrivals[ sCmd ].Permissions[ tUser.iProfile ] then  

						--[[Is the sum of protocol command including the prefix, the user command, a space (+1) and a endpipe (+1) greater or equal to than the entire message?
						If so, that means it is a command with arguments (and isn't just a command with a space at the end.
						Let's capture the substring, including the endpipe (this is an optimization!)* , and store it in sMsg. 
						*Keeping the endpipe on lets us avoiding concatenating it either in C or Lua (The hubsoft does it if we don't term string with it in Lua, anyway.]]
	
						local sMsg = "";
						if ( nInitIndex + #sCmd + 2 ) < #sData then 
							sMsg = sData:sub( nInitIndex + #sCmd + 2 );
						end
						return ExecuteCommand( tUser, sMsg, sCmd, true ); 				--per usual we let ExectueCommand do the job of passing the command its arguments and passing back its returns.
					else
						return Core.SendPmToUser( tUser, tMail[1],  "*** Permission denied.\124" ), true;
					end
				end
			end
		end
	end
end

function OnExit( )
	table.save( tBoxes, sPath .. tMail.tConfig.sMailFile );
end

	--[[Main purpose of this function is to have a uniform method of deciding whether to pass the text to the next script,
	what text to respond with from this script, where to respond, and the nick sending the response.]]

function ExecuteCommand( tUser, sMsg, sCmd, bInPM )
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
end

--[[ Gracefully removes a single entry from an array then moves everything up.]]
function tremove( t, k )
	local tlen = #t;
	t[k] = nil;
	for i = k, tlen, 1 do
		t[i] = t[i+1];
	end
end

function Send( sSender, sRec, sMsg, sSubj )  																						--Used by cmail and wmail to save to inbox and sent arrays.
	local sSender_low, sRec_low, sSubj = sSender:lower(), sRec:lower(), sSubj or "(No Subject)";
	if tBoxes.inbox[ sRec_low ] then																								--Has this user ever received a message?
		if #tBoxes.inbox[ sRec_low ] >= tMail.nInboxLimit then
			return true, "The recipient has exceeded their mailbox limit./124", true, tMail[1];
		else
			tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] + 1 ] = { os.time(), sRec, sSender, sSubj, sMsg, false };				--Create a new table.
			tBoxes.inbox[ sRec_low ].nCounter = tBoxes.inbox[ sRec_low ].nCounter + 1;													--Increments to keep track of unread messages.
			if tBoxes.sent[ sSender_low ] then																							--Has the user ever sent a message?
				if #tBoxes.sent[ sSender_low ] >= tMail.nSentLimit then
					return true, "Your 'Sent' mailbox has reached its limit. Try deleting some messages first./124", true, tMail[1];
				else
					tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];	--If they do we just create the reference as the end of the array.
				end
			else
				tBoxes.sent[ sSender_low ] = { tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ] }									--If they don't we create the reference inside of a new constructor.
			end
			return true, "You sent the following message to " .. sRec .. ":\n\n" .. sSubj .. "\n\n"  .. sMsg, true, tMail[1];
		end
	else
		tBoxes.inbox[ sRec_low ] = { { os.time(), sRec, sSender, sSubj, sMsg, false }, nCounter = 1 };								--Inbox item created inside constructor for new table.
		if tBoxes.sent[ sSender_low ] then
			if #tBoxes.sent[ sSender_low ] >= tMail.nSentLimit then
				return true, "Your 'Sent' mailbox has reached its limit. Try deleting some messages first./124", true, tMail[1];
			else
				tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];	--Has sent messages so no constructor needed.
			end
		else
			tBoxes.sent[ sSender_low ] = { tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ] }									--Hasn't, constructor needed.
		end
		return true, "You sent the following message to " .. sRec .. ":\n\n" .. sSubj .. "\n\n"  .. sMsg, true, tMail[1];
	end
end

tCommandArrivals = {	
	wmail = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " <Recipient> <Message> - Sends message to recipient of your choice.\n";
	},
	rmail = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " [Sent or Inbox] <Message Number> - PM's all messages sent to you from all users. Type sent before user's name to see a sent message.\n";
	},
	mhelp = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " - PMs this message to you. (sort order of help is dynamic and may change at any time)\n";
	},
	dmail = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " [Sent or Inbox] <Message Number> - Deletes message number. (as displayed when checking inbox or sent commands)\n";
	},
	cmail = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " <Recipient> <Subject> - Starting compose mode. Followed by typing message and pressing enter. Can cancel with cancel command.\n"
	},
	inbox = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " - Lists all messages in inbox.\n"
	},
	sent = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " - Lists all sent messages.\n"
	},
	cancel = {
		Permissions = { [0] = true, true, true, true, true, true },
		sHelp = " [Recipient] - Cancels compose mode if set, otherwise removes last unread message sent to Recipient.\n"
	},
}

function tCommandArrivals.mhelp:Action( tUser )
	local sRet = "\n\n**-*-** " .. ScriptMan.GetScript().sName .."  help (use one of these prefixes: " .. SetMan.GetString( 29 ) .. " Works in main or in PM to " .. tMail[1] .. " **-*-**\n\n";
	for name, obj in pairs( tCommandArrivals ) do
		if obj.Permissions[ tUser.iProfile ] then
			sRet = sRet .. "\t" .. name .. "\t" .. obj.sHelp;
		end
	end
	return true, sRet, true, tMail[1];
end

function tCommandArrivals.dmail:Action( tUser, sMsg )
	--[[Match with two capture, 1st is 0 or more nonspace characters, may result in nil being assigned to sBox. 2nd match is 1 or more digits, his needs to be turned into a number type.]]
	local sBox, nInd = sMsg:match( "^(%S-)%s-(%d+)|" ); 
	 --[[So, we convert nInd to number, make tUser.sNick in lowercase like all of our indices, and lastly we check if sBox is a match, if not it defaults to 'inbox'. 
	Otherwise for valid arguments we lower the case for the same reason as sNick.]]
	local nInd, sNick, sBox = tonumber( nInd ), tUser.sNick:lower(), ( sBox and ( sBox:lower() == "inbox" or sBox:lower() == "sent" ) ) and sBox or "inbox";
	if sBox and nInd then
		if tBoxes[ sBox ][ sNick ] then
			if tBoxes[ sBox ][ sNick ][ nInd ] then
				--[[ nCounter is used to keep track of the amount of total unread messages, so we should check if the message being deleted has been read so we can have an accurate count.
				By the way, we check inbox because sent messages just reference the inbox items of the recipient. Who cares abount unread sent? Future changes may have an interactive confirmation
				on dmail for deletion of unread mail. Unplanned "feature" added is messages deleted without being read keep their reference in the sending users outbox, along with unread status.]] 
				if sBox == "inbox" and not tBoxes[ sBox ][ sNick ][ nInd ][6] then  
					tBoxes[ sBox ][ sNick ].nCounter = tBoxes[ sBox ][ sNick ].nCounter - 1;
				end
				tremove( tBoxes[ sBox ][ sNick ], nInd ); 						--Gracefully remove the reference.
				return true, "Successfully deleted message.", true, tMail[1];
			else
				return true, "Error, you don't have that many messages in this mailbox!\124", true, tMail[1];
			end
		else
			return true, "You don't have any messages to delete in this mailbox!\124", true, tMail[1];
		end
	else
		return true, "Syntax error, please check mhelp for the proper arguments.\124", true, tMail[1];
	end
end

function tCommandArrivals.cancel:Action( tUser, sMsg )
	local sRec = sMsg:match( "^(%S+)|$" );
	if sRec then
		local sRec_low, sNick = sRec:lower(), tUser.sNick:lower();
		if tBoxes.inbox[ sRec_low ] then
			local t = tBoxes.inbox[ sRec_low ];
			for i = #t, 1, -1 do 										--Iterate over array in reverse to find last message.
				if t[i][ 3 ]:lower() == sNick then 								--Does the from field match the cancel command user?
					if not t[i][6] then 								--If so, has the recipient read the message?
						t.nCounter = t.nCounter - 1; 					--Keeping nCounter accurate.
						tremove( t, i ); 								--if not we go ahead and remove it, buttt carefullllly.
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
				

function tCommandArrivals.inbox:Action( tUser ) -- Most of this command is formatting text, with liberal use of string.rep to attempt general text alignment, same with sent, they're nearly identical.
	local ret = "\n\nYour messages are as follows: (Lines with * at the end are unread)\n\n # \t\tCommand" .. string.rep( " ", 30 ) .. "\t To" .. string.rep( " ", 9 ) .."\tFrom " .. string.rep( " ", 9 ) .. "\t\t Date & Time	\t\t\t    Subject\n" .. string.rep( "-", 192 ) .. "\n";
	if tBoxes.inbox[ tUser.sNick:lower() ] and #tBoxes.inbox[ tUser.sNick:lower() ] > 0 then
		for i, v in ipairs( tBoxes.inbox[ tUser.sNick:lower() ] ) do
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
	if tBoxes.sent[ tUser.sNick:lower() ] and #tBoxes.sent[ tUser.sNick:lower() ] > 0 then
		for i, v in ipairs( tBoxes.sent[ tUser.sNick:lower() ] ) do
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

function tCommandArrivals.wmail:Action( tUser, sMsg ) --Really just handles text, passing it to Send.
	if sMsg then
		local sRec, sMail = sMsg:match( "^(%S+)%s(.*)|" );
		if sRec and sMail then
			return Send( tUser.sNick, sRec, sMail );
		else
			return true, "Syntax error, please check mhelp for the proper arguments.\124", true, tMail[1];
		end
	end
end

function tCommandArrivals.cmail:Action( tUser, sMsg )
	local sRec, sSubj = sMsg:match( "^(%S+)%s?(.-)|$" );
	if sRec then
		sSubj = ( #sSubj > 0 and sSubj ) or "(No Subject)"; 								--Is subject longer than nothing, if not we make it uniform to wmail's no subject.
		tCompose[ tUser.sNick ] = { 0, sRec, tUser.sNick, sSubj, "", false }; 		--So, now we listen on ToArrival for this user.
		return true, "*** Composing message, please type message and press enter to send.\124", true, tMail[1];
	else
		return true, "Syntax error, you must specify a recipient.\124", true, tMail[1];
	end
end
	

function tCommandArrivals.rmail:Action( tUser, sMsg )
	local sBox, nIndex = sMsg:lower():match( "^(%S-)%s?(%d-)|$" );  --Capture 0 or more nonspace characters, then there might be a space, and 0 or more digits, which are to be captured.
	local sNick, sBox = tUser.sNick:lower(), sBox and sBox:lower(); --if sBox exists we want it lowercase, again user doesn't have to worry about case.
	if nIndex and #nIndex > 0 then												--Make sure we didn't capture an empty string.
		if sBox ~= "sent" and sBox ~= "inbox" then					--If it isn't one of the two we want to set it to the default "inbox"
			sBox, nIndex = "inbox", tonumber( nIndex );
		else
			nIndex = tonumber( nIndex );
		end
	else
		return true, "Syntax error, please check mhelp for proper arguments.\124", true, tMail[1];
	end
	if tBoxes[ sBox ][ sNick ] then									--Does the user have an inbox?
		if tBoxes[ sBox ][ sNick ][ nIndex ] then					--Does the message number exist?
			local tMsg = tBoxes[ sBox ][ sNick ][ nIndex ];			--Variable pointing straight to the table in question.
			if sBox == "inbox" then tMsg[6], tBoxes.inbox[ sNick ].nCounter = true, tBoxes.inbox[ sNick ].nCounter - 1; end		--Keeps track of read messages for inbox only.
			return true, "\nSent on " .. os.date( "%x at %X", tMsg[1] ) ..  "\nFrom: " .. tMsg[ 3 ] .. "\nSubject: " .. tMsg[4] .. "\n\n" .. tMsg[5], true, tMail[1];
		else
			return true, "*** Error, you do not have that many messages.\124", true, tMail[1];
		end
	else
		return true, "Specified box is empty.\124", true, tMail[1];
	end
end

