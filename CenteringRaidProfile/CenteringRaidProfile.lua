
----------------
-- PROPERTIES --
----------------

local ADDON_NAME = GetAddOnMetadata('CenteringRaidProfile', 'Title');
local ADDON_VERSION = GetAddOnMetadata('CenteringRaidProfile', 'Version');
local ADDON_INITIALIZED = false;

-- The following properties were pulled from Blizzard's interface code.
-- BCUF refers to Blizzard's Compact Unit Frame and related classes (to remember where I got these numbers).
local BCUF_BORDER_WIDTH = 8;
local BCUF_GROUP_TITLE_HEIGHT = 14;

-- These are the raid profile settings we need to account for when we are positioning the raid frame.
local RAID_PROFILE_OPTION_KEEP_GROUPS_TOGETHER = 'keepGroupsTogether';
local RAID_PROFILE_OPTION_HORIZONTAL_GROUPS = 'horizontalGroups';
local RAID_PROFILE_OPTION_FRAME_WIDTH = 'frameWidth';
local RAID_PROFILE_OPTION_FRAME_HEIGHT = 'frameHeight';
local RAID_PROFILE_OPTION_SHOW_BORDERS = 'displayBorder';

-- The following properties are addon-specific constants and settings.
local CRP_PROFILE_NAME = 'Centering Raid Profile';
local CRP_SETTING_DEBUG_LOGGING = 'DebugLogging';
local CRP_SETTING_ANCHOR_POINT = 'AnchorPoint';
local CRP_SETTING_ANCHOR_POINT_X_PERCENTAGE = 'AnchorPointXPercentage';
local CRP_SETTING_ANCHOR_POINT_Y_PERCENTAGE = 'AnchorPointYPercentage';
local CRP_SETTING_CENTER_ALL_RAID_PROFILES = 'CenterAllRaidProfiles';
local CRP_DEFAULT_SETTINGS = {
	[CRP_SETTING_DEBUG_LOGGING] = false,
	[CRP_SETTING_ANCHOR_POINT] = 'center';
	-- These default percentages should place the raid container horizontally centered and roughly just above
	-- the extra action buttons on screen with Blizzard's default scaling and profile settings.
	[CRP_SETTING_ANCHOR_POINT_X_PERCENTAGE] = 0.50,
	[CRP_SETTING_ANCHOR_POINT_Y_PERCENTAGE] = 0.30,
	[CRP_SETTING_CENTER_ALL_RAID_PROFILES] = false,
};

local crpEnforceConfigurationAfterCombat = false;
local crpUpdateProfileLock = false;
local crpUpdateGroupLock = false;
local crpCombatDetected = false;

-----------------------
-- PRIVATE FUNCTIONS --
-----------------------

local function CenteringRaidProfile_Print(message)
	print('['..ADDON_NAME..'] '..message);
end


local function CenteringRaidProfile_DebugPrint(message)
	local isLogging = CenteringRaidProfileSettings[CRP_SETTING_DEBUG_LOGGING];
	if (isLogging == true) then
		print('['..ADDON_NAME..'] '..message);
	end
end


-- This is a utility function that doesn't actually have anything specific to do with this addon, and it should
-- probably exist in an outside library/module.
local function CenteringRaidProfile_ToBoolean(value)
	assert(type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean', 'Cannot convert type to boolean.')
	if (type(value) == 'string') then
		value = value:lower();
		value = value:gsub('^%s*(.-)%s*$', '%1'); -- equivalent to trim()
	end
	
	if (value == 'true' or value == 'yes' or value == 'on' or (type(value) == 'number' and value ~= 0) or value == true) then
		return true;
	elseif (value == 'false' or value == 'no' or value == 'off' or (type(value) == 'number' and value == 0) or value == false) then
		return false;
	else
		error('Cannot convert value to boolean.');
	end
end


local function CenteringRaidProfile_EnsureSettingsIntegrity()
	if (CenteringRaidProfileSettings == nil) then
		CenteringRaidProfileSettings = CRP_DEFAULT_SETTINGS;
		return;
	end

	for key, _ in pairs(CRP_DEFAULT_SETTINGS) do
		if (CenteringRaidProfileSettings[key] == nil) then
			CenteringRaidProfileSettings[key] = CRP_DEFAULT_SETTINGS[key];
		end
	end
end


local function CenteringRaidProfile_GetWorkingRaidProfile()
	local activeProfile = GetActiveRaidProfile();
	local isCenteringAllProfiles = CenteringRaidProfileSettings[CRP_SETTING_CENTER_ALL_RAID_PROFILES];
	if (isCenteringAllProfiles == true) then	
		return activeProfile;
	else
		return CRP_PROFILE_NAME;
	end
end


local function CenteringRaidProfile_GetNumVisibleRaidGroups()
	local numGroups = 0;
	local numPlayers = 0;
	local playerSubgroup = 0;
	local largestSubgroupCount = 0;
	
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
				
				-- For supporting horizontal groups, we also want to know the largest subgroup
				-- size, in order to properly center the frame if there are less than 5 people
				-- across any single group.
				if (numMembersPerGroup[groupNumber] > largestSubgroupCount) then
					largestSubgroupCount = numMembersPerGroup[groupNumber];
				end
			end
		end
		
		-- Count the number of non-empty groups.
		for i = 1, NUM_RAID_GROUPS do
			if (numMembersPerGroup[i] > 0 and CRF_GetFilterGroup(i)) then
				numGroups = numGroups + 1;
			end
		end
	elseif (isInGroup) then
		-- If the player is not in a raid but is 'in a group', then the player is in a party.
		numGroups = 1;
	end
	
	return numGroups, numPlayers, playerSubgroup, largestSubgroupCount;
end


local function CenteringRaidProfile_GetApproximateCenteredFrameBounds(anchorPoint, anchorX, anchorY, numGroups, largestSubgroupCount)
	-- Calculate the size of the complete raid frame based on the number of visible groups and various
	-- raid profile settings.
	local workingProfile = CenteringRaidProfile_GetWorkingRaidProfile();
	local unitWidth = GetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_FRAME_WIDTH);
	local unitHeight = GetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_FRAME_HEIGHT);
	local usingBorders = GetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_SHOW_BORDERS);
	local usingHorizontalGroups = GetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_HORIZONTAL_GROUPS);
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
		groupWidth = (unitWidth * largestSubgroupCount);
		groupHeight = (unitHeight + BCUF_GROUP_TITLE_HEIGHT) * numGroups;
		if (usingBorders) then
			groupWidth = groupWidth + (BCUF_BORDER_WIDTH * 2);
			groupHeight = groupHeight + (BCUF_BORDER_WIDTH * numGroups);
		end
	end
	
	-- Calculate the anchor point for the resize frame to place the raid container where we want to
	-- (i.e. centered on the default frame).
	local framePointX = anchorX - (groupWidth / 2) - (numGroups + 1);
	local framePointY = anchorY + (groupHeight / 2);
	if (anchorPoint == 'top') then
		framePointY = anchorY;
	end
	CenteringRaidProfile_DebugPrint('Calculated frame point: '..framePointX..', '..framePointY);

	return framePointX, framePointY, groupWidth, groupHeight;
end


local function CenteringRaidProfile_GetAccurateCenteredFrameBounds(anchorPoint, anchorX, anchorY, numGroups, playerSubgroup, largestSubgroupCount)
	-- When a player first joins a group after logging in, the raid group frames are seemingly not loaded right
	-- away, so we need to check to be sure that we can grab the player's group frame before we can continue.
	-- If we can't, we probably just have to wait another second or two at most, but in the meantime, we
	-- approximate the bounds of the raid container.
	local playerGroupFrame = _G['CompactRaidGroup'..playerSubgroup];
	if (playerGroupFrame == nil) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: group frames not fully loaded (swapping to different strategy).');
		return CenteringRaidProfile_GetApproximateCenteredFrameBounds(anchorPoint, anchorX, anchorY, numGroups, largestSubgroupCount);
	end

	-- Calculate the size of the complete raid container based on the number of visible groups, as well as the
	-- size settings of the individual unit frames.
	local groupWidth = playerGroupFrame:GetWidth();
	local groupHeight = playerGroupFrame:GetHeight();
	local workingProfile = CenteringRaidProfile_GetWorkingRaidProfile();
	local usingHorizontalGroups = GetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_HORIZONTAL_GROUPS);
	if (usingHorizontalGroups) then
		-- When using horizontal groups, the container needs an extra group's worth of height in order
		-- to avoid overflow for some reason.  I suspect this is a bug with Blizzard's FlowContainer.
		groupHeight = groupHeight * (numGroups + 1);
	else
		groupWidth = groupWidth * numGroups;
	end
	CenteringRaidProfile_DebugPrint('Group frame size: '..groupWidth..', '..groupHeight);
	
	-- Calculate the anchor point for the resize frame to center the raid container.
	local framePointX = anchorX - (groupWidth / 2) - (BCUF_BORDER_WIDTH / 2);
	local framePointY = anchorY + (groupHeight / 2) + (BCUF_GROUP_TITLE_HEIGHT / 2);
	if (anchorPoint == 'top') then
		framePointY = anchorY;
	end
	if (usingHorizontalGroups) then
		framePointX = anchorX - (((groupWidth / MEMBERS_PER_RAID_GROUP) * largestSubgroupCount) / 2) - (BCUF_BORDER_WIDTH / 2);
		if (anchorPoint == 'center') then
			-- When using horizontal groups, the container needs an extra group's worth of height in order
			-- to avoid overflow for some reason.  I suspect this is a bug with Blizzard's FlowContainer.
			framePointY = framePointY - (groupHeight / (numGroups + 1) / 2);
		end
	end
	CenteringRaidProfile_DebugPrint('Calculated frame point: '..framePointX..', '..framePointY);

	return framePointX, framePointY, groupWidth, groupHeight;
end


local function CenteringRaidProfile_UpdateRaidContainerBounds()
	-- Don't do anything if we are in combat (obviously; though if you reach here while in combat, you've
	-- almost certainly tainted the Blizzard UI already).
	local inCombat = InCombatLockdown();
	if (inCombat == true or crpCombatDetected == true) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: combat lockdown.');
		return;
	end

	-- Don't do anything if the raid profiles are not fully loaded (or you will trigger data loss of ALL the
	-- raid profiles).
	local profilesLoaded = HasLoadedCUFProfiles();
	if (profilesLoaded == false) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: profiles not loaded.');
		return;
	end
	
	-- Don't do anything if the current raid profile is not suppose to be centered.
	local activeProfile = GetActiveRaidProfile();
	local workingProfile = CenteringRaidProfile_GetWorkingRaidProfile();
	if (activeProfile ~= workingProfile) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: profile not active.');
		return;
	end

	-- Don't do anything if the player is not in a group.
	local numGroups, _, playerSubgroup, largestSubgroupCount = CenteringRaidProfile_GetNumVisibleRaidGroups();
	if (numGroups == 0) then
		CenteringRaidProfile_DebugPrint('Failed to update raid frames: no group detected.');
		return;
	end
	CenteringRaidProfile_DebugPrint('Non-empty subgroups: '..numGroups);
	CenteringRaidProfile_DebugPrint('Player subgroup: '..playerSubgroup);
	CenteringRaidProfile_DebugPrint('Largest subgroup count: '..largestSubgroupCount);
	
	-- Determine center point we are aligning the raid frames with.
	local anchorPoint = CenteringRaidProfileSettings[CRP_SETTING_ANCHOR_POINT];
	local anchorX = GetScreenWidth() * CenteringRaidProfileSettings[CRP_SETTING_ANCHOR_POINT_X_PERCENTAGE];
	local anchorY = GetScreenHeight() * CenteringRaidProfileSettings[CRP_SETTING_ANCHOR_POINT_Y_PERCENTAGE];
	CenteringRaidProfile_DebugPrint('Desired anchor/center point: '..anchorX..', '..anchorY);

	-- Get the bounds for the raid container such that it will be centered around the specified point.
	local framePointX, framePointY, groupWidth, groupHeight = CenteringRaidProfile_GetAccurateCenteredFrameBounds(anchorPoint, anchorX, anchorY, numGroups, playerSubgroup, largestSubgroupCount);

	-- The raid container bounds are controlled by the "Resize Frame" that players see when they unlock the raid
	-- container.  We manipulate the Resize Frame to play nice with Blizzard's UI, and to ensure the bounds are
	-- saved correctly in the raid profile so that the resize frame looks reasonable/usable if the player chooses
	-- to stop using this add-on.
	local manager = CompactRaidFrameManager;
	local resizeFrame = manager.containerResizeFrame;
	resizeFrame:ClearAllPoints();
	resizeFrame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', framePointX, framePointY);
	-- Adding in the title height and border width with accounts for the rendering offset that Blizzard does
	-- with the resize frame.  This might be a bug on their side, but I account for it nontheless.
	resizeFrame:SetHeight(groupHeight + BCUF_GROUP_TITLE_HEIGHT + BCUF_BORDER_WIDTH);
	resizeFrame:SetUserPlaced(1);
	CompactRaidFrameManager_ResizeFrame_SavePosition(manager)
	CenteringRaidProfile_DebugPrint('Updated auto-adjusting raid profile position.');
