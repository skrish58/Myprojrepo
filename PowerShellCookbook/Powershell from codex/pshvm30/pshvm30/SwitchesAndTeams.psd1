# culture=“en-US”
ConvertFrom-StringData @'
	Copyright = Copyright 2013 Altaro Software
	MainMenuTitle = Switches and Teams Manipulation Script
	MainTeamTitle = Main Team Menu
	AdapterListTitle = Available Adapters
	TeamingModeTitle = Teaming Mode
	TeamDeleteTitle = Team Deletion
	LBATitle = Load Balancing Algorithm
	MainSwitchTitle = Main Switch Menu
	SwitchQoSTitle = Quality of Service Mode Selection
	SwitchIOVTitle = SR-IOV Selection
	SwitchDeletionTitle = Switch Deletion
	SetTeamIPTitle = Set IP Address on Team Adapters
	RemoveTeamIPTitle = Remove IP Addressing from Team Adapters
	AddVNTitle = Choose Switch for New Virtual Adapter
	RemoveVNTitle = Remove Virtual Network Adapter
	SetVNIPTitle = Set IP Address for Virtual Adapter
	RemoveVNIPTitle = Remove IP Addressing from Virtual Adapter
	BackMenu = Back
	ExitScript = Exit Script
	SelectOption = Select an option
	WorkWithTeams = Work with teams and team adapters
	WorkWithSwitches = Work with virtual switches and virtual adapters
	NoSwitch = You must enable the Hyper-V role to work with virtual switches and adapters
	CreateTeamOption = Create a team
	DeleteTeamOption = Delete a team
	SetTeamIP = Set IP address on a team adapter
	RemoveTeamIP = Remove IP address from a team adapter (set to DHCP)
	ChooseTeamName = Enter a name for the new team
	ChooseTeamNICName = Enter a name for the team's virtual adapter [Default is {0}]
	LoadingAdapters = Loading adapter list...
	TeamAdapterWarning = Team adapters hosting virtual switches are ineligible for IP
	NoAdaptersSelected = You must select at least one adapter
	ContinueTeamCreation = Finished Selecting Team Members
	TeamingModeLACP = LACP
	TeamingModeStatic = Static
	TeamingModeSwitchIndependent = Switch Independent
	LBAHyperVPorts = Hyper-V Ports
	LBATransportPorts = Transport Ports
	LBAIPAddresses = IP Addresses
	LBAMACAddresses = MAC Addresses
	ConfirmTeamHeader = Confirm Team Creation Settings:
	ConfirmTeamName = Team Name: {0}
	ConfirmTeamNICName = Team NIC Name: {0}
	ConfirmTeamMembers = Members: {0}
	ConfirmTeamMode = Teaming Mode: {0}
	ConfirmTeamLBA = Load-Balancing Algorithm: {0}
	TeamWarning = Continuing WILL interrupt all traffic on these adapters!
	ConfirmTeamConfirmation = Accept these settings and create the team? [Y or N (Default: N)]
	TeamCreationInProgress = Team creation in progress, please wait...
	FailureFinish = Press [Enter] to return to the menu
	LoadingTeams = Loading teams...
	CreateSwitchOption = Create a virtual switch
	DeleteSwitchOption = Delete a virtual switch
	NoTeamsToDelete = No teams to delete
	ChooseSwitchName = Enter a name for the new switch
	ContinueSwitchCreation = None, switch will be internal or private
	SwitchQoSAbsolute = Absolute Values Mode
	SwitchQoSRelative = Relative Weight Mode
	SwitchQoSNone = No QoS
	SwitchQoSWarningPermanent = WARNING: QoS settings are permanent!
	SwitchIOVEnabled = SR-IOV Enabled
	SwitchIOVDisabled = SR-IOV Disabled
	SwitchIOVWarning = WARNING: SR-IOV setting is permanent!\r\n SR-IOV is ignored on physical adapters that do not have IOV support and on all teamed adapters.
	ConfirmSwitchHeader = Confirm Switch Creation Settings:
	ConfirmSwitchName = Switch Name: {0}
	ConfirmSwitchAdapter = Switch hosted on adapter: {0}
	ConfirmSwitchTypeExternal = Switch Type: External
	ConfirmSwitchTypePrivate = Switch Type: Private/Internal
	ConfirmSwitchQoSMode = Switch QoS Mode: {0}
	ConfirmSwitchIOV = Switch SR-IOV: {0}
	SwitchWarning = Continuing WILL end all traffic on this adapter and remove its TCP/IP properties!
	ConfirmSwitchConfirmation = Accept these settings and create the switch? [Y or N (Default: N)]
	SwitchCreationInProgress = Switch creation in progress, please wait...
	LoadingSwitches = Loading switches...
	NoSwitchToDelete = No switch to delete
	SwitchDeletionSelect = Enter the number of the switch to delete
	SwitchDeletionWarning = WARNING: Virtual adapters on the switch will be removed!
	AddVN = Add a virtual network adapter
	RemoveVN = Remove a virtual network adapter
	AddingAdapter = Adding adapter {0} to {1}...
	ConfirmVNRemoval = Are you sure you want to remove virtual adapter {0}?\r\n(Y for yes, anything else for no)
	SetVNIP = Set IP address on a virtual adapter
	RemoveVNIP = Remove IP address from a virtual adapter (set to DHCP)
	NewVNName = Name for new virtual adapter
	ClearingInfo = Please wait, resetting IP information...
	EnteringIPForAdapter = Entering IP Information for {0}\r\n
	RequestIP = IP Address (#.#.#.# format)
	RequestSubnetMask = Subnet Mask (#.#.#.# format or 0-32)
	RequestGateway = Default Gateway (#.#.#.# or [Enter] for none)
	RequestDNS = DNS Servers (Comma-separated or [Enter] for none)
	RequestDNSRegister = Register this adapter in DNS? (N for no, anything else for Yes)
	ConfirmIPChange = Check all settings closely! Existing IP information will be lost!\r\nAre you sure you want to continue? (Yes or No)
	InvalidMask = Invalid subnet mask
	SetVNVLAN = Set VLAN ID for a virtual adapter
	EnterVLAN = Enter VLAN ID for {0} (-1 to set to Untagged)
	NoSwitchForVN = No virtual switch available
	NoVNToRemove = No virtual adapters in the management OS to remove
	NoVNForIP = No virtual adapters available
	ShowTeams = Show current teams
	ShowSwitchesAndAdapters = Show Virtual Switches and Adapters
	VirtualSwitchName = Virtual switch name: {0}
	VirtualSwitchType = Virtual switch type: {0}
	VirtualSwitchPhysical = Hosted on physical adapter: {0}
	VirtualSwitchAdapters = Adapters on this switch:
	VirtualSwitchReservationMode = Bandwidth Reservation Mode: {0}
	VirtualSwitchIOVEnabled = SR-IOV Enabled: {0}
	ShowAdapterName = Adapter Name: {0}
	ShowAdapterVLAN = Adapter VLAN: {0}
	Untagged = Untagged
'@