--[[
	Script Name: microPost 
	Author: amenay
	
	Planned Features:
	 
		Reference,
		Threads, (in the conversational sense)
		CC & BCC
		attachments?
		Administrative tools, both automated and manual.
		Control over notifications, granularity, where, etc.
		
		Todo:
		
		Make default behavior for send on broadcast to list all recipients.
		Address issue with parsing dollar signs.
		
		Notes on commenting style: Single line comments are comments on that line. Block comments are comments on code that follows.
		
]]
require "sim"

dofile( Core.GetPtokaXPath( ) .. "scripts/data/chill.table.lua" ); 	--Gives us table.load, table.save.
dofile( Core.GetPtokaXPath( ) .. "scripts/microMail.cfg" );			--Would rather have it in the cfg folder.
dofile( Core.GetPtokaXPath( ) .. "scripts/data/tbl/microMailCommands.tbl" );	--Commands and Permissions.
--[[ sPre creates a formatted pattern readable by string.match in order to detect when PtokaX set prefixes are used. ]]
sPre = "^[" .. ( SetMan.GetString( 29 ):gsub( ( "%p" ), function ( p ) return "%" .. p end ) ) .. "]";
--[[ Less concatenation on the fly if you have the botname ready. ]]
sFromBot = "<" .. tMail[1] .. "> ";
--[[ Used to keep track of who is in the composing state ]]
tCompose = {};

do
	--[[ Things we do before OnStartup (this code runs immediately.) Loading the mailfile, first load text into memory then execute it! tBoxes should exist after this, but we don't bother testing that. nope. ]]
	tBoxes = table.load( tMail.tConfig.sPath .. tMail.tConfig.sMailFile );
	if not tBoxes then
		--[[ The things we do when tBoxes does not exist. ]]
		os.execute( "mkdir \"" .. tMail.tConfig.sPath .. "\"" );
		tBoxes = { inbox = {}, sent = {} };
	end
end

	--[[ Register bot, load serialize function, and register interactive Lua mode.]]
	
function OnStartup( )
	Core.RegBot( unpack( tMail ) );
	sim.hook_OnStartup( { "#SIM", "PtokaX Lua interface via ToArrival", "", true }, { "amenay", "Generic" } );
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
	local sToUser = sData:match( "^(%S+)", 6 );											--Capture begins at the 6th char, ends at the first space after the 1st non-space character. Receiving user, per nmdc prot.
	local nInitIndex = #sToUser + 18 + #tUser.sNick * 2; 								--A bit of math to mark the first character of the actual message sent.
	sim.hook_ToArrival( tUser, sData, sToUser, nInitIndex );							--sim will listen for messages sent to Botname registered to it on startup. see sim.hook_ToArrival
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
	table.save( tBoxes, tMail.tConfig.sPath .. tMail.tConfig.sMailFile );
	sim.hook_OnExit();
end

OnError, OpDisconnected = sim.hook_OnError, sim.hook_OpDisconnected;

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

--[[ Gracefully removes a single entry from an array then moves everything down.]]
function tremove( t, k )
	local tlen = #t;
	t[k] = nil;
	for i = k, tlen, 1 do
		t[i] = t[i+1];
	end
end

function Send( sSender, Rec, sMsg, sSubj, sBroadcast )																	--Used by cmail and wmail to save to inbox and sent arrays.																						
	local bBroadcast, sRec;		
	if type( Rec ) == "table" then
		if not sBroadcast then
			sBroadcast = table.concat( Rec, ", " );
		end
		sRec = Rec[1];
		table.remove( Rec, 1 );
		if #Rec > 0 then
			bBroadcast = true;
		else
			bBroadcast = false;
		end
	end
	sRec = sRec or Rec;
	local sSender_low, sRec_low, sSubj = sSender:lower(), sRec:lower(), sSubj or "(No Subject)";
	local tRecUser = Core.GetUser( sRec );																							--Gets recieving user's object if online.
	if tBoxes.inbox[ sRec_low ] then																								--Has this user ever received a message?
		if #tBoxes.inbox[ sRec_low ] >= tMail.tConfig.nInboxLimit then
			if bBroadcast then
				Core.SendPmToNick( sSender, tMail[1], sRec .. " has exceeded their mailbox limit.\124" );
				return Send( sSender, Rec, sMsg, sSubj, sBroadcast );
			else
				return true, sRec .. " has exceeded their mailbox limit.\124", true, tMail[1];
			end
		else
			tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] + 1 ] = { os.time(), sRec, sSender, sSubj, sMsg, false };				--Create a new message table.
			tBoxes.inbox[ sRec_low ].nCounter = tBoxes.inbox[ sRec_low ].nCounter + 1;														--Increments to keep track of unread messages.
			if tRecUser then
				Core.SendToUser( tRecUser, sFromBot .. "You've received a message from " .. sSender .. " type '" .. sPre:sub( 4, 4 ) .. "rmail " ..  tBoxes.inbox[ sRec_low ].nCounter .. "' to view.\124" );
			end
			if not bBroadcast then
				if tBoxes.sent[ sSender_low ] then																					--Has the user ever sent a message?
					if #tBoxes.sent[ sSender_low ] >= tMail.tConfig.nSentLimit then
						return true, "Your 'Sent' mailbox has reached its limit. Try deleting some messages first.\124", true, tMail[1];
					elseif sBroadcast then
						local t = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];
						t[2] = sBroadcast;
						tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = t;
					else
						tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];	--If they do we just create the reference as the end of the array.
					end
				else
					tBoxes.sent[ sSender_low ] = { tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ] };									--If they don't we create the reference inside of a new constructor.
				end
				return true, "You sent the following message to " .. ( sBroadcast or sRec ) .. ":\n\n" .. sSubj .. "\n\n"  .. sMsg, true, tMail[1];
			else
				return Send( sSender, Rec, sMsg, sSubj, sBroadcast );
			end
		end
	else
		tBoxes.inbox[ sRec_low ] = { { os.time(), sRec, sSender, sSubj, sMsg, false }, nCounter = 1 };									--Inbox item created inside constructor for new table.
		if tRecUser then
			Core.SendToUser( tRecUser, sFromBot .. "You've received a message from " .. sSender .. " type '" .. sPre:sub( 4, 4 ) .. "rmail 1' to view.\124" );
		end
		if not bBroadcast then
			if tBoxes.sent[ sSender_low ] then																					--Has the user ever sent a message?
				if #tBoxes.sent[ sSender_low ] >= tMail.tConfig.nSentLimit then
					return true, "Your 'Sent' mailbox has reached its limit. Try deleting some messages first.\124", true, tMail[1];
				elseif sBroadcast then
					local t = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];
					t[2] = sBroadcast;
					tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = t;
				else
					tBoxes.sent[ sSender_low ][ #tBoxes.sent[ sSender_low ] + 1 ] = tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ];	--If they do we just create the reference as the end of the array.
				end
			else
				tBoxes.sent[ sSender_low ] = { tBoxes.inbox[ sRec_low ][ #tBoxes.inbox[ sRec_low ] ] };									--If they don't we create the reference inside of a new constructor.
			end
		else
			return Send( sSender, Rec, sMsg, sSubj, sBroadcast );
		end
		return true, "You sent the following message to " .. ( sBroadcast or sRec ) .. ":\n\n" .. sSubj .. "\n\n"  .. sMsg, true, tMail[1];
	end
end