end


local function CenteringRaidProfile_AcquireUpdateGroupLock()
	local canBeAcquired = (crpUpdateGroupLock == false);
	if (canBeAcquired == true) then
		crpUpdateGroupLock = true;
	end
	
	return canBeAcquired;
end


local function CenteringRaidProfile_RelinquishUpdateGroupLock()
	crpUpdateGroupLock = false;
end


local function CenteringRaidProfile_ConfigureRaidProfile()
	-- Don't do anything if we are in combat (obviously; though if you reach here while in combat, you've
	-- almost certainly tainted the Blizzard UI already).
	local inCombat = InCombatLockdown();
	if (inCombat == true or crpCombatDetected == true) then
		CenteringRaidProfile_DebugPrint('Failed to configure raid frames: combat lockdown.');
		return;
	end

	-- Don't do anything if we are in combat (obviously; though if you reach here while in combat, you've
	-- almost certainly tainted the Blizzard UI already).
	local profilesLoaded = HasLoadedCUFProfiles();
	if (profilesLoaded == false) then
		return;
	end
	
	-- Make sure the special raid profile for this add-on exists.
	local profileExists = RaidProfileExists(CRP_PROFILE_NAME);
	if (profileExists == false) then
		local numProfiles = GetNumRaidProfiles();
		local maxNumProfiles = GetMaxNumCUFProfiles();
		if (numProfiles < maxNumProfiles) then
			CreateNewRaidProfile(CRP_PROFILE_NAME);
		else
			CenteringRaidProfile_Print('You have too many raid profiles ('..numProfiles..'); you must remove one in order for this add-on to function.');
		end
	end
	
	local workingProfile = CenteringRaidProfile_GetWorkingRaidProfile();
	
	-- Below we are enforcing certain raid profile options in order for this addon to work.  Note that wrapping
	-- these enforcements in if-statements is necessary in order to avoid stack overflows from hooking
	-- `SaveRaidProfileCopy` (which we do for further enforcement).
	
	-- In order for all this to be manageable as a side project, I am limiting this to only supporting
	-- group-based layouts for the raid profiles.
	local usingGroups = GetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_KEEP_GROUPS_TOGETHER);
	if (usingGroups == false) then
		SetRaidProfileOption(workingProfile, RAID_PROFILE_OPTION_KEEP_GROUPS_TOGETHER, true);
		SaveRaidProfileCopy(workingProfile);
	end
	
	-- It's particularly important to turn off the dynamic container positioning, or it will prevent our
	-- positioning code from working at all.  As a default, we try to align the container to be vaguely
	-- centered on the screen as if it were roughly the size of the Resize Frame graphic (roughly 190
	-- points wide).
	local dynamicPositioning = GetRaidProfileSavedPosition(workingProfile);
	if (dynamicPositioning == true) then
		local screenWidth = GetScreenWidth();
		local screenHeight = GetScreenHeight();
		local topOffset = screenHeight / 2.0;
		local bottomOffset = topOffset + 190;
		local leftOffset = (screenWidth - 190) / 2;
		SetRaidProfileSavedPosition(workingProfile, false, 'TOP', topOffset, 'BOTTOM', bottomOffset, 'LEFT', leftOffset);
	end
	
	CenteringRaidProfile_DebugPrint('Configured auto-positioning raid profile.');
