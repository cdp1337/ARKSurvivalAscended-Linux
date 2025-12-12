#!/usr/bin/env python3
import argparse
import configparser
import json
import math
import shutil
import time
import datetime
from urllib import request
from urllib import error as urllib_error
from scriptlets._common.firewall_allow import *
from scriptlets._common.firewall_remove import *
from scriptlets.bz_eval_tui.prompt_yn import *
from scriptlets.bz_eval_tui.prompt_text import *
from scriptlets.bz_eval_tui.table import *
from scriptlets.bz_eval_tui.print_header import *
from scriptlets._common.get_wan_ip import *
from scriptlets.steam.steamcmd_check_app_update import *
# import:org_python/venv_path_include.py
from scriptlets.warlock.steam_app import *
from scriptlets.warlock.base_service import *
from scriptlets.warlock.cli_config import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.rcon_service import *
from scriptlets.warlock.unreal_config import *


here = os.path.dirname(os.path.realpath(__file__))

GAME_DESC = 'ARK: Survival Ascended'
REPO = 'cdp1337/ARKSurvivalAscended-Linux'
FUNDING = 'https://ko-fi.com/bitsandbytes'

GAME_USER = 'steam'
STEAM_DIR = '/home/%s/.local/share/Steam' % GAME_USER

ICON_ENABLED = '✅'
ICON_STOPPED = '🛑'
ICON_DISABLED = '❌'
ICON_WARNING = '⛔'
ICON_STARTING = '⌛'

# Require sudo / root for starting/stopping the service
IS_SUDO = os.geteuid() == 0


