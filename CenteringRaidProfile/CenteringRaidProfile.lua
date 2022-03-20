
----------------
-- PROPERTIES --
----------------

local ADDON_NAME = GetAddOnMetadata('CenteringRaidProfile', 'Title');
local ADDON_VERSION = GetAddOnMetadata('CenteringRaidProfile', 'Version');
local ADDON_INITIALIZED = false;

local RAID_PROFILE_OPTION_KEEP_GROUPS_TOGETHER = 'keepGroupsTogether';
local RAID_PROFILE_OPTION_HORIZONTAL_GROUPS = 'horizontalGroups';
local RAID_PROFILE_OPTION_FRAME_WIDTH = 'frameWidth';
local RAID_PROFILE_OPTION_FRAME_HEIGHT = 'frameHeight';
local RAID_PROFILE_OPTION_SHOW_BORDERS = 'displayBorder';

local CENTERING_RAID_PROFILE_NAME = 'Centering Raid Profile';

-- The following values were pulled from Blizzard's interface code.
-- BCUF refers to Blizzard's Compact Unit Frame and related classes (to remember where I got these numbers).
local BCUF_BORDER_WIDTH = 8;
local BCUF_GROUP_TITLE_HEIGHT = 14;

local CENTERING_RAID_PROFILE_SETTING_DEBUG_LOGGING = 'DebugLogging'
local ADDON_DEFAULT_SETTINGS = {
	[CENTERING_RAID_PROFILE_SETTING_DEBUG_LOGGING] = false,
};

local enforceConfigurationAfterCombat = false;

----------------
-- STRUCTURES --
----------------

local CONSOLE_COMMAND_TABLE = {
	['status'] = function()
		local text = '['..ADDON_NAME..'] Version '..ADDON_VERSION..' | Status: '
		if (ADDON_INITIALIZED == true) then
			text = text..'Active!';
		else
			text = text..'INACTIVE!';
		end
		print(text);
	end,
	['help'] = '['..ADDON_NAME..'] Available console commands: status, help, debug on|off.',
	['debug'] = function(enabled)
		local boolValue = CenteringRaidProfile_ToBoolean(enabled);
		CenteringRaidProfileSettings[CENTERING_RAID_PROFILE_SETTING_DEBUG_LOGGING] = boolValue;
		
		local message = '['..ADDON_NAME..'] Debug output ';
		if (boolValue) then
			message = message .. 'enabled!';
		else
			message = message .. 'disabled.';
		end
		print(message);
	end
}

--------------
-- HANDLERS --
--------------

function CenteringRaidProfile_OnLoad(self)
	self:RegisterEvent('PLAYER_LOGIN');
	self:RegisterEvent('PLAYER_REGEN_DISABLED');
	
	SLASH_CENTERING_RAID_PROFILE1 = '/crp';
	SlashCmdList['CENTERING_RAID_PROFILE'] = function(message)
		CenteringRaidProfile_OnConsoleCommand(message, CONSOLE_COMMAND_TABLE);
	end;
end


function CenteringRaidProfile_OnEvent(self, event, ...)
	if (event == 'PLAYER_LOGIN') then
		CenteringRaidProfile_Initialize();
	elseif (event == 'PLAYER_REGEN_DISABLED') then
		if (enforceConfigurationAfterCombat) then
			CenteringRaidProfile_ConfigureAutoPositioningRaidProfile();
		end
	end
end


function CenteringRaidProfile_OnConsoleCommand(message, commandTable)
	local command, parameters = strsplit(' ', message, 2);
	local entry = commandTable[command:lower()];
	local which = type(entry);
	
	if (which == 'function') then
		entry(parameters)
	elseif (which == 'table') then
		CenteringRaidProfile_OnConsoleCommand(parameters or '', entry);
	elseif (which == 'string') then
		print(entry);
	elseif (message ~= 'help') then
		CenteringRaidProfile_OnConsoleCommand('help', commandTable);
	end
end

---------------
-- FUNCTIONS --
---------------

function CenteringRaidProfile_Initialize()
	-- Only initialize the add-on once.
	if (ADDON_INITIALIZED == true) then
		return;
	end
	
	if (CenteringRaidProfileSettings == nil) then
		CenteringRaidProfileSettings = ADDON_DEFAULT_SETTINGS;
	end
	
	-- WE SHOULD ONLY DO HOOKS ONCE!!!
	
	-- Hook this in order to securely do the initial raid profile configuration when the player loads into the game
	-- and when the player initially joins a group.
	-- NOTE: I was doing this originally in my own event handler, but I'm trying this in order to try avoid tainting
	-- issues.
	hooksecurefunc('CompactUnitFrameProfiles_OnEvent', function(self, event)
		if (event == 'COMPACT_UNIT_FRAME_PROFILES_LOADED') then
			CenteringRaidProfile_ConfigureAutoPositioningRaidProfile();
		elseif (event == 'GROUP_JOINED') then
			local inCombat = InCombatLockdown();
			if (inCombat == false) then
				CenteringRaidProfile_UpdateAutoPositioningRaidFrames(CompactRaidFrameManager);
			end
		end
	end)
	
	-- Hook the following functions in order to enforce certain settings, and to adjust the raid frame
	-- as a player adjusts their profile settings (i.e. if the player changes their frame width, the raid frame
	-- will adjust accordingly).
	hooksecurefunc('SaveRaidProfileCopy', function(profile, option, value)
		local inCombat = InCombatLockdown();
		if (inCombat == false) then
			CenteringRaidProfile_ConfigureAutoPositioningRaidProfile();
		else
			enforceConfigurationAfterCombat = true;
		end
	end)
	hooksecurefunc('CompactUnitFrameProfiles_ApplyCurrentSettings', function(profile)
		local inCombat = InCombatLockdown();
		if (inCombat == false) then
			CenteringRaidProfile_UpdateAutoPositioningRaidFrames(CompactRaidFrameManager);
		end
	end)
	
	-- Hook this in order to have the raid frames adjusted whenever Blizzard updates the raid frames.
	-- NOTE: I was doing this originally in my own event handler, but I'm trying this in order to try avoid tainting
	-- issues.
	hooksecurefunc('CompactRaidFrameManager_UpdateShown', function(manager)
		local inCombat = InCombatLockdown();
		if (inCombat == false) then
			CenteringRaidProfile_UpdateAutoPositioningRaidFrames(manager);
		end
	end)
	
	ADDON_INITIALIZED = true;
	
	CenteringRaidProfile_DebugPrint(ADDON_NAME..' initialized successfully!');
end