end


-- Even if we don't actually call a Blizzard function, we can still cause taint by simply having a reference to
-- said Blizzard function in an otherwise benign "caller" function, so we use a function wrapper in certain cases
-- to avoid this potential avenue for taint.
local function CenteringRaidProfile_ApplyCurrentRaidProfileSettings()
	CompactUnitFrameProfiles_ApplyCurrentSettings();
end


local function CenteringRaidProfile_AcquireUpdateProfileLock()
	local canBeAcquired = (crpUpdateProfileLock == false);
	if (canBeAcquired == true) then
		crpUpdateProfileLock = true;
	end
	
	return canBeAcquired;
end


local function CenteringRaidProfile_RelinquishUpdateProfileLock()
	crpUpdateProfileLock = false;
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- A note about these functions: I don't think that these functions need to be public for the addon to work.
-- However, these are the main drivers/controllers for the addon, and are designed to be resilient to being called
-- outside of typical addon situations (i.e. debugging).

function CenteringRaidProfile_Initialize()
	-- Only initialize the add-on once.
	if (ADDON_INITIALIZED == true) then
		return;
	end
	
	-- If addon settings are not set to reasonable values, bad things happen.
	CenteringRaidProfile_EnsureSettingsIntegrity();
	
	-- WE SHOULD ONLY DO HOOKS ONCE!!!
	
	-- Hook the following functions in order to enforce certain settings, and to adjust the raid container
	-- as a player adjusts their profile settings (i.e. if the player changes their unit frame width, the raid
	-- container will adjust accordingly).
	hooksecurefunc('SaveRaidProfileCopy', function(profile)
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidProfile();
		else
			crpEnforceConfigurationAfterCombat = true;
		end
	end);
	hooksecurefunc('SetActiveRaidProfile', function(profile)
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidProfile();
		else
			crpEnforceConfigurationAfterCombat = true;
		end
	end);
	hooksecurefunc('CompactUnitFrameProfiles_ApplyCurrentSettings', function(profile)
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidContainer();
		end
	end);
	
	-- Hooking this allows us to update the raid container bounds when a group is toggled (i.e. shown or hidden).
	hooksecurefunc('CompactRaidFrameManager_ToggleGroupFilter', function()
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidContainer();
		end
	end);
	
	ADDON_INITIALIZED = true;
	
	CenteringRaidProfile_DebugPrint('Initialized successfully!');
end


function CenteringRaidProfile_UpdateRaidProfile()
	-- Due to the way we are hooking the Blizzard UI, we need to be careful to avoid stack overflows.
	-- In order to create certain functionality, I had to create an indirect recursive loop when adjusting
	-- raid profile settings, and this lock should prevent the stack overflow.
	local locked = CenteringRaidProfile_AcquireUpdateProfileLock();
	if (not locked) then
		return;
	end
	
	CenteringRaidProfile_ConfigureRaidProfile();
	
	local activeProfile = GetActiveRaidProfile();
	local workingProfile = CenteringRaidProfile_GetWorkingRaidProfile();
	if (GetDisplayedAllyFrames() and activeProfile == workingProfile) then
		CenteringRaidProfile_ApplyCurrentRaidProfileSettings();
	end
	
	crpEnforceConfigurationAfterCombat = false;
	CenteringRaidProfile_RelinquishUpdateProfileLock();
