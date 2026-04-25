#!/usr/bin/env python3
import datetime
import json
import os
import sys
# Include the virtual environment site-packages in sys.path
here = os.path.dirname(os.path.realpath(__file__))
if not os.path.exists(os.path.join(here, '.venv')):
	print('Python environment not setup')
	exit(1)
sys.path.insert(
	0,
	os.path.join(
		here,
		'.venv',
		'lib',
		'python' + '.'.join(sys.version.split('.')[:2]), 'site-packages'
	)
)
import shutil
import zipfile
from SystemdUnitParser import SystemdUnitParser
from warlock_manager.apps.steam_app import SteamApp
from warlock_manager.libs.cmd import Cmd
from warlock_manager.services.rcon_service import RCONService
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.config.unreal_config import UnrealConfig
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs import utils
from warlock_manager.libs.proton import get_proton_paths
from warlock_manager.libs.download import download_json, download_file
from warlock_manager.libs.logger import logger
from warlock_manager.formatters.cli_formatter import cli_formatter
from warlock_manager.mods.warlock_nexus_mod import WarlockNexusMod
# To allow running as a standalone script without installing the package, include the venv path for imports.
# This will set the include path for this path to .venv to allow packages installed therein to be utilized.
#
# IMPORTANT - any imports that are needed for the script to run must be after this,
# otherwise the imports will fail when running as a standalone script.


# Import the appropriate type of handler for the game installer.
# Common options are:
# from warlock_manager.apps.base_app import BaseApp

# Import the appropriate type of handler for the game services.
# Common options are:
# from warlock_manager.services.base_service import BaseService
# from warlock_manager.services.socket_service import SocketService
# from warlock_manager.services.http_service import HTTPService

# Import the various configuration handlers used by this game.
# Common options are:
# from warlock_manager.config.cli_config import CLIConfig
# from warlock_manager.config.json_config import JSONConfig

# Load the application runner responsible for interfacing with CLI arguments
# and providing default functionality for running the manager.

# If your script manages the firewall, (recommended), import the Firewall library

# Utilities provided by Warlock that are common to many applications

# Useful in some games

# Select the baseline for mod support
# from warlock_manager.mods.base_mod import BaseMod


class GameMod(WarlockNexusMod):
	_library = None

	@classmethod
	def get_mod(cls, source: 'GameService', provider: str | None, mod_id: str | int) -> 'GameMod | None':
		"""
		Get a specific mod by ID

		:param source:   Source game service to use for reference
		:param provider: Mod provider, e.g. 'curseforge'
		:param mod_id:   Mod ID
		:return:
		"""

		# Search through the game database first.
		library_mods = cls.get_library_mods()
		for mod in library_mods:
			if mod.id == int(mod_id) and mod.provider == provider:
				return mod

		# If no mod found locally, default to upstream support
		return super().get_mod(source, provider, mod_id)

	@classmethod
	def get_library_mods(cls) -> list['GameMod']:
		"""
		Pull the list of mods from the library file within ARK

		:return:
		"""
		if cls._library is None:
			cls._library = []

			# Pull mod data from the JSON library file
			lib_file = os.path.join(utils.get_base_directory(), 'AppFiles', 'ShooterGame', 'Binaries', 'Win64', 'ShooterGame', 'ModsUserData', '83374', 'library.json')
			if os.path.exists(lib_file):
				with open(lib_file, 'r', encoding='utf-8-sig') as f:
					mod_lib = json.load(f)
					for mod_data in mod_lib['installedMods']:
						mod = GameMod()
						mod.name = mod_data['details']['name']
						mod.description = mod_data['details']['summary']
						mod.url = mod_data['details']['links']['websiteUrl']
						mod.info_url = mod_data['details']['links']['wikiUrl']
						mod.id = mod_data['details']['iD']
						mod.provider = 'curseforge'
						if len(mod_data['details']['authors']) > 0:
							mod.author = mod_data['details']['authors'][0]['name']
						mod.icon = mod_data['details']['logo']['thumbnailUrl']

						cls._library.append(mod)

		return cls._library


class GameAPIException(Exception):
	pass