def format_seconds(seconds: int) -> dict:
	hours = int(seconds // 3600)
	minutes = int((seconds - (hours * 3600)) // 60)
	seconds = int(seconds % 60)

	short_minutes = ('0' + str(minutes)) if minutes < 10 else str(minutes)
	short_seconds = ('0' + str(seconds)) if seconds < 10 else str(seconds)

	if hours > 0:
		short = '%s:%s:%s' % (str(hours), short_minutes, short_seconds)
	else:
		short = '%s:%s' % (str(minutes), short_seconds)

	return {
		'h': hours,
		'm': minutes,
		's': seconds,
		'full': '%s hrs %s min %s sec' % (str(hours), str(minutes), str(seconds)),
		'short': short
	}

def format_filesize(size_bytes: int) -> str:
	if size_bytes == 0:
		return '0 B'
	size_name = ('B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB')
	i = int(math.floor(math.log(size_bytes, 1024)))
	p = math.pow(1024, i)
	s = round(size_bytes / p, 2)
	return '%s %s' % (s, size_name[i])


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
		# Find services for this game within systemd
		res = subprocess.run(['grep', '-lr', os.path.join(here, 'AppFiles'), '/etc/systemd/system/'], stdout=subprocess.PIPE)
		for line in res.stdout.decode().strip().split('\n'):
			if line.endswith('.service'):
				service_name = os.path.basename(line)[:-8]
				if os.path.exists(os.path.join('/etc/systemd/system/', service_name + '.service.d/override.conf')):
					self.services.append(service_name)

		self.configs = {
			'game': UnrealConfig('game', os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'Game.ini')),
			'gus': UnrealConfig('gus', os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'GameUserSettings.ini')),
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

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
			print('Removing broken Steam library to prevent segfault')
			os.remove(check_path)


class GameService(RCONService):
	"""
	Game service manager
	"""
	def __init__(self, service: str, game: GameApp):
		super().__init__(service, game)
		self.file = '/etc/systemd/system/%s.service.d/override.conf' % service
		self.configs['cli'] = CLIConfig('cli', self.file)
		self.map = None
		self.runner = None

		with open(self.file, 'r') as f:
			for line in f.readlines():
				if not line.startswith('ExecStart='):
					continue

				# Extract out all the various info from the start line
				extracted_keys = re.match(
					(r'ExecStart=(?P<runner>[^ ]*) run ArkAscendedServer.exe'
					 r'(?P<map>[^/?]*)\?listen\?(?P<args>.*)'
					 ),
					line
				)
				self.runner = extracted_keys.group('runner')
				self.map = extracted_keys.group('map').strip()
				self.configs['cli'].format = 'ExecStart=%s run ArkAscendedServer.exe %s?listen[OPTIONS]' % (self.runner, self.map)

		self.load()

	def set_option(self, option: str, value: Union[str, int, bool]):
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

	def option_value_updated(self, option: str, previous_value, new_value):
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""

		# Special option actions
		if option == 'Port':
			# Update firewall for game port change
			if previous_value:
				firewall_remove(int(previous_value), 'udp')
			firewall_allow(int(value), 'udp', '%s game port - %s' % (self.game.desc, self.get_map_label()))

		# Reload the service
		if os.geteuid() != 0:
			print('WARNING: Please run sudo systemctl daemon-reload to apply changes to the service.', file=sys.stderr)
		else:
			subprocess.run(['systemctl', 'daemon-reload'])

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

	def get_player_max(self) -> Union[int, None]:
		"""
		Get the maximum player count on the server, or None if the API is unavailable
		:return:
		"""
		if self.option_has_value('Win Live Max Players'):
			return self.get_option_value('Win Live Max Players')
		else:
			return 70

	def get_player_count(self) -> Union[int, None]:
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
		for line in processes.split('\n'):
			pid, cmd = line.strip().split(' ', 1)
			if cmd.startswith('ArkAscendedServer.exe %s?listen' % self.map):
				return int(line.strip().split(' ')[0])
		return 0

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


def menu_service(service: GameService):
	"""
	Interface for managing an individual service
	:param service:
	:return:
	"""
	while True:
		ModLibrary.refresh_data()

		print_header('Service Details')
		running = service.is_running()
		if service.is_api_enabled() and running:
			players = service.get_player_count()
			if players is None:
				players = 'N/A (unable to retrieve player count)'
		else:
			players = 'N/A'

		# Retrieve the WAN IP of this instance; can be useful for direct access.
		wan = get_wan_ip() or 'N/A'

		print('Map:         %s' % service.map)
		print('Session:     %s' % service.get_option_value('Session Name'))
		print('WAN IP:      %s' % wan)
		print('Port:        %s (UDP)' % service.get_option_value('Port'))
		print('RCON:        %s (TCP)' % service.get_option_value('RCON Port'))
		print('Auto-Start:  %s' % ('Yes' if service.is_enabled() else 'No'))
		print('Status:      %s' % ('Running' if running else 'Stopped'))
		print('Players:     %s' % players)
		print('Mods:        %s' % '\n             '.join(service.get_mod_names()))
		print('Cluster ID:  %s' % service.get_option_value('Cluster ID'))
		if running:
			print('Memory:      %s' % service.get_memory_usage())
			print('CPU:         %s' % service.get_cpu_usage())
			print('Map Size:    %s' % format_filesize(service.get_map_file_size()))
			connect_pw = service.get_option_value('Server Password')
			if connect_pw == '':
				print('Connect Cmd: open %s:%s' % (wan, service.get_option_value('Port')))
			else:
				print('Connect Cmd: open %s:%s?%s' % (wan, service.get_option_value('Port'), connect_pw))
		print('')

		# Check for common recent issues with the server
		log = service.get_logs()
		if 'oom-kill' in log:
			print('❗⛔❗ WARNING - Service was recently killed by the OOM killer')
			print('This may indicate that your server ran out of memory!')
			print('')

		options = []
		if service.is_enabled():
			options.append('[D]isable')
		else:
			options.append('[E]nable')

		if running:
			print('Map is currently running, please stop to make changes.')
		else:
			options.append('[M]ods | [C]luster | re[N]ame | [O]ptions')

		if running:
			options.append('s[T]op')
			options.append('[R]estart')
		else:
			options.append('[S]tart')

		options.append('[B]ack')
		opt = input(' | '.join(options) + ': ').lower()

		if opt == 'b':
			return
		elif opt == 'e':
			if not service.is_enabled():
				service.enable()
		elif opt == 'd':
			if service.is_enabled():
				service.disable()
		elif opt == 'm':
			val = input('Enter the mod ID to toggle: ').strip()
			if val != '':
				service.toggle_mod(val)
		elif opt == 'c':
			service.prompt_option('Cluster ID')
		elif opt == 'n':
			name = service.get_option_value('Session Name')
			if '(' in name and service.game.get_option_value('Joined Session Name'):
				name = name[:name.index('(')]
			val = prompt_text('Please enter new name: ', default=name, prefill=True)
			service.set_option('Session Name', val)
		elif opt == 'o':
			print('@TODO')
		elif opt == 's':
			service.start()
		elif opt == 't':
			service.stop()
		elif opt == 'r':
			service.restart()
		else:
			print('Invalid option')


def menu_monitor(service: GameService):
	"""
	Monitor the game server status in real time

	:param service:
	:return:
	"""

	try:
		while True:
			status = service.get_status()
			weather = service.get_weather()
			players = status['onlinePlayers']

			os.system('clear')
			print_header('Game Server Monitor - Press Ctrl+C to exit')
			if not service.is_running():
				print('Game is not currently running!')
				time.sleep(20)
				continue

			if status is None:
				print('Unable to connect to game API!')
			else:
				uptime = format_seconds(status['uptime'])
				print('Players Online: %s/%s' % (str(len(status['onlinePlayers'])), str(service.game.get_option_value('MaxPlayers'))))
				print('Direct Connect: %s:%s' % (get_wan_ip() or 'N/A', service.game.get_option_value('GamePort')))
				print('Server Uptime:  %s' % uptime['full'])

				if weather is not None:
					print('Temperature:       %.1f °C' % weather['temperature'])
					print('Precipitation:     %d' % weather['precipitation'])
					print('Cloudiness:        %d' % weather['cloudiness'])
					print('Fog:               %d' % weather['fog'])
					print('Pressure:          %.1f hPa' % weather['pressure'])
					print('Relative Humidity: %d%%' % weather['relativeHumidity'])
					print('Wind Force:        %.1f m/s' % weather['windForce'])

				print('')
				if len(players) > 0:
					table = Table(['Player Name', 'Online For'])
					for p in players:
						table.add([players[p]['name'], format_seconds(players[p]['timeConnected'])['short']])
					table.render()
				else:
					print('No players currently online.')

			time.sleep(5)
	except KeyboardInterrupt:
		print('\nExiting monitor...')


def menu_get_services(game: GameApp):
	services = game.get_services()
	stats = {}
	for g in services:
		if g.is_starting():
			status = 'starting'
		elif g.is_stopping():
			status = 'stopping'
		elif g.is_running():
			status = 'running'
		else:
			status = 'stopped'

		pre_exec = g.get_exec_start_pre_status()
		start_exec = g.get_exec_start_status()
		if pre_exec and pre_exec['start_time']:
			pre_exec['start_time'] = int(pre_exec['start_time'].timestamp())
		if pre_exec and pre_exec['stop_time']:
			pre_exec['stop_time'] = int(pre_exec['stop_time'].timestamp())
		if start_exec and start_exec['start_time']:
			start_exec['start_time'] = int(start_exec['start_time'].timestamp())
		if start_exec and start_exec['stop_time']:
			start_exec['stop_time'] = int(start_exec['stop_time'].timestamp())

		svc_stats = {
			'service': g.service,
			'name': g.get_option_value('Session Name'),
			'ip': get_wan_ip(),
			'port': g.get_option_value('Port'),
			'status': status,
			'enabled': g.is_enabled(),
			'player_count': g.get_player_count(),
			'max_players': g.get_player_max(),
			'memory_usage': g.get_memory_usage(),
			'cpu_usage': g.get_cpu_usage(),
			'game_pid': g.get_game_pid(),
			'service_pid': g.get_pid(),
			'pre_exec': pre_exec,
			'start_exec': start_exec,
		}
		stats[g.service] = svc_stats
	print(json.dumps(stats))


def menu_check_update(game: GameApp):
	if game.check_update_available():
		print('An update is available for %s!' % game.desc)
		sys.exit(0)
	else:
		print('%s is up to date.' % game.desc)
		sys.exit(1)


def menu_get_game_configs(game: GameApp):
	"""
	List the available configuration files for this game (JSON encoded)
	:param game:
	:return:
	"""
	opts = []
	# Get global configs
	for opt in game.get_options():
		opts.append({
			'option': opt,
			'default': game.get_option_default(opt),
			'value': game.get_option_value(opt),
			'type': game.get_option_type(opt),
			'help': game.get_option_help(opt)
		})

	print(json.dumps(opts))
	sys.exit(0)


def menu_get_service_configs(service: GameService):
	"""
	List the available configuration files for this game (JSON encoded)
	:param game:
	:param service:
	:return:
	"""
	opts = []
	# Get per-service configs
	for opt in service.get_options():
		opts.append({
			'option': opt,
			'default': service.get_option_default(opt),
			'value': service.get_option_value(opt),
			'type': service.get_option_type(opt),
			'help': service.get_option_help(opt)
		})

	print(json.dumps(opts))
	sys.exit(0)


def menu_messages(game):
	"""
	Management interface to view/edit player messages for various events
	:return:
	"""
	messages = []
	for key in game.configs['manager'].options.keys():
		if game.configs['manager'].options[key][0] == 'Messages':
			messages.append(key)

	while True:
		print_header('Player Messages')
		print('The following messages will be sent to players when certain events occur.')
		print('')
		table = Table()
		counter = 0
		for key in messages:
			counter += 1
			table.add(['opt %s' % str(counter), key, game.get_option_value(key)])
		table.render()

		print('')
		opt = input('[1-%s] change message | [B]ack: ' % counter).lower()

		if opt == 'b':
			return
		elif str.isnumeric(opt) and 1 <= int(opt) <= counter:
			key = messages[int(opt)-1]
			game.prompt_option(key)
		else:
			print('Invalid option')


def menu_mods(game: GameApp):
	"""
	Interface to manage mods across all maps
	:return:
	"""
	while True:
		# Pull mod data to know which mods are unused
		ModLibrary.refresh_data()
		mods_installed = ModLibrary.get_mods()
		mods_used = []

		running = game.is_active()
		services = game.get_services()
		print_header('Mods Configuration')
		table = Table(['Session', 'Mods', 'Status'])
		for service in services:
			service.add_to_table(table)
			for modid in service.get_option_value('Mods').split(','):
				modid = modid.strip()
				if modid != '' and modid not in mods_used:
					mods_used.append(modid)
		table.render()
		print('')

		print('Installed Mods:')
		for mod_id in mods_installed:
			used = ' (In Use)' if mod_id in mods_used else ' (Not In Use)'
			print(' - %s: %s%s' % (mod_id, mods_installed[mod_id]['name'], used))
		print('')
		if running:
			print('⚠️  At least one map is running - unable to change mods while a map is active')
			opt = input('[B]ack: ').lower()
		else:
			opt = input('[E]nable mod on all maps | [D]isable mod on all maps | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'e':
			val = input('Enter the mod ID to enable: ').strip()
			if val != '':
				for s in services:
					s.enable_mod(val)
		elif opt == 'd':
			val = input('Enter the mod ID to disable: ').strip()
			if val != '':
				for s in services:
					s.disable_mod(val)
		else:
			print('Invalid option')


def menu_cluster(game):
	while True:
		running = game.is_active()
		services = game.get_services()
		print_header('Cluster Configuration')
		table = Table(['Session', 'Cluster ID', 'Status'])
		for service in services:
			service.add_to_table(table)
		table.render()
		print('')

		if running:
			print('⚠️  At least one map is running - unable to change cluster while a map is active')
			opt = input('[B]ack: ').lower()
		else:
			opt = input('[C]hange cluster id on all maps | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'c' and not running:
			print('WARNING - changing the cluster ID may result in loss of data!')
			vals = []
			for s in services:
				c_id = s.get_option_value('Cluster ID')
				if c_id and c_id not in vals:
					vals.append(c_id)
			if len(vals) == 1:
				val = prompt_text('Cluster ID: ', default=vals[0], prefill=True)
			else:
				val = prompt_text('Cluster ID: ')
			for s in services:
				s.set_option('Cluster ID', val)
		else:
			print('Invalid option')


def menu_admin_password(game: GameApp):
	"""
	Interface to manage rcon and administration password
	:return:
	"""
	while True:
		running = game.is_active()
		services = game.get_services()
		print_header('Admin and RCON Configuration')
		table = Table(['Session', 'Admin Password', 'RCON', 'Status'])
		for service in services:
			service.add_to_table(table)
		table.render()
		print('')

		if running:
			print('⚠️  At least one map is running - unable to change settings while a map is active')
			opt = input('[B]ack: ').lower()
		else:
			opt = input('[C]hange admin password on all | [E]nable RCON on all | [D]isable RCON on all | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'e' and not running:
			for s in services:
				s.set_option('RCON Enabled', True)
		elif opt == 'd' and not running:
			print('WARNING - disabling RCON may prevent clean shutdowns!')
			for s in services:
				s.set_option('RCON Enabled', False)
		elif opt == 'c' and not running:
			vals = []
			for s in services:
				v = s.get_option_value('Server Admin Password')
				if v and v not in vals:
					vals.append(v)
			if len(vals) == 1:
				val = prompt_text('Server Admin Password: ', default=vals[0], prefill=True)
			else:
				val = prompt_text('Server Admin Password: ')

			for s in services:
				s.set_option('Server Admin Password', val)
		else:
			print('Invalid option')


def menu_discord(game: GameApp):
	while True:
		print_header('Discord Integration')
		enabled = game.get_option_value('Discord Enabled')
		webhook = game.get_option_value('Discord Webhook URL')
		if webhook == '':
			print('Discord has not been integrated yet.')
			print('')
			print('If you would like to send shutdown / startup notifications to Discord, you can')
			print('do so by adding a Webhook (Discord -> Settings -> Integrations -> Webhooks -> Create Webhook)')
			print('and pasting the generated URL here.')
			print('')
			print('URL or just the character "b" to go [B]ack.')
			opt = input(': ')

			if 'https://' in opt:
				game.set_option('Discord Enabled', True)
				game.set_option('Discord Webhook URL', opt)
			else:
				return
		else:
			discord_channel = None
			discord_guild = None
			discord_name = None
			req = request.Request(webhook, headers={'Accept': 'application/json', 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0'}, method='GET')
			try:
				with request.urlopen(req) as resp:
					data = json.loads(resp.read().decode('utf-8'))
					discord_channel = data['channel_id']
					discord_guild = data['guild_id']
					discord_name = data['name']
			except urllib_error.HTTPError as e:
				print('Error: %s' % e)
			except json.JSONDecodeError as e:
				print('Error: %s' % e)

			if enabled and discord_name:
				print('Discord integration is currently available and enabled!')
			elif discord_name:
				print('Discord integration is currently DISABLED.')
			else:
				print('Discord integration is currently unavailable, bad Webhook URL?')
			print('')
			print('Discord Webhook URL:  %s' % webhook[0:webhook.rindex('/')+5] + '************' + webhook[-4:])
			print('Discord Channel ID:   %s' % discord_channel)
			print('Discord Guild ID:     %s' % discord_guild)
			print('Discord Webhook Name: %s' % discord_name)
			print('')

			options = []
			if enabled:
				options.append('[D]isable')
			else:
				options.append('[E]nable')

			options.append('[C]hange Discord webhook URL')
			options.append('[B]ack')
			print(' | '.join(options))
			opt = input(': ').lower()

			if opt == 'b':
				return
			elif opt == 'c':
				print('do so by adding a Webhook (Discord -> Settings -> Integrations -> Webhooks -> Create Webhook)')
				print('and pasting the generated URL here.')
				val = input('Enter new Discord webhook URL: ').strip()
				if val != '':
					game.set_option('Discord Webhook URL', val)
			elif opt == 'e':
				game.set_option('Discord Enabled', True)
			elif opt == 'd':
				game.set_option('Discord Enabled', False)
			else:
				print('Invalid option')


def menu_wipe(game):
	while True:
		print_header('Wipe User Data')
		print('Wiping user data will remove all player progress, including characters, items, and structures.')
		print('This action is irreversible and will reset the game to its initial state.')
		print('')
		table = Table(['#', 'Map', 'Map Size'])
		services = game.get_services()
		for service in services:
			service.add_to_table(table)
		table.render()

		print('')
		print('1-%s to reset individual map' % len(services))
		print('or [A]ll to wipe all user data across all maps, [B]ack to return')
		opt = input(': ').lower()

		if opt == 'b':
			return

		if opt.isdigit() and 1 <= int(opt) <= len(services):
			path = services[int(opt)-1].get_saved_location()
		elif opt == 'a':
			path = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'SavedArks')
		else:
			print('Invalid option!')
			return

		print('Are you sure you want to proceed? This action cannot be undone! type DELETE to confirm.')
		confirm = input(': ')
		if confirm == 'DELETE':
			# Instead of doing a simple shutil.rmtree, manually walk through the target directory
			# and delete individual files.  This avoids issues with symlinks that may exist in the SavedArks folder.
			for root, dir, files in os.walk(path, followlinks=True):
				for f in files:
					file_path = os.path.join(root, f)
					print('Removing %s...' % file_path)
					os.remove(file_path)
		else:
			print('Wipe operation cancelled.')


def menu_main(game: GameApp):
	stay = True
	while stay:
		running = game.is_active()
		services = game.get_services()
		print_header('Welcome to the %s Server Manager' % game.desc)
		if REPO:
			print('Find an issue? https://github.com/%s/issues' % REPO)
		if FUNDING:
			print('Want to help support this project? %s' % FUNDING)
		print('')
		table = Table(['#', 'Map', 'Session', 'Port', 'RCON', 'Auto-Start', 'Status', 'Mem', 'Players'])
		for service in services:
			service.add_to_table(table)
		table.render()

		print('')
		print('1-%s to manage individual map settings' % len(services))
		print('Configure: [M]ods | [C]luster | [A]dmin password/RCON | re[N]ame | [D]iscord integration | [P]layer messages')
		print('Control: [S]tart all | s[T]op all | [R]estart all | [U]pdate')
		if running:
			print('Manage Data: (please stop all maps to manage game data)')
		else:
			print('Manage Data: [B]ackup | [W]ipe User Data')
		print('or [Q]uit to exit')
		opt = input(': ').lower()

		if opt == 'a':
			menu_admin_password(game)
		elif opt == 'b':
			if running:
				print('⚠️  Please stop all maps before managing backups.')
			else:
				game.backup()
		elif opt == 'c':
			menu_cluster(game)
		elif opt == 'd':
			menu_discord(game)
		elif opt == 'm':
			menu_mods(game)
		elif opt == 'n':
			if running:
				print('⚠️  Please stop all maps before renaming.')
			else:
				val = input('Please enter new name: ').strip()
				if val != '':
					for s in services:
						s.set_option('Session Name', val)
		elif opt == 'p':
			menu_messages(game)
		elif opt == 'q':
			stay = False
		elif opt == 'r':
			for s in services:
				s.restart()
		elif opt == 's':
			for s in services:
				if s.is_enabled():
					s.start()
				else:
					print('Skipping %s as it is not enabled for auto-start.' % s.service)
		elif opt == 't':
			for s in services:
				s.stop()
		elif opt == 'u':
			if running:
				print('⚠️ Please stop all maps prior to updating.')
			else:
				game.update()
		elif opt == 'w':
			if running:
				print('⚠️  Please stop all maps before wiping user data.')
			else:
				menu_wipe(game)
		elif opt.isdigit() and 1 <= int(opt) <= len(services):
			menu_service(services[int(opt)-1])

parser = argparse.ArgumentParser('manage.py')
parser.add_argument(
	'--service',
	help='Specify the service instance to manage (default: ALL)',
	type=str,
	default='ALL'
)
parser.add_argument(
	'--pre-stop',
	help='Send notifications to game players and Discord and save the world',
	action='store_true'
)
parser.add_argument(
	'--post-start',
	help='Send notifications to game players and Discord after starting the server',
	action='store_true'
)
parser.add_argument(
	'--stop',
	help='Stop the game server',
	action='store_true'
)
parser.add_argument(
	'--start',
	help='Start the game server',
	action='store_true'
)
parser.add_argument(
	'--restart',
	help='Restart the game server',
	action='store_true'
)
parser.add_argument(
	'--monitor',
	help='Monitor the game server status in real time',
	action='store_true'
)
parser.add_argument(
	'--backup',
	help='Backup the game server files',
	action='store_true'
)
parser.add_argument(
	'--max-backups',
	help='Maximum number of backups to keep when creating a new backup (default: 0 = unlimited)',
	type=int,
	default=0
)
parser.add_argument(
	'--restore',
	help='Restore the game server files from a backup archive',
	type=str,
	default=''
)
parser.add_argument(
	'--check-update',
	help='Check for game updates via SteamCMD and report the status',
	action='store_true'
)
parser.add_argument(
	'--update',
	help='Update the game server via SteamCMD',
	action='store_true'
)
parser.add_argument(
	'--get-services',
	help='List the available service instances for this game (JSON encoded)',
	action='store_true'
)
parser.add_argument(
	'--get-configs',
	help='List the available configuration files for this game (JSON encoded)',
	action='store_true'
)
parser.add_argument(
	'--set-config',
	help='Set a configuration option for the game',
	type=str,
	nargs=2
)
parser.add_argument(
	'--get-ports',
	help='Get the list of ports used by the game server (JSON encoded)',
	action='store_true'
)
parser.add_argument(
	'--is-running',
	help='Check if any game service is currently running (exit code 0 = yes, 1 = no)',
	action='store_true'
)
parser.add_argument(
	'--has-players',
	help='Check if any players are currently connected to any game service (exit code 0 = yes, 1 = no)',
	action='store_true'
)
parser.add_argument(
	'--logs',
	help='Print the latest logs from the game service',
	action='store_true'
)
parser.add_argument(
	'--first-run',
	help='Perform first-run configuration for setting up the game server initially',
	action='store_true'
)
args = parser.parse_args()

game = GameApp()
services = game.get_services()


if args.service != 'ALL':
	# User opted to manage only a single game instance
	service = None
	for svc in services:
		if svc.service == args.service:
			service = svc
			break

	if service is None:
		print('Service instance %s not found!' % args.service, file=sys.stderr)
		sys.exit(1)
	else:
		services = [ service ]

if args.pre_stop:
	if len(services) > 1:
		print('ERROR: --pre-stop can only be used with a single service instance at a time.', file=sys.stderr)
		sys.exit(1)
	g = services[0]
	sys.exit(0 if g.pre_stop() else 1)
elif args.post_start:
	if len(services) > 1:
		print('ERROR: --post-start can only be used with a single service instance at a time.', file=sys.stderr)
		sys.exit(1)
	g = services[0]
	sys.exit(0 if g.post_start() else 1)
elif args.stop:
	for svc in services:
		svc.stop()
elif args.start:
	if len(services) > 1:
		# Start any enabled instance
		for svc in services:
			if svc.is_enabled():
				svc.start()
			else:
				print('Skipping %s as it is not enabled for auto-start.' % svc.service)
	else:
		for svc in services:
			svc.start()
elif args.restart:
	for svc in services:
		svc.restart()
elif args.monitor:
	if len(services) > 1:
		print('ERROR: --monitor can only be used with a single service instance at a time.', file=sys.stderr)
		sys.exit(1)
	g = services[0]
	menu_monitor(g)
elif args.logs:
	if len(services) > 1:
		print('ERROR: --log can only be used with a single service instance at a time.', file=sys.stderr)
		sys.exit(1)
	g = services[0]
	g.print_logs()
elif args.backup:
	sys.exit(0 if game.backup(args.max_backups) else 1)
elif args.restore != '':
	sys.exit(0 if game.restore(args.restore) else 1)
elif args.check_update:
	menu_check_update(game)
elif args.update:
	sys.exit(0 if game.update() else 1)
elif args.get_services:
	menu_get_services(game)
elif args.get_configs:
	if args.service == 'ALL':
		menu_get_game_configs(game)
	else:
		g = services[0]
		menu_get_service_configs(g)
elif args.set_config != None:
	option, value = args.set_config
	if args.service == 'ALL':
		game.set_option(option, value)
	else:
		g = services[0]
		g.set_option(option, value)
elif args.get_ports:
	ports = []
	for svc in services:
		if not getattr(svc, 'get_port_definitions', None):
			continue

		for port_dat in svc.get_port_definitions():
			port_def = {}
			if isinstance(port_dat[0], int):
				# Port statically assigned and cannot be changed
				port_def['value'] = port_dat[0]
				port_def['config'] = None
			else:
				port_def['value'] = svc.get_option_value(port_dat[0])
				port_def['config'] = port_dat[0]

			port_def['service'] = svc.service
			port_def['protocol'] = port_dat[1]
			port_def['description'] = port_dat[2]
			ports.append(port_def)
	print(json.dumps(ports))
	sys.exit(0)
elif args.has_players:
	has_players = False
	for svc in services:
		c = svc.get_player_count()
		if c is not None and c > 0:
			has_players = True
			break
	sys.exit(0 if has_players else 1)
elif args.is_running:
	is_running = False
	for svc in services:
		if svc.is_running():
			is_running = True
			break
	sys.exit(0 if is_running else 1)
elif args.first_run:
	menu_first_run(game, False)
else:
	# Default mode - interactive menu
	if not game.configured:
		menu_first_run(game, True)

	if len(services) > 1:
		menu_main(game)
	else:
		g = list(services.values())[0]
		menu_service(g)