function CenteringRaidProfile_ConfigureAutoPositioningRaidProfile()
	-- We are not allowed to modify frames (or really do much of anything with the UI) while in combat.
	local inCombat = InCombatLockdown();
	if (inCombat == true) then
		enforceConfigurationAfterCombat = true;
		CenteringRaidProfile_DebugPrint('Failed to configure raid frames: combat lockdown.');
		return;
	end

	-- Trying to do anything with raid profiles before they are fully loaded is guaranteed to lead to data loss
	-- (even with existing raid profiles that we don't manage).
	local profilesLoaded = HasLoadedCUFProfiles();
	if (profilesLoaded == false) then
		return;
	end
	
	local profileExists = RaidProfileExists(CENTERING_RAID_PROFILE_NAME);
	if (profileExists == false) then
		local numProfiles = GetNumRaidProfiles();
		local maxNumProfiles = GetMaxNumCUFProfiles();
		if (numProfiles < maxNumProfiles) then
			CreateNewRaidProfile(CENTERING_RAID_PROFILE_NAME);
		else
			print('['..ADDON_NAME..'] You have too many raid profiles ('..numProfiles..'); you must remove one in order for this add-on to function.');
		end
	end
	
	-- Below we are enforcing certain raid profile options in order for this addon to work.  Note that wrapping
	-- these enforcements in if-statements is necessary in order to avoid stack overflows from hooking
	-- `SaveRaidProfileCopy` (which we do for further enforcement).
	
	-- In order for all this to be manageable as a fun side project, I'm limiting this to only supporting
	-- a group-based layout for the raid profile.
	local keepGroups = GetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_KEEP_GROUPS_TOGETHER);
	if (keepGroups == false) then
		SetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_KEEP_GROUPS_TOGETHER, true);
		SaveRaidProfileCopy(CENTERING_RAID_PROFILE_NAME);
	end
	
	-- It's particularly important to turn off the dynamic container positioning, or it will prevent our
	-- positioning code from working at all.  As a default, we try to align the container to be vaguely
	-- centered on the screen as if it were roughly the size of the Resize Frame graphic (roughly 190
	-- points wide).
	local dynamicPosition = GetRaidProfileSavedPosition(CENTERING_RAID_PROFILE_NAME);
	if (dynamicPosition == true) then
		local screenWidth = GetScreenWidth();
		local screenHeight = GetScreenHeight();
		local topOffset = screenHeight / 2.0;
		local bottomOffset = topOffset + 190;
		local leftOffset = (screenWidth - 190) / 2;
		SetRaidProfileSavedPosition(CENTERING_RAID_PROFILE_NAME, false, 'TOP', topOffset, 'BOTTOM', bottomOffset, 'LEFT', leftOffset);
	end
	
	local activeProfile = GetActiveRaidProfile();
	if (activeProfile == CENTERING_RAID_PROFILE_NAME) then
		CompactUnitFrameProfiles_ApplyCurrentSettings();
	end
	
	enforceConfigurationAfterCombat = false;
	CenteringRaidProfile_DebugPrint('Configured auto-positioning raid profile.');
end