end


function CenteringRaidProfile_UpdateRaidContainer()
	-- Due to the way we are hooking the Blizzard UI, we need to be careful to avoid stack overflows.
	-- Frame updates are usually where the stack overflow end up, so we prevent other updates until we are
	-- completely done with an active update.
	local locked = CenteringRaidProfile_AcquireUpdateGroupLock();
	if (not locked) then
		return;
	end
	
	CenteringRaidProfile_UpdateRaidContainerBounds();
	
	CenteringRaidProfile_RelinquishUpdateGroupLock();
end

-----------------------------
-- ENTRY POINTS / HANDLERS --
-----------------------------

local CONSOLE_COMMAND_TABLE = {
	['status'] = function()
		local message = 'Version '..ADDON_VERSION..' | Status: '
		if (ADDON_INITIALIZED == true) then
			message = message..'Active!';
		else
			message = message..'INACTIVE!';
		end
		CenteringRaidProfile_Print(message);
	end,
	['help'] = 'Available console functions: help, status, anchorpoint <center | top>, anchorx | anchory <percentage between 0.15 and 0.85>',
	['debug'] = function(enabled)
		local boolValue = CenteringRaidProfile_ToBoolean(enabled);
		CenteringRaidProfileSettings[CRP_SETTING_DEBUG_LOGGING] = boolValue;
		
		local message = 'Debug output: ';
		if (boolValue) then
			message = message .. 'enabled!';
		else
			message = message .. 'disabled.';
		end
		CenteringRaidProfile_Print(message);
	end,
	['anchorpoint'] = function(point)
		point = point:lower();
		point = point:gsub('^%s*(.-)%s*$', '%1'); -- trim
		if (point == 'top' or point == 'center') then
			CenteringRaidProfileSettings[CRP_SETTING_ANCHOR_POINT] = point;
			CenteringRaidProfile_Print('Anchor point saved: '..point..'.');
		
			local inCombat = InCombatLockdown();
			if (inCombat == false or crpCombatDetected == false) then
				CenteringRaidProfile_UpdateRaidContainer();
			else
				CenteringRaidProfile_Print('Raid container position will be updated after combat.');
			end
		else
			CenteringRaidProfile_Print('Invalid anchor point \''..point..'\'.  Anchor point can only be the \'center\' or \'top\' of the raid container.');
		end
	end,
	['anchorx'] = function(percentage)
		local basePercentage = tonumber(percentage);
		if (basePercentage) then
			local finalPercentage = math.min(math.max(basePercentage, 0.15), 0.85);
			CenteringRaidProfileSettings[CRP_SETTING_ANCHOR_POINT_X_PERCENTAGE] = finalPercentage;
			CenteringRaidProfile_Print('Anchor X position saved: '..finalPercentage..'.');
			
			local inCombat = InCombatLockdown();
			if (inCombat == false or crpCombatDetected == false) then
				CenteringRaidProfile_UpdateRaidContainer();
			else
				CenteringRaidProfile_Print('Raid container position will be updated after combat.');
			end
		else
			CenteringRaidProfile_Print('Invalid value \''..percentage..'\' for anchorx.  Please specify a percentage between 0.15 and 0.85.');
		end
	end,
	['anchory'] = function(percentage)
		local basePercentage = tonumber(percentage);
		if (basePercentage) then
			local finalPercentage = math.min(math.max(basePercentage, 0.15), 0.85);
			CenteringRaidProfileSettings[CRP_SETTING_ANCHOR_POINT_Y_PERCENTAGE] = finalPercentage;
			CenteringRaidProfile_Print('Anchor Y position saved: '..finalPercentage..'.');
			
			local inCombat = InCombatLockdown();
			if (inCombat == false or crpCombatDetected == false) then
				CenteringRaidProfile_UpdateRaidContainer();
			else
				CenteringRaidProfile_Print('Raid container position will be updated after combat.');
			end
		else
			CenteringRaidProfile_Print('Invalid value \''..percentage..'\' for anchorx.  Please specify a percentage between 0.15 and 0.85.');
		end
	end,
	['allprofiles'] = function(enabled)
		local boolValue = CenteringRaidProfile_ToBoolean(enabled);
		CenteringRaidProfileSettings[CRP_SETTING_CENTER_ALL_RAID_PROFILES] = boolValue;
		
		local message = 'Centering ALL raid profiles: ';
		if (boolValue) then
			message = message .. 'enabled!';
		else
			message = message .. 'disabled.';
		end
		CenteringRaidProfile_Print(message);
		
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidProfile();
			CenteringRaidProfile_UpdateRaidContainer();
		else
			crpEnforceConfigurationAfterCombat = true;
		end
	end,
}