class GameApp(SteamApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'ARK:SA'
		self.desc = 'ARK: Survival Ascended'
		self.steam_id = '2430930'
		#self.steam_id = '90'  # TESTING - Use Half-Life Dedicated Server since it's only 90MB
		self.service_prefix = 'ark-'
		self.service_handler = GameService
		self.mod_handler = GameMod

		self.configs = {
			'game': UnrealConfig(
				'game',
				os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Saved/Config/WindowsServer/Game.ini')
			),
			'gus': UnrealConfig(
				'gus',
				os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini')
			),
			'manager': INIConfig(
				'manager',
				os.path.join(utils.get_base_directory(), '.settings.ini')
			)
		}
		self.load()

	def run_migrations(self):
		"""
		Run any migrations from the Migrations directory
		:return:
		"""
		migrations_path = os.path.join(utils.get_base_directory(), 'Migrations')
		if not os.path.exists(migrations_path):
			return

		migrations = []
		for filename in os.listdir(migrations_path):
			if filename.startswith('_app.') and filename.endswith('.json'):
				migration_file = os.path.join(migrations_path, filename)
				migration_data = []
				try:
					with open(migration_file, 'r', encoding='utf-8') as f:
						migration_data = json.load(f)
				except Exception as e:
					logger.error('Failed to load migration file for game: %s' % e)
					continue

				for option in migration_data:
					try:
						self.set_option(option['option'], option['value'])
					except Exception as e:
						logger.error('Failed to migrate option %s for game: %s' % (option['name'], e))

				migrations.append(migration_file)

		# Move the migrated files to mark them as completed
		for file in migrations:
			os.rename(file, file[:-5] + '.migrated')

	def first_run(self) -> bool:

		# Update with Steam (or install on first install)
		self.update()

		# Run migrations for the application
		self.run_migrations()

		services = self.get_services()
		if len(services) == 0:
			# No services exist, auto-create the various maps supported for convenience.
			community_name = self.get_option_value('Community Name')
			maps = {
				'ark-island': ('TheIsland_WP', []),
				'ark-aberration': ('Aberration_WP', []),
				'ark-club': ('BobsMissions_WP', ['1005639']),
				'ark-scorched': ('ScorchedEarth_WP', []),
				'ark-thecenter': ('TheCenter_WP', []),
				'ark-extinction': ('Extinction_WP', []),
				'ark-astraeos': ('Astraeos_WP', []),
				'ark-ragnarok': ('Ragnarok_WP', []) ,
				'ark-valguero': ('Valguero_WP', []),
				'ark-lostcolony': ('LostColony_WP', [])
			}
			for map_name in maps.keys():
				logger.info('Creating service for map %s' % (map_name,))
				svc = self.create_service(map_name)
				svc.set_option('Map Name', maps[map_name][0])
				svc.set_option('Session Name', '%s (%s)' % (community_name, svc.get_map_label()))
				if len(maps[map_name][1]) > 0:
					svc.set_option('Mods', ','.join(maps[map_name][1]))
			return True
		else:
			# Import any legacy configurations from the previous installation
			# This is required because between 1.0 and 2.2, breaking changes were implemented in CLI params
			for svc in self.get_services():
				# Run any migrations for this service
				svc.run_migrations()

				# Just rebuild systemd to ensure it's updated
				svc.build_systemd_config()
				svc.reload()
		return False

	def get_option_options(self, option: str):
		"""
		Get the list of possible options for a configuration option
		:param option:
		:return:
		"""
		if option == 'Default Proton Path':
			return get_proton_paths()
		elif option == 'ASA API Loader':
			return self.get_asa_api_loader_versions()
		else:
			return super().get_option_options(option)

	def option_value_updated(self, option: str, previous_value, new_value) -> bool | None:
		"""
		Handle any special actions needed when an option value is updated

		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""
		if option == 'Default Cluster ID':
			# Update any service with the old value to the new one.
			# Do NOT change any service with a different cluster ID, as the user may have changed that explicitly.
			for svc in self.get_services():
				if svc.get_option_value('Cluster ID') == previous_value:
					svc.set_option('Cluster ID', new_value)
			return True
		elif option == 'Default Proton Path':
			# Update the Proton path in the service config
			for svc in self.get_services():
				if svc.get_option_value('Proton Path') == previous_value:
					svc.set_option('Proton Path', new_value)
			return True
		elif option == 'Community Name':
			if self.get_option_value('Joined Session Name'):
				for svc in self.get_services():
					svc.set_option('Session Name', '%s (%s)' % (new_value, svc.get_map_label()))
				return True

		return None

	def get_asa_api_loader_versions(self) -> list:
		"""
		Get the list of versions available for the ASA API Loader
		:return:
		"""
		versions = ["None"]
		url = "https://api.github.com/repos/ArkServerApi/AsaApi/releases"
		data = download_json(url)
		for release in data:
			versions.append(release['tag_name'])
		return versions

	def get_latest_asa_api_loader(self) -> str | None:
		"""
		Get the latest ASA API Loader version
		:return:
		"""
		url = "https://api.github.com/repos/ArkServerApi/AsaApi/releases"
		data = download_json(url)
		for release in data:
			return release['tag_name']
		return None

	def download_asa_api_loader(self):
		"""
		Download and install ASA API Loader

		:return:
		"""

		version = self.get_option_value('ASA API Loader')
		if version == 'None':
			version = self.get_latest_asa_api_loader()
			if version is None:
				raise GameAPIException('Unable to determine latest ASA API Loader version')
			# Store this in the config so the operator knows the version used.
			self.set_option('ASA API Loader', version)

		url = f"https://github.com/ArkServerApi/AsaApi/releases/download/{version}/AsaApi_{version}.zip"
		zip = os.path.join(utils.get_base_directory(), 'Packages', f"AsaApi_{version}.zip")
		target_path = os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Binaries/Win64/')
		download_file(url, zip)
		with zipfile.ZipFile(zip, 'r') as zip_ref:
			zip_ref.extractall(target_path)

	def ensure_asa_api_loader(self):
		"""
		Ensure the ASA API Loader is installed and ready to use
		:return:
		"""
		version = self.get_option_value('ASA API Loader')
		if version == 'None':
			# Not set yet, the download will handle everything.
			self.download_asa_api_loader()
		else:
			# Version is set, double check that it's available
			zip = os.path.join(utils.get_base_directory(), 'Packages', f"AsaApi_{version}.zip")
			target = os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Binaries/Win64/AsaApiLoader.exe')
			if not (os.path.exists(zip) and os.path.exists(target)):
				# Either not downloaded or not extracted yet.
				self.download_asa_api_loader()

	def get_proton_path(self) -> str | None:
		"""
		Get the path to Proton as configured.
		:return:
		"""
		proton_path = self.get_option_value('Default Proton Path')
		if proton_path:
			return proton_path
		else:
			# It's not set yet!  Just return the first one found.
			paths = get_proton_paths()
			return paths[0] if len(paths) > 0 else None

	def post_update(self):
		"""
		Perform any post-update actions needed for this game

		Called immediately after an update is performed but before services are restarted.

		:return:
		"""
		# Version 74.24 released on Nov 4th 2025 with the comment "Fixed a crash" introduces a serious bug
		# that causes the game to segfault when attempting to load the Steam API.
		# Being Wildcard, they don't actually provide any reason as to why they're using the Steam API for an Epic game,
		# but it seems to work without the Steam library available.
		#
		# In the logs you will see:
		# Initializing Steam Subsystem for server validation.
		# Steam Subsystem initialized: FAILED
		#
		check_path = os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Binaries/Win64/steamclient64.dll')
		if os.path.exists(check_path):
			print('Removing broken Steam library to fix build 74.24 crash...')
			os.remove(check_path)

		# As discovered by Deciphersoul; the update 77.34 released on Dec 24 2025 caused an issue with some Debian
		# servers, notably Debian 12, and when using certain mods.
		# The fix is to download the Microsoft XAudio2 Redist package and extract the required DLLs.
		#
		# https://github.com/Acekorneya/Ark-Survival-Ascended-Server/issues/116
		print('Installing Microsoft XAudio2 Redist DLL to fix build 77.34 crash...')
		xaudio_src = 'https://www.nuget.org/api/v2/package/Microsoft.XAudio2.Redist/1.2.11'
		xaudio_dest = os.path.join(utils.get_base_directory(), 'Packages/Microsoft.XAudio2.Redist.zip')
		dll_dest = os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Binaries/Win64/xaudio2_9.dll')
		download_file(xaudio_src, xaudio_dest)
		with zipfile.ZipFile(xaudio_dest, 'r') as zip_ref:
			for file in zip_ref.namelist():
				if file.endswith('release/bin/x64/xaudio2_9redist.dll'):
					zip_ref.extract(file, dll_dest)
		utils.ensure_file_ownership(dll_dest)


class GameService(RCONService):
	"""
	Game service manager
	"""
	def __init__(self, service: str, game: GameApp):
		super().__init__(service, game)

		self.configs = {
			'service': INIConfig('service', os.path.join(utils.get_base_directory(), 'Configs', 'service.%s.ini' % self.service))
		}

		self.bulk = False
		"""
		Set to True to skip rebuilding systemd on every change; useful for bulk operations
		"""

	def create_service(self):
		"""
		Create the systemd service for this game, including the service file and environment file
		:return:
		"""
		self.bulk = True
		super().create_service()

		if self.game.get_option_value('Default New Save Format'):
			# This triggers the new save options for a single database.
			# https://ark.wiki.gg/wiki/2023_official_server_save_files
			self.set_option('Use Store', True)
			self.set_option('New Save Format', True)

		# New instances should by default share the group cluster.
		self.set_option('Cluster ID', self.game.get_option_value('Default Cluster ID'))

		# New instances should use a separate save directory to allow the same map to run on separate instances
		self.set_option('Alt Save Directory', self.service)

		# New instances need the proton prefix
		proton_prefix = self.game.get_option_value('Default Proton Path')
		if proton_prefix:
			self.set_option('Proton Path', proton_prefix)
		else:
			self.set_option('Proton Path', self.game.get_proton_path())

		# Ensure the prefix exists for this instance.
		prefix_path = os.path.join(utils.get_base_directory(), 'prefixes', self.service)
		prefix_src = os.path.join(
			os.path.dirname(self.get_option_value('Proton Path')),
			'files/share/default_pfx'
		)
		if not os.path.exists(prefix_path):
			shutil.copytree(prefix_src, prefix_path)
			utils.ensure_file_ownership(prefix_path)

		self.build_systemd_config()
		self.reload()
		self.bulk = False

	def run_migrations(self):
		"""
		Run any migrations from the Migrations directory
		:return:
		"""
		migrations_path = os.path.join(utils.get_base_directory(), 'Migrations')
		if not os.path.exists(migrations_path):
			return

		self.bulk = True
		migrations = []
		for filename in os.listdir(migrations_path):
			if filename.startswith(f"{self.service}.") and filename.endswith('.json'):
				migration_file = os.path.join(migrations_path, filename)
				migration_data = []
				try:
					with open(migration_file, 'r', encoding='utf-8') as f:
						migration_data = json.load(f)
				except Exception as e:
					logger.error('Failed to load migration file for service %s: %s' % (self.service, e))
					continue

				for option in migration_data:
					try:
						self.set_option(option['option'], option['value'])
					except Exception as e:
						logger.error('Failed to migrate option %s for service %s: %s' % (option['name'], self.service, e))

				migrations.append(migration_file)

		# Move the migrated files to mark them as completed
		for file in migrations:
			os.rename(file, file[:-5] + '.migrated')

		self.build_systemd_config()
		self.reload()
		self.bulk = False

	def get_environment(self) -> dict:
		"""
		Get the environment variables for this service as a dictionary

		:return:
		"""
		ret = {
			'XDG_RUNTIME_DIR': '/run/user/%s' % utils.get_app_uid(),
			'STEAM_COMPAT_CLIENT_INSTALL_PATH': os.path.join(utils.get_home_directory(), '.local/share/Steam'),
			'STEAM_COMPAT_DATA_PATH': os.path.join(utils.get_base_directory(), 'prefixes', self.service),
			'PROTON_USE_XALIA': 0
		}
		if self.get_option_value('Mod Loader') != 'None':
			ret['DISPLAY'] = ':99'

		return ret

	def get_binary(self) -> str:
		return 'AsaApiLoader.exe' if self.get_option_value('Mod Loader') == 'ASA API Loader' else 'ArkAscendedServer.exe'

	def get_executable(self) -> str:
		"""
		Get the full executable for this game service
		:return:
		"""

		proton_path = self.get_option_value('Proton Path')
		if not proton_path:
			# This needs something, so try to pull whatever path is available from the game manager.
			proton_path = self.game.get_proton_path()

		if not proton_path:
			logger.error('Unable to determine Proton path for %s' % self.service)
			return '/bin/false'

		binary = self.get_binary()
		map_name = self.get_option_value('Map Name')
		options = cli_formatter(self.configs['service'], 'option', prefix='', sep='=', joiner='?')
		if map_name:
			options = map_name + '?listen?' + options
		flags = cli_formatter(self.configs['service'], 'flag', prefix='-', sep='=', joiner=' ')

		return ' '.join([
			proton_path,
			'run',
			binary,
			options,
			flags
		])

	def get_systemd_config(self) -> SystemdUnitParser:
		"""
		Get the systemd unit configuration for this service, if available
		:return:
		"""
		config = super().get_systemd_config()

		# We need to change the working directory of this game to be in binaries
		config['Service']['WorkingDirectory'] = os.path.join(utils.get_base_directory(), 'AppFiles/ShooterGame/Binaries/Win64')

		return config

	def get_option_options(self, option: str):
		"""
		Get the list of possible options for a configuration option
		:param option:
		:return:
		"""
		if option == 'Proton Path':
			return get_proton_paths()
		else:
			return super().get_option_options(option)

	def option_value_updated(self, option: str, previous_value, new_value) -> bool | None:
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""
		success = None
		rebuild_env = False

		# Special option actions
		if option == 'Port':
			# Update firewall for game port change
			if previous_value:
				Firewall.remove(int(previous_value), 'udp')
			Firewall.allow(int(new_value), 'udp', '%s game port - %s' % (self.game.name, self.get_map_label()))
			success = True
		elif option == 'Mod Loader':
			if new_value == 'ASA API Loader':
				self.game.ensure_asa_api_loader()
			success = True
			rebuild_env = True

		if rebuild_env:
			self.build_environment_file()

		if not self.bulk:
			# Reload the service; all options on services control the systemd service file.
			self.build_systemd_config()
			self.reload()

		return success

	def is_api_enabled(self) -> bool:
		"""
		Check if RCON is enabled for this service
		:return:
		"""
		return (
			self.get_option_value('RCON Port') != '' and
			self.get_option_value('RCON Enabled') and
			self.get_option_value('Server Admin Password') != ''
		)

	def get_api_port(self) -> int:
		"""
		Get the RCON port from the service configuration
		:return:
		"""
		return self.get_option_value('RCON Port')

	def get_api_password(self) -> str:
		"""
		Get the RCON password from the service configuration
		:return:
		"""
		return self.get_option_value('Server Admin Password')

	def get_player_max(self) -> int | None:
		"""
		Get the maximum player count on the server, or None if the API is unavailable
		:return:
		"""
		if self.option_has_value('Win Live Max Players'):
			return self.get_option_value('Win Live Max Players')
		else:
			return 70

	def get_player_count(self) -> int | None:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		ret =  self.cmd('ListPlayers')
		if ret is None:
			return None
		elif ret == 'No Players Connected':
			return 0
		else:
			return len(ret.split('\n'))

	def get_save_directory(self):
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(utils.get_base_directory(), 'AppFiles', 'ShooterGame', 'Saved')

	def get_save_files(self):
		ret = ['clusters']

		alt_save_dir = self.get_option_value('Alt Save Directory')
		map_name = self.get_option_value('Map Name')

		if map_name == 'BobsMissions_WP':
			map_name = 'BobsMissions'

		if alt_save_dir:
			base_path = os.path.join(alt_save_dir, map_name)
			check_path = os.path.join(self.get_save_directory(), alt_save_dir, map_name)
			logger.debug('Using alternate save directory: %s' % check_path)
		else:
			base_path = os.path.join('SavedArks', map_name)
			check_path = os.path.join(self.get_save_directory(), 'SavedArks', map_name)
			logger.debug('Using default save directory: %s' % check_path)

		if os.path.exists(check_path):
			for file in os.listdir(check_path):
				if file.endswith('bak'):
					# Skip backups
					continue
				if '_WP_0' in file or '_WP_1' in file:
					# More backups to skip
					continue
				ret.append(os.path.join(base_path, file))
		else:
			logger.debug('Save directory does not exist: %s' % check_path)
		return ret

	def save_world(self):
		"""
		Issue a Save command on the server
		:return:
		"""
		self.cmd('SaveWorld')

	def send_message(self, message: str):
		"""
		Send a message to the game server
		:param message:
		:return:
		"""
		self.cmd('ServerChat %s' % message)

	def get_pids(self) -> list:
		"""
		Get all process IDs for this game instance
		:return:
		"""

		# There's no quick way to get the game process PID from systemd,
		# so use ps to find the process based on the map name
		pids = [self.get_pid()]
		binary = self.get_binary()
		map_name = self.get_option_value('Map Name')
		session_name = self.get_option_value('Session Name')
		command = Cmd(['pgrep', '-af', '%s %s' % (binary, map_name)])
		command.is_memory_cacheable(2)
		for line in command.lines:
			if line.strip():
				pid, cmd = line.strip().split(' ', 1)
				if session_name in cmd:
					pids.append(int(pid))

		# This game uses Proton, so networking is handled by the wineserver binary.
		# Check wineservers if their environment is configured to use this instance.
		wineservers = Cmd(['pgrep', 'wineserver']).lines
		for wine_pid in wineservers:
			wine_env_file = '/proc/%s/environ' % wine_pid
			if os.path.exists(wine_env_file):
				with open(wine_env_file, 'r', encoding='utf-8') as f:
					wine_env = f.read()
				if '/prefixes/%s/' % self.service in wine_env:
					pids.append(int(wine_pid))

		return list(set(pids))

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""

		# There's no quick way to get the game process PID from systemd,
		# so use ps to find the process based on the map name
		binary = self.get_binary()
		map_name = self.get_option_value('Map Name')
		session_name = self.get_option_value('Session Name')
		command = Cmd(['pgrep', '-af', '^%s %s' % (binary, map_name)])
		command.is_memory_cacheable(2)
		for line in command.lines:
			if line.strip():
				pid, cmd = line.strip().split(' ', 1)
				if session_name in cmd:
					return pid
		return 0

	def get_map_label(self) -> str:
		"""
		Get the label of the map
		:return:
		"""
		map_name = self.get_option_value('Map Name')
		if map_name == 'BobsMissions_WP':
			return 'Club'
		elif map_name is None or map_name == '':
			return self.service
		elif map_name.endswith('_WP'):
			return map_name[:-3]
		else:
			return map_name

	def get_enabled_mods(self) -> list['GameMod']:
		"""
		Get all enabled mods that are locally available on this service

		:return:
		"""

		# This game stores mods in a configuration parameter, so pull them from that.
		enabled_mod_ids = self.get_option_value('Mods').split(',')
		enabled_mod_ids = [m.strip() for m in enabled_mod_ids if m.strip() != '']
		enabled_mods = []
		for mod_id in enabled_mod_ids:
			mod = GameMod.get_mod(self, 'curseforge', mod_id)
			if mod is not None:
				enabled_mods.append(mod)

		return enabled_mods

	def add_mod(self, mod: 'GameMod', force: bool = False) -> bool:
		"""
		Enable a mod for this service

		:param mod_id:
		:param force:
		:return:
		"""
		if not self.is_stopped():
			logger.error('Cannot add mods to a running service!')
			return False

		mods = self.get_option_value('Mods').split(',')
		mods = [m.strip() for m in mods if m.strip() != '']

		if mod.id in mods:
			logger.warning('Mod %s is already enabled on this service!' % (mod.id, ))
			return True

		mods.append(str(mod.id))
		self.set_option('Mods', ','.join(mods))
		logger.info('Enabled mod %s on service %s' % (mod.id, self.service))
		return True

	def remove_mod(self, mod: 'BaseMod') -> bool:
		"""
		Disable a mod for this service

		:param mod_id:
		:return:
		"""
		if not self.is_stopped():
			logger.error('Cannot remove mods from a running service!')
			return False

		mods = self.get_option_value('Mods').split(',')
		mods = [m.strip() for m in mods if m.strip() != '']

		if str(mod.id) not in mods:
			logger.warning('Mod %s is not enabled on this service!' % (mod.id, ))
			return False

		mods.remove(str(mod.id))
		self.set_option('Mods', ','.join(mods))
		logger.info('Disabled mod %s on service %s' % (mod.id, self.service))
		return True

	def get_port_definitions(self) -> list:
		"""
		Get a list of port definitions for this service
		:return:
		"""
		return [
			('Port', 'udp', '%s game port - %s' % (self.game.name, self.get_map_label())),
			('RCON Port', 'tcp', '%s RCON port - %s' % (self.game.name, self.get_map_label()))
		]

	def get_port(self) -> int | None:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		return self.get_option_value('Port')

	def get_name(self) -> str:
		"""
		Get the name of this game server instance
		:return:
		"""
		return self.get_option_value('Session Name')

if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
