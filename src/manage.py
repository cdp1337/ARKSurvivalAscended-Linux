#!/usr/bin/env python3
import os

# To allow running as a standalone script without installing the package, include the venv path for imports.
# This will set the include path for this path to .venv to allow packages installed therein to be utilized.
#
# IMPORTANT - any imports that are needed for the script to run must be after this,
# otherwise the imports will fail when running as a standalone script.
# import:org_python/venv_path_include.py

import logging
import zipfile

# Import the appropriate type of handler for the game installer.
# Common options are:
# from warlock_manager.apps.base_app import BaseApp
from warlock_manager.apps.steam_app import SteamApp

# Import the appropriate type of handler for the game services.
# Common options are:
# from warlock_manager.services.base_service import BaseService
from warlock_manager.services.rcon_service import RCONService
# from warlock_manager.services.socket_service import SocketService
# from warlock_manager.services.http_service import HTTPService

# Import the various configuration handlers used by this game.
# Common options are:
# from warlock_manager.config.cli_config import CLIConfig
from warlock_manager.config.ini_config import INIConfig
# from warlock_manager.config.json_config import JSONConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.config.unreal_config import UnrealConfig

# Load the application runner responsible for interfacing with CLI arguments
# and providing default functionality for running the manager.
from warlock_manager.libs.app_runner import app_runner

# If your script manages the firewall, (recommended), import the Firewall library
from warlock_manager.libs.firewall import Firewall

# Utilities provided by Warlock that are common to many applications
from warlock_manager.libs import utils
from warlock_manager.libs.proton import get_proton_paths
from warlock_manager.libs.download import download_json, download_file

# Useful in some games
from warlock_manager.formatters.cli_formatter import cli_formatter

# Select the baseline for mod support
# from warlock_manager.mods.base_mod import BaseMod
from warlock_manager.mods.warlock_nexus_mod import WarlockNexusMod


class ModLibrary(object):
	_mods = None

	@classmethod
	def refresh_data(cls):
		"""
		Force refresh of mod data from disk
		:return:
		"""
		ModLibrary._mods = None

	@classmethod
	def get_mods(cls) -> dict:
		if cls._mods is None:
			cls._mods = {}
			# Pull mod data from the JSON library file
			lib_file = os.path.join(here, 'AppFiles', 'ShooterGame', 'Binaries', 'Win64', 'ShooterGame', 'ModsUserData', '83374', 'library.json')
			if os.path.exists(lib_file):
				with open(lib_file, 'r', encoding='utf-8-sig') as f:
					mod_lib = json.load(f)
					for mod in mod_lib['installedMods']:
						cls._mods[str(mod['details']['iD'])] = {
							'name': mod['details']['name'],
							'path': mod['pathOnDisk']
						}

		return cls._mods

	@classmethod
	def resolve_mod_name(cls, mod_id) -> Union[str, None]:
		mods = cls.get_mods()
		if mod_id in mods:
			return mods[mod_id]['name']
		return None


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
		self.service_prefix = 'ark-'

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

	def first_run(self) -> bool:
		services = self.get_services()
		if len(services) == 0:
			# No services exist, auto-create the various maps supported for convenience.
			maps = {
				'ark-island': ('Island', 'TheIsland_WP', []),
				'ark-aberration': ('Aberration', 'Aberration_WP', []),
				'ark-club': ('Club', 'BobsMissions_WP', ['1005639']),
				'ark-scorched': ('Scorched', 'ScorchedEarth_WP', []),
				'ark-thecenter': ('The Center', 'TheCenter_WP', []),
				'ark-extinction': ('Extinction', 'Extinction_WP', []),
				'ark-astraeos': ('Astraeos', 'Astraeos_WP', []),
				'ark-ragnarok': ('Ragnarok', 'Ragnarok_WP', []) ,
				'ark-valguero': ('Valguero', 'Valguero_WP', []),
				'ark-lostcolony': ('Lost Colony', 'LostColony_WP', [])
			}
			for map_name in maps.keys():
				logging.info('Creating service for map %s' % (map_name,))
				svc = self.create_service(map_name)
				svc.set_option('Session Name', maps[map_name][0])
				svc.set_option('Map Name', maps[map_name][1])
				if len(maps[map_name][2]) > 0:
					svc.set_option('Mods', ','.join(maps[map_name][2]))
			return True
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

	def get_save_directory(self):
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved')

	def get_save_files(self):
		ret = ['clusters']
		for svc in self.get_services():
			path = svc.get_saved_location()
			base_path = os.path.basename(path)
			if os.path.exists(path):
				for file in os.listdir(path):
					if file.endswith('bak'):
						continue
					if '_WP_0' in file or '_WP_1' in file:
						continue
					ret.append(os.path.join('SavedArks', base_path, file))
		return ret

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
		check_path = os.path.join(here, 'AppFiles/ShooterGame/Binaries/Win64/steamclient64.dll')
		if os.path.exists(check_path):
			print('Removing broken Steam library to fix build 74.24 crash...')
			os.remove(check_path)

		# As discovered by Deciphersoul; the update 77.34 released on Dec 24 2025 caused an issue with some Debian
		# servers, notably Debian 12, and when using certain mods.
		# The fix is to download the Microsoft XAudio2 Redist package and extract the required DLLs.
		#
		# https://github.com/Acekorneya/Ark-Survival-Ascended-Server/issues/116
		print('Installing Microsoft XAudio2 Redist DLL to fix build 77.34 crash...')
		req = request.urlopen('https://www.nuget.org/api/v2/package/Microsoft.XAudio2.Redist/1.2.11', timeout=30)
		package_data = req.read()
		package_path = '/tmp/Microsoft.XAudio2.Redist.zip'
		dll_dest = os.path.join(here, 'AppFiles/ShooterGame/Binaries/Win64/xaudio2_9.dll')
		with open(package_path, 'wb') as f:
			f.write(package_data)
		shutil.unpack_archive(package_path, '/tmp/Microsoft.XAudio2.Redist')
		shutil.copy(
			'/tmp/Microsoft.XAudio2.Redist/build/native/release/bin/x64/xaudio2_9redist.dll',
			dll_dest
		)
		if os.geteuid() == 0:
			stat_info = os.stat(here)
			uid = stat_info.st_uid
			gid = stat_info.st_gid
			os.chown(dll_dest, uid, gid)