function CenteringRaidProfile_UpdateAutoPositioningRaidFrames(manager)
	-- We are not allowed to modify frames (or really do much of anything with the UI) while in combat.
	local inCombat = InCombatLockdown();
	if (inCombat == true) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: combat lockdown.');
		return;
	end

	-- Trying to do anything with raid profiles before they are fully loaded is guaranteed to lead to data loss
	-- (even with existing raid profiles that we don't manage).
	local profilesLoaded = HasLoadedCUFProfiles();
	if (profilesLoaded == false) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: profiles not loaded.');
		return;
	end
	
	-- No point doing anything if the current raid profile isn't the auto-positioning one.
	local activeProfile = GetActiveRaidProfile();
	if (activeProfile ~= CENTERING_RAID_PROFILE_NAME) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: profile not active.');
		return;
	end

	-- If we aren't in a group, we shouldn't bother doing anything.
	local numGroups, _, playerSubgroup = CenteringRaidProfile_GetNumVisibleRaidGroups();
	if (numGroups == 0) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: no group detected.');
		return;
	end
	CenteringRaidProfile_DebugPrint('Non-empty subgroups: '..numGroups);
	
	-- TODO: These should theoretically be configurable settings that are stored as saved variables.
	local centerPointX = GetScreenWidth() * 0.5;
	local centerPointY = GetScreenHeight() * 0.3056;
	CenteringRaidProfile_DebugPrint('Desired center point: '..centerPointX..', '..centerPointY);

	-- NOTE: I tried various implementations for centering the raid frame, and these were the best two options.
	-- Strategy A was my original strategy of calculating the center point based on the raid profile options.
	-- Strategy B was my lastest and most accurate strategy, which simply uses the actual size of the individual
	-- raid groups to calculate the center point.  However, I'm worried that accessing the group frame is
	-- tainting the UI, so I'm default to strategy A until I can resolve all other tainting issues.
--	local anchorPointX, anchorPointY, groupWidth, groupHeight = CenteringRaidProfile_GetAnchorPointCalculated(centerPointX, centerPointY, numGroups);
	local anchorPointX, anchorPointY, groupWidth, groupHeight = CenteringRaidProfile_GetAnchorPointAccurate(centerPointX, centerPointY, numGroups, playerSubgroup);

	-- Position the resize frame, and save the final bounds to the raid profile.
	local resizeFrame = manager.containerResizeFrame;
	resizeFrame:ClearAllPoints();
	resizeFrame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', anchorPointX, anchorPointY);
	resizeFrame:SetHeight(groupHeight);
	resizeFrame:SetUserPlaced(1);
	CompactRaidFrameManager_ResizeFrame_SavePosition(manager)
	CenteringRaidProfile_DebugPrint('Updated auto-adjusting raid profile position.');
end


function CenteringRaidProfile_GetAnchorPointCalculated(centerPointX, centerPointY, numGroups)
	-- Calculate the size of the complete raid frame based on the number of non-empty groups and various
	-- raid profile settings.
	local unitWidth = GetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_FRAME_WIDTH);
	local unitHeight = GetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_FRAME_HEIGHT);
	local usingBorders = GetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_SHOW_BORDERS);
	local usingHorizontalGroups = GetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_HORIZONTAL_GROUPS);
	CenteringRaidProfile_DebugPrint('Unit frame size: '..unitWidth..', '..unitHeight);

	local groupWidth = (unitWidth * numGroups);
	local groupHeight = (unitHeight * MEMBERS_PER_RAID_GROUP) + BCUF_GROUP_TITLE_HEIGHT;
	if (usingBorders) then
		-- The width of the frame does visually shift from the anchor position, so we account for it in
		-- container width.
		groupWidth = groupWidth + (BCUF_BORDER_WIDTH * 2 * numGroups);
		-- Note that the position of the frame is not pushed down by the top border because it rendered just
		-- below the group title area, so we only need to account for the bottom border for determining the
		-- height of the container.
		groupHeight = groupHeight + BCUF_BORDER_WIDTH;
	end
	
	-- I find horizontal groups to be ugly (mostly because of the group title), but I know people who actually use
	-- this feature, so I support it here.
	if (usingHorizontalGroups) then
		groupWidth = (unitWidth * MEMBERS_PER_RAID_GROUP);
		groupHeight = (unitHeight + BCUF_GROUP_TITLE_HEIGHT) * numGroups;
		if (usingBorders) then
			groupWidth = groupWidth + (BCUF_BORDER_WIDTH * 2);
			groupHeight = groupHeight + (BCUF_BORDER_WIDTH * numGroups);
		end
	end
	
	-- Calculate the anchor point for the resize frame to place the raid container where we want to
	-- (i.e. centered on the default frame).
	local anchorPointX = centerPointX - (groupWidth / 2) - (numGroups + 1);
	local anchorPointY = centerPointY + (groupHeight / 2);
	CenteringRaidProfile_DebugPrint('Calculated anchor point: '..anchorPointX..', '..anchorPointY);

	return anchorPointX, anchorPointY, groupWidth, groupHeight;
end