-- Note that, even though this is a private function, I include it with the other handlers since it's essentially
-- a Blizzard-specific handler; it's just hooked differently from the other handlers (see the "OnLoad" function).
local function CenteringRaidProfile_OnConsoleCommand(message, commandTable)
	local command, parameters = strsplit(' ', message, 2);
	local entry = commandTable[command:lower()];
	local which = type(entry);
	
	if (which == 'function') then
		entry(parameters)
	elseif (which == 'table') then
		CenteringRaidProfile_OnConsoleCommand(parameters or '', entry);
	elseif (which == 'string') then
		CenteringRaidProfile_Print(entry);
	elseif (message ~= 'help') then
		CenteringRaidProfile_OnConsoleCommand('help', commandTable);
	end
end


function CenteringRaidProfile_OnLoad(self)
	self:RegisterEvent('PLAYER_LOGIN');
	self:RegisterEvent('COMPACT_UNIT_FRAME_PROFILES_LOADED');
	self:RegisterEvent('PLAYER_REGEN_ENABLED');
	self:RegisterEvent('PLAYER_REGEN_DISABLED');
	self:RegisterEvent('GROUP_ROSTER_UPDATE');
	
	SLASH_CENTERING_RAID_PROFILE1 = '/crp';
	SlashCmdList['CENTERING_RAID_PROFILE'] = function(message)
		CenteringRaidProfile_OnConsoleCommand(message, CONSOLE_COMMAND_TABLE);
	end;
end


function CenteringRaidProfile_OnEvent(self, event, ...)
	if (event == 'PLAYER_LOGIN') then
		CenteringRaidProfile_Initialize();
	elseif (event == 'COMPACT_UNIT_FRAME_PROFILES_LOADED') then
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidProfile();
		else
			crpEnforceConfigurationAfterCombat = true;
		end
	elseif (event == 'GROUP_ROSTER_UPDATE') then
		local inCombat = InCombatLockdown();
		if (inCombat == false or crpCombatDetected == false) then
			CenteringRaidProfile_UpdateRaidContainer();
		end
	elseif (event == 'PLAYER_REGEN_ENABLED') then
		crpCombatDetected = false;
		if (crpEnforceConfigurationAfterCombat == true) then
			CenteringRaidProfile_UpdateRaidProfile();
		end
		CenteringRaidProfile_UpdateRaidContainer();
	elseif (event == 'PLAYER_REGEN_DISABLED') then
		crpCombatDetected = true;
	end
end

-- Author note: my personal defaults are:
-- -- default UI scaling
-- -- 80 width raid unit frame
-- -- 40 height raid unit frame
-- -- anchory .3115 if anchor center
-- -- anchory .4065 if anchor top
-- -- allprofiles on