class GameService(RCONService):
	"""
	Game service manager
	"""
	def __init__(self, service: str, game: GameApp):
		super().__init__(service, game)

		self.configs = {
			'service': INIConfig('service', os.path.join(utils.get_base_directory(), 'Configs', 'service.%s.ini' % self.service))
		}
		self.map = None
		self.runner = None
		self.bin = 'ArkAscendedServer'

		self.load()

	def create_service(self):
		"""
		Create the systemd service for this game, including the service file and environment file
		:return:
		"""
		super().create_service()

		if self.game.get_option_value('Default New Save Format'):
			# This triggers the new save options for a single database.
			# https://ark.wiki.gg/wiki/2023_official_server_save_files
			self.set_option('Use Store', True)
			self.set_option('New Save Format', True)

		# New instances should by default share the group cluster.
		self.set_option('Cluster ID', self.game.get_option_value('Default Cluster ID'))

	def get_environment(self) -> dict:
		"""
		Get the environment variables for this service as a dictionary

		:return:
		"""
		ret = {
			'XDG_RUNTIME_DIR': '/run/user/%s' % utils.get_app_uid(),
			'STEAM_COMPAT_CLIENT_INSTALL_PATH': os.path.join(utils.get_home_directory(), '.local/share/Steam'),
			'STEAM_COMPAT_DATA_PATH': os.path.join(utils.get_base_directory(), 'prefixes', self.service),
		}
		if self.get_option_value('ASA API Loader') != 'None':
			ret['DISPLAY'] = ':99'

		return ret

	def get_executable(self) -> str:
		"""
		Get the full executable for this game service
		:return:
		"""

		proton_path = self.get_option_value('Proton Path')
		binary = 'AsaApiLoader.exe' if self.get_option_value('Mod Loader') == 'ASA API Loader' else 'ArkAscendedServer.exe'
		map = self.get_option_value('Map Name')
		options = cli_formatter(self.configs['service'], 'option', prefix='', sep='=', joiner='?')
		options = map + '?listen?' + options
		flags = cli_formatter(self.configs['service'], 'flag', prefix='-', sep='=', joiner=' ')

		return ' '.join([
			proton_path,
			'run',
			binary,
			options,
			flags
		])

	def set_option(self, option: str, value: str | int | bool):
		"""
		Set a configuration option in the service config
		:param option:
		:param value:
		:return:
		"""
		if option == 'Session Name':
			if self.game.get_option_value('Joined Session Name'):
				value = '%s (%s)' % (value, self.get_map_label())

		super().set_option(option, value)

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
		rebuild = False
		success = None

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
			rebuild = True

		# Reload the service
		if rebuild:
			self.build_systemd_config()
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
		ret =  self._api_cmd('ListPlayers')
		if ret is None:
			return None
		elif ret == 'No Players Connected':
			return 0
		else:
			return len(ret.split('\n'))

	def save_world(self):
		"""
		Issue a Save command on the server
		:return:
		"""
		self._api_cmd('SaveWorld')

	def send_message(self, message: str):
		"""
		Send a message to the game server
		:param message:
		:return:
		"""
		self._api_cmd('ServerChat %s' % message)

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""

		# There's no quick way to get the game process PID from systemd,
		# so use ps to find the process based on the map name
		processes = subprocess.run([
			'ps', 'axh', '-o', 'pid,cmd'
		], stdout=subprocess.PIPE).stdout.decode().strip()
		process = 0
		for line in processes.split('\n'):
			pid, cmd = line.strip().split(' ', 1)
			if cmd.startswith('%s.exe %s?listen' % (self.bin, self.map)):
				_p = int(line.strip().split(' ')[0])
				# ASA API spawns 2 processes, the first handler then the second game executable.
				# Grab the larger PID which should be the actual game process.
				process = max(process, _p)
		return process

	def get_map_label(self) -> str:
		if self.map == 'BobsMissions_WP':
			return 'Club'
		elif self.map.endswith('_WP'):
			return self.map[:-3]
		else:
			return self.map

	def get_mod_names(self) -> list:
		"""
		Get the list of mod names for this service
		:return:
		"""
		names = []
		mods = self.get_option_value('Mods').split(',')

		for mod in mods:
			mod = mod.strip()
			if mod == '':
				continue
			mod_name = ModLibrary.resolve_mod_name(mod)
			if mod_name is not None:
				names.append('%s (%s)' % (mod_name, mod))
			else:
				names.append('NOT INSTALLED (%s)' % (mod,))
		return names

	def get_saved_location(self) -> str:
		if self.map == 'BobsMissions_WP':
			map = 'BobsMissions'
		else:
			map = self.map

		return os.path.join(
			here,
			'AppFiles',
			'ShooterGame',
			'Saved',
			'SavedArks',
			map
		)

	def get_map_file_size(self) -> int:
		"""
		Get the size of the map data on disk in bytes
		:return:
		"""
		map_path = os.path.join(self.get_saved_location(), self.map + '.ark')
		if os.path.exists(map_path):
			return os.path.getsize(map_path)
		else:
			return 0

	def add_to_table(self, table: Table):
		row = []
		for column in table.header:
			if column == '#':
				row.append(str(len(table.data) + 1))
			else:
				row.append(self.get_table_value(column))
		table.add(row)

	def get_table_value(self, col: str) -> str:
		if col == 'Map':
			return self.map
		elif col == 'Session':
			return self.get_option_value('Session Name')
		elif col == 'Port':
			return self.get_option_value('Port')
		elif col == 'RCON':
			return self.get_option_value('RCON Port') if self.is_api_enabled() else 'N/A'
		elif col == 'Auto-Start':
			return '✅ Enabled' if self.is_enabled() else '❌ Disabled'
		elif col == 'Status':
			return '✅ Running' if self.is_running() else '❌ Stopped'
		elif col == 'Admin Password':
			return self.get_option_value('Server Admin Password')
		elif col == 'Players':
			v = self.get_player_count()
			return str(v) if v is not None else 'N/A'
		elif col == 'Mods':
			return ', '.join(self.get_mod_names())
		elif col == 'Cluster ID':
			return self.get_option_value('Cluster ID')
		elif col == 'Map Size':
			return format_filesize(self.get_map_file_size())
		elif col == 'Mem':
			return self.get_memory_usage()
		else:
			return '???'

	def enable_mod(self, mod_id):
		"""
		Enable a mod for this service

		:param mod_id:
		:return:
		"""
		mods = self.get_option_value('Mods').split(',')
		mods = [m.strip() for m in mods if m.strip() != '']

		if mod_id in mods:
			print('Mod %s is already enabled on this service!' % (mod_id, ))
			return

		mods.append(mod_id)
		self.set_option('Mods', ','.join(mods))
		print('Enabled mod %s on service %s' % (mod_id, self.service))

	def disable_mod(self, mod_id):
		"""
		Disable a mod for this service

		:param mod_id:
		:return:
		"""
		mods = self.get_option_value('Mods').split(',')
		mods = [m.strip() for m in mods if m.strip() != '']

		if mod_id not in mods:
			print('Mod %s is not enabled on this service!' % (mod_id, ))
			return

		mods.remove(mod_id)
		self.set_option('Mods', ','.join(mods))
		print('Disabled mod %s on service %s' % (mod_id, self.service))

	def toggle_mod(self, mod_id):
		"""
		Toggle a mod for this service

		:param mod_id:
		:return:
		"""
		mods = self.get_option_value('Mods').split(',')
		mods = [m.strip() for m in mods if m.strip() != '']

		if mod_id in mods:
			mods.remove(mod_id)
			action = 'Disabled'
		else:
			mods.append(mod_id)
			action = 'Enabled'

		self.set_option('Mods', ','.join(mods))
		print('%s mod %s on service %s' % (action, mod_id, self.service))

	def post_start(self) -> bool:
		ret = super().post_start()
		if not ret:
			# Print the last few messages from the Game log to provide a hint to the user if there was a problem.
			log = os.path.join(here, 'AppFiles/ShooterGame/Saved/Logs/ShooterGame.log')
			if os.path.exists(log):
				subprocess.run(['tail', '-n', '20', log])

		return ret

	def get_port_definitions(self) -> list:
		"""
		Get a list of port definitions for this service
		:return:
		"""
		return [
			('Port', 'udp', '%s game port - %s' % (self.game.desc, self.get_map_label())),
			('RCON Port', 'tcp', '%s RCON port - %s' % (self.game.desc, self.get_map_label()))
		]