function CenteringRaidProfile_GetAnchorPointAccurate(centerPointX, centerPointY, numGroups, playerSubgroup)
	-- When a player first joins a group after logging in, the raid group frames are seemingly not loaded right
	-- away, so we need to check to be sure that we can grab the player's group frame before we can continue.
	-- If we can't, we probably just have to wait another second or two at most.
	local playerGroupFrame = _G['CompactRaidGroup'..playerSubgroup];
	if (playerGroupFrame == nil) then
		RPTweaks_DebugPrint('Failed to update raid frames: group frames not fully loaded (swapping to different strategy).');
		return CenteringRaidProfile_GetAnchorPointA(centerPointX, centerPointY, numGroups);
	end

	-- Calculate the size of the complete raid frame based on the number of non-empty groups, as well as the
	-- size settings of the individual unit frames.
	local groupWidth = playerGroupFrame:GetWidth();
	local groupHeight = playerGroupFrame:GetHeight();
	local usingHorizontalGroups = GetRaidProfileOption(CENTERING_RAID_PROFILE_NAME, RAID_PROFILE_OPTION_HORIZONTAL_GROUPS);
	if (usingHorizontalGroups) then
		-- When using horizontal groups, the container frame needs an extra group's worth of height in order to
		-- avoid overflow for some reason.  I suspect this is a bug with Blizzard's FlowContainer.
		groupHeight = groupHeight * (numGroups + 1);
	else
		groupWidth = groupWidth * numGroups;
	end
	CenteringRaidProfile_DebugPrint('Group frame size: '..groupWidth..', '..groupHeight);
	
	-- Calculate the anchor point for the resize frame to place the raid container where we want to
	-- (i.e. centered on the default frame).
	local anchorPointX = centerPointX - (groupWidth / 2) - 4;
	local anchorPointY = centerPointY + (groupHeight / 2) + 7;
	if (usingHorizontalGroups) then
		anchorPointY = anchorPointY - (groupHeight / (numGroups + 1) / 2);
	end
	CenteringRaidProfile_DebugPrint('Calculated anchor point: '..anchorPointX..', '..anchorPointY);

	return anchorPointX, anchorPointY, groupWidth, groupHeight;
end


function CenteringRaidProfile_GetNumVisibleRaidGroups()
	local numGroups = 0;
	local numPlayers = 0;
	local playerSubgroup = 0;
	
	local isInRaid = IsInRaid();
	local isInGroup = IsInGroup();
	if (isInRaid) then
		-- Arrays in Lua are just numerically indexed tables, so I need to manually initialize them.
		local numMembersPerGroup = {};
		for i = 1, NUM_RAID_GROUPS do
			numMembersPerGroup[i] = 0;
		end
		
		-- Loop through all the group members to determine how many people are in each subgroup.
		for i = 1, MAX_RAID_MEMBERS do
			local name, _, groupNumber = GetRaidRosterInfo(i);
			if (name ~= nil) then
				numMembersPerGroup[groupNumber] = numMembersPerGroup[groupNumber] + 1;
				numPlayers = numPlayers + 1;
				
				-- While we are here, we also try to locate the player's group, since we can
				-- reliably use it to grab a group frame later on (because we know it's
				-- impossible for that group to be empty since the player is in there).
				if (UnitName('player') == name) then
					playerSubgroup = groupNumber;
				end
			end
		end
		
		-- Count the number of non-empty groups.
		for i = 1, NUM_RAID_GROUPS do
			if (numMembersPerGroup[i] > 0) then
				numGroups = numGroups + 1;
			end
		end
	elseif (isInGroup) then
		-- If the player is not in a raid but is 'in a group', then the player is in a party.
		numGroups = 1;
	end
	
	return numGroups, numPlayers, playerSubgroup;
end


function CenteringRaidProfile_ToBoolean(value)
	assert(type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean', 'Cannot convert type to boolean.')
	if type(value) == 'string' then
		value = value:lower();
		value = value:gsub('^%s*(.-)%s*$', '%1'); -- equivalent to trim()
	end
	
	if value == 'true' or value == 'yes' or value == 'on' or (type(value) == 'number' and value ~= 0) or value == true then
		return true;
	elseif value == 'false' or value == 'no' or value == 'off' or (type(value) == 'number' and value == 0) or value == false then
		return false;
	else
		error('Cannot convert value to boolean.');
	end
end


function CenteringRaidProfile_DebugPrint(message)
	local isLogging = CenteringRaidProfileSettings[CENTERING_RAID_PROFILE_SETTING_DEBUG_LOGGING];
	if (isLogging == true) then
		print('['..ADDON_NAME..'] '..message);
	end
end
