#!/usr/bin/env python3
import argparse
import configparser
import json
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
from scriptlets.warlock.base_app import *
from scriptlets.warlock.base_service import *
from scriptlets.warlock.cli_config import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.rcon_service import *
from scriptlets.warlock.unreal_config import *
from pprint import pprint


here = os.path.dirname(os.path.realpath(__file__))

GAME_DESC = 'ARK: Survival Ascended'
REPO = 'cdp1337/ARKSurvivalAscended-Linux'
FUNDING = 'https://ko-fi.com/bitsandbytes'

GAME_USER = 'steam'
STEAM_DIR = '/home/%s/.local/share/Steam' % GAME_USER

SAVE_DIR = '/home/%s/.config/Epic/Vein/Saved/SaveGames/' % GAME_USER
# VEIN uses the default Epic save handler which stores saves in ~/.config

ICON_ENABLED = '✅'
ICON_STOPPED = '🛑'
ICON_DISABLED = '❌'
ICON_WARNING = '⛔'
ICON_STARTING = '⌛'
ICON_ALERT = '⚠️'

manager = INIConfig('manager', os.path.join(here, '.settings.ini'))

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


class GameApp(BaseApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'ARK:SA'
		self.desc = 'ARK: Survival Ascended'
		self.steam_id = '2430930'
		services_path = os.path.join(here, 'services')
		for f in os.listdir(services_path):
			if f.endswith('.conf'):
				self.services.append(f[:-5])

		self.configs = {
			'game': UnrealConfig('game', os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'Game.ini')),
			'gus': UnrealConfig('gus', os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'GameUserSettings.ini'))
		}
		self.load()

	def check_update_available(self) -> bool:
		"""
		Check if a SteamCMD update is available for this game

		:return:
		"""
		return steamcmd_check_app_update(os.path.join(here, 'AppFiles', 'steamapps', 'appmanifest_%s.acf' % self.steam_id))


class GameService(RCONService):
	"""
	Game service manager
	"""
	def __init__(self, service: str, game: GameApp):
		super().__init__(service, game)
		self.file = os.path.join(here, 'services', '%s.conf' % service)
		self.configs['cli'] = CLIConfig('cli')
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
				self.configs['cli'].load(extracted_keys.group('args'))

	def save(self):
		"""
		Save the service definition back to the service file
		and reload systemd with the new updates.
		:return:
		"""
		exec_line = 'ExecStart=%s run ArkAscendedServer.exe %s?listen?%s' % (self.runner, self.map, str(self.configs['cli']))

		# Save the compiled line back to the service file, (along with the header)
		with open(self.file, 'w') as f:
			f.write('[Service]\n')
			f.write('# Edit this line to adjust start parameters of the server\n')
			f.write('# After modifying, please remember to run  to apply changes to the system.\n')
			f.write(exec_line + '\n')

		# Reload the service
		if os.geteuid() != 0:
			print('WARNING: Please run sudo systemctl daemon-reload to apply changes to the service.', file=sys.stderr)
		else:
			subprocess.run(['systemctl', 'daemon-reload'])

	def set_option(self, option: str, value: str):
		"""
		Set a configuration option in the service config
		:param option:
		:param value:
		:return:
		"""
		if option == 'Session name':
			if manager.get_value('Joined Session Name'):
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
			return self.game.get_option_value('Max Players')

	def get_player_count(self) -> Union[int, None]:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		ret =  self._rcon_cmd('ListPlayers')
		if ret is None:
			return None
		elif ret == 'No Players Connected':
			return 0
		else:
			return len(ret.split('\n'))

	def post_start(self):
		"""
		Perform the necessary operations for after a game has started
		:return:
		"""
		pass

	def pre_stop(self):
		"""
		Perform operations necessary for safely stopping a server

		Called automatically via systemd
		:return:
		"""
		pass

	def save_world(self):
		"""
		Issue a Save command on the server
		:return:
		"""
		self._rcon_cmd('SaveWorld')

	def send_message(self, message: str):
		"""
		Send a message to the game server
		:param message:
		:return:
		"""
		self._rcon_cmd('ServerChat %s' % message)

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
				names.append('%s NOT INSTALLED (%s)' % (ICON_ALERT, mod))
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
			row.append(self.get_table_value(column))
		table.add(row)

	def get_table_value(self, col: str) -> str:
		if col == 'num':
			#row.append(str(row_counter))
			return '#todo#'
		elif col == 'map':
			return self.map
		elif col == 'session':
			return self.get_option_value('Session Name')
		elif col == 'port':
			return str(self.get_option_value('Port'))
		elif col == 'rcon':
			return self.get_option_value('RCON Port') if self.is_api_enabled() else 'N/A'
		elif col == 'enabled':
			return '✅ Enabled' if self.is_enabled() else '❌ Disabled'
		elif col == 'running':
			return '✅ Running' if self.is_running() else '❌ Stopped'
		else:
			return '???'
		'''elif col == 'admin_password':
			row.append(service.get_option('ServerAdminPassword'))
		elif col == 'players':
			v = service.rcon_get_number_players()
			row.append(str(v) if v is not None else 'N/A')
		elif col == 'mods':
			row.append(', '.join(service.mods))
		elif col == 'cluster':
			row.append(service.cluster_id or '')
		elif col == 'map_size':
			row.append(str(service.get_map_file_size()))
		elif col == 'player_profiles':
			row.append(str(service.get_num_player_profiles()))
		elif col == 'memory':
			row.append(service.get_memory_usage())
		'''



def menu_service(service: GameService):
	stay = True
	wan_ip = get_wan_ip()

	while stay:
		print_header('Welcome to the %s Manager' % service.game.desc)
		if REPO != '':
			print('Found an issue? https://github.com/%s/issues' % REPO)
		if FUNDING != '':
			print('Want to help financially support this project? %s' % FUNDING)

		keys = []
		options = []
		server_port = service.game.get_option_value('GamePort')
		player_pass = service.game.get_option_value('ServerPassword')
		api_port = str(service.game.get_option_value('APIPort'))
		print('')
		table = Table()
		table.borders = False
		table.align = ['r', 'r', 'l']

		if service.is_starting():
			table.add(['Status', '', ICON_STARTING + ' Starting...'])
		elif service.is_stopping():
			table.add(['Status', '', ICON_STARTING + ' Stopping...'])
		elif service.is_running():
			table.add(['Status', 's[T]op', ICON_ENABLED + ' Running'])
			keys.append('T')
		else:
			table.add(['Status', '[S]tart', ICON_STOPPED + ' Stopped'])
			keys.append('S')

		if service.is_enabled():
			table.add(['Auto-Start', '[D]isable', ICON_ENABLED + ' Enabled'])
			keys.append('D')
		else:
			table.add(['Auto-Start', '[E]nable', ICON_DISABLED + ' Disabled'])
			keys.append('E')

		if service.is_running():
			table.add(['Memory Usage', '', service.get_memory_usage()])
			table.add(['CPU Usage', '', service.get_cpu_usage()])
			table.add(['Players', '', str(service.get_player_count())])
			table.add(['Direct Connect', '', '%s:%s' % (wan_ip, server_port) if wan_ip else 'N/A'])

		table.add(['------', '----', '---------------------'])

		table.add(['Server Name', '(opt %s)' % (len(options) + 1), service.game.get_option_value('ServerName')])
		options.append(('ServerName', ))

		table.add(['Port', '(opt %s)' % (len(options) + 1), server_port])
		options.append(('ServerPort', True))

		table.add(['API Access', '(opt %s)' % (len(options) + 1), ICON_ENABLED + ' ' + api_port if api_port else ICON_DISABLED + ' Disabled'])
		options.append(('APIPort', True))

		table.add(['Join Password', '(opt %s)' % (len(options) + 1), player_pass if player_pass != '' else '--No Password Required--'])
		options.append(('ServerPassword', ))

		table.add(['Max Players', '(opt %s)' % (len(options) + 1), service.game.get_option_value('MaxPlayers')])
		options.append(('MaxPlayers', ))

		table.add(['Query Port', '(opt %s)' % (len(options) + 1), service.game.get_option_value('SteamQueryPort')])
		options.append(('SteamQueryPort', True))

		table.add(['Valve Anti Cheat', '(opt %s)' % (len(options) + 1), service.game.get_option_value('VACEnabled')])
		options.append(('VACEnabled', ))

		table.add(['PVP Enabled', '(opt %s)' % (len(options) + 1), service.game.get_option_value('PVPEnabled')])
		options.append(('PVPEnabled', ))

		table.render()

		print('')
		print('Control: [%s], or [Q]uit to exit' % '/'.join(keys))
		print('Configure: [1-%s], [P]layer messages' % str(len(options)))
		opt = input(': ').lower()

		if opt == 'q':
			stay = False

		elif opt == 'p':
			menu_messages()

		elif opt == 's':
			service.start()

		elif opt == 't':
			service.stop()

		elif opt == 'e':
			service.enable()

		elif opt == 'd':
			service.disable()

		elif str.isnumeric(opt) and 1 <= int(opt) <= len(options):
			action = options[int(opt) - 1]
			param = action[0]
			require_sudo = len(action) == 2 and action[1]

			if require_sudo and not IS_SUDO:
				print('ERROR: This option requires sudo / root privileges.')
				continue

			prompt_option(service.game, param)


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


def menu_backup(game: GameApp, max_backups: int = 0):
	"""
	Backup the game server files

	:param game:
	:param max_backups: Maximum number of backups to keep (0 = unlimited)
	:return:
	"""
	target_dir = os.path.join(here, 'backups')
	temp_store = os.path.join(here, '.save')

	if not os.path.exists(SAVE_DIR):
		print('Save directory %s does not exist, cannot continue!' % SAVE_DIR, file=sys.stderr)
		sys.exit(1)

	# Ensure target directory exists; this will store the finalized backups
	if not os.path.exists(target_dir):
		os.makedirs(target_dir)
		if IS_SUDO:
			subprocess.run(['chown', '%s:%s' % (GAME_USER, GAME_USER), target_dir])

	# Temporary directories for various file sources
	for d in ['config', 'save']:
		p = os.path.join(temp_store, d)
		if not os.path.exists(p):
			os.makedirs(p)

	# Copy the various configuration files used by the game
	for cfg in game.configs.values():
		src = cfg.path
		dst = os.path.join(temp_store, 'config', os.path.basename(src))
		if os.path.exists(src):
			shutil.copy(src, dst)

	# Copy all files from the save directory
	for f in os.listdir(SAVE_DIR):
		src = os.path.join(SAVE_DIR, f)
		dst = os.path.join(temp_store, 'save', f)
		if not os.path.isdir(src):
			shutil.copy(src, dst)

	# Ensure ownership is correct
	if IS_SUDO:
		subprocess.run(['chown', '-R', '%s:%s' % (GAME_USER, GAME_USER), temp_store])

	# Create the final archive
	timestamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
	backup_name = '%s-backup-%s.tar.gz' % (game.name, timestamp)
	backup_path = os.path.join(target_dir, backup_name)
	shutil.make_archive(backup_path[:-7], 'gztar', temp_store)

	# Cleanup
	shutil.rmtree(temp_store)

	# Remove old backups if necessary
	if max_backups > 0:
		backups = []
		for f in os.listdir(target_dir):
			if f.startswith('%s-backup-' % game.name) and f.endswith('.tar.gz'):
				full_path = os.path.join(target_dir, f)
				backups.append((full_path, os.path.getmtime(full_path)))
		backups.sort(key=lambda x: x[1])  # Sort by modification time
		while len(backups) > max_backups:
			old_backup = backups.pop(0)
			os.remove(old_backup[0])
			print('Removed old backup: %s' % old_backup[0])

	print('Backup saved to %s' % backup_path)
	sys.exit(0)


def menu_restore(game: GameApp, path: str):
	"""
	Restore the game server files

	:param game: Game service to restore
	:param path: Path to the backup archive
	:return:
	"""
	temp_store = os.path.join(here, '.save')

	if not os.path.exists(SAVE_DIR):
		print('Save directory %s does not exist, cannot continue!' % SAVE_DIR, file=sys.stderr)
		sys.exit(1)

	if not os.path.exists(path):
		print('Backup file %s does not exist, cannot continue!' % path, file=sys.stderr)
		sys.exit(1)

	if game.is_active():
		print('Game server is currently running, please stop it before restoring a backup!', file=sys.stderr)
		sys.exit(1)

	if not os.path.exists(temp_store):
		os.makedirs(temp_store)

	# Extract the archive to the temporary location
	shutil.unpack_archive(path, temp_store)

	# Restore the various configuration files used by the game
	for cfg in game.configs.values():
		dst = cfg.path
		src = os.path.join(temp_store, 'config', os.path.basename(dst))
		if os.path.exists(src):
			shutil.copy(src, dst)
			if IS_SUDO:
				subprocess.run(['chown', '%s:%s' % (GAME_USER, GAME_USER), dst])

	# Restore all files to the save directory
	save_src = os.path.join(temp_store, 'save')
	for f in os.listdir(save_src):
		src = os.path.join(save_src, f)
		dst = os.path.join(SAVE_DIR, f)
		if not os.path.isdir(src):
			shutil.copy(src, dst)
			if IS_SUDO:
				subprocess.run(['chown', '%s:%s' % (GAME_USER, GAME_USER), dst])

	# Cleanup
	shutil.rmtree(temp_store)
	print('Restored from %s' % path)
	sys.exit(0)


def menu_get_services(game: GameApp):
	services = game.get_services()
	stats = {}
	for svc in services:
		g = services[svc]

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
			'service': svc,
			'name': game.get_option_value('ServerName'),
			'ip': get_wan_ip(),
			'port': game.get_option_value('GamePort'),
			'status': status,
			'enabled': g.is_enabled(),
			'player_count': g.get_player_count(),
			'max_players': game.get_option_value('MaxPlayers'),
			'memory_usage': g.get_memory_usage(),
			'cpu_usage': g.get_cpu_usage(),
			'game_pid': g.get_game_pid(),
			'service_pid': g.get_pid(),
			'pre_exec': pre_exec,
			'start_exec': start_exec,
		}
		stats[svc] = svc_stats
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
	for key in ManagerConfig.messages:
		opts.append({
			'option': key,
			'default': ManagerConfig.messages[key]['default'],
			'value': ManagerConfig.get_message(key),
			'type': 'str'
		})

	print(json.dumps(opts))
	sys.exit(0)


def menu_set_game_config(game: GameApp, option: str, value: str):
	"""
	Set a configuration option for the game
	:param game:
	:param option:
	:param value:
	:return:
	"""
	for key in ManagerConfig.messages:
		if option == key:
			ManagerConfig.set_message(option, value)
			print('Option %s set to %s' % (option, value))
			sys.exit(0)

	print('Option not valid', file=sys.stderr)
	sys.exit(1)


def menu_get_service_configs(service: GameService):
	"""
	List the available configuration files for this game (JSON encoded)
	:param game:
	:param service:
	:return:
	"""
	opts = []
	# Get per-service configs
	for opt in service.game.get_options():
		opts.append({
			'option': opt,
			'default': service.game.get_option_default(opt),
			'value': service.game.get_option_value(opt),
			'type': service.game.get_option_type(opt),
			'help': service.game.get_option_help(opt)
		})

	print(json.dumps(opts))
	sys.exit(0)


def menu_set_service_config(service: GameService, option: str, value: str):
	"""
	Set a configuration option for the game
	:param game:
	:param service:
	:param option:
	:param value:
	:return:
	"""
	if option in service.game.get_options():
		service.game.set_option(option, value)
		print('Option %s set to %s' % (option, value))
		sys.exit(0)

	print('Option not valid', file=sys.stderr)
	sys.exit(1)


def menu_messages():
	"""
	Management interface to view/edit player messages for various events
	:return:
	"""
	messages = []
	for key in ManagerConfig.messages:
		messages.append((key, ManagerConfig.messages[key]['title']))

	while True:
		print_header('Player Messages')
		print('The following messages will be sent to players when certain events occur.')
		print('')
		counter = 0
		for key, title in messages:
			counter += 1
			print('| %s | %s | %s' % (str(counter).ljust(2), title.ljust(28), ManagerConfig.get_message(key)))

		print('')
		opt = input('[1-%s] change message | [B]ack: ' % counter).lower()
		key = None
		val = ''

		if opt == 'b':
			return
		elif str.isnumeric(opt) and 1 <= int(opt) <= counter:
			key = messages[int(opt)-1][0]
			print('')
			print('Edit the message, left/right works to move cursor.  Blank to use default.')
			val = prompt_text('%s: ' % messages[int(opt)-1][1], default=ManagerConfig.get_message(key), prefill=True)
		else:
			print('Invalid option')

		if key is not None:
			ManagerConfig.set_message(key, val)


def menu_main(game: GameApp):
	stay = True
	while stay:
		running = game.is_active()
		print_header('Welcome to the %s Server Manager' % game.desc)
		if REPO:
			print('Find an issue? https://github.com/%s/issues' % REPO)
		if FUNDING:
			print('Want to help support this project? %s' % FUNDING)
		print('')
		table = Table(['num', 'map', 'session', 'port', 'rcon', 'enabled', 'running', 'memory', 'players'])
		for service in game.get_services().values():
			service.add_to_table(table)
		table.render()

		print('')
		print('1-%s to manage individual map settings' % len(services))
		print('Configure: [M]ods | [C]luster | [A]dmin password/RCON | re[N]ame | [D]iscord integration | [P]layer messages')
		print('Control: [S]tart all | s[T]op all | [R]estart all | [U]pdate')
		if running:
			print('Manage Data: (please stop all maps to manage game data)')
		else:
			print('Manage Data: [B]ackup/Restore | [W]ipe User Data')
		print('or [Q]uit to exit')
		opt = input(': ').lower()

		if opt == 'a':
			menu_admin_password()
		elif opt == 'b':
			if running:
				print('⚠️  Please stop all maps before managing backups.')
			else:
				menu_backup_restore()
		elif opt == 'c':
			menu_cluster()
		elif opt == 'd':
			menu_discord()
		elif opt == 'm':
			menu_mods()
		elif opt == 'n':
			if running:
				print('⚠️  Please stop all maps before renaming.')
			else:
				val = input('Please enter new name: ').strip()
				if val != '':
					for s in services:
						s.rename(val)
		elif opt == 'p':
			menu_messages()
		elif opt == 'q':
			stay = False
		elif opt == 'r':
			safe_restart(services)
		elif opt == 's':
			safe_start(services)
		elif opt == 't':
			safe_stop(services)
		elif opt == 'u':
			if running:
				print('⚠️ Please stop all maps prior to updating.')
			else:
				subprocess.run([os.path.join(here, 'update.sh')], stderr=sys.stderr, stdout=sys.stdout)
		elif opt == 'w':
			if running:
				print('⚠️  Please stop all maps before wiping user data.')
			else:
				menu_wipe()
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
	'--is-running',
	help='Check if any game service is currently running (exit code 0 = yes, 1 = no)',
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
	if args.service not in services:
		print('Service instance %s not found!' % args.service, file=sys.stderr)
		sys.exit(1)
	services = {args.service: services[args.service]}

if args.pre_stop:
	for svc in services:
		g = services[svc]
		g.pre_stop()
elif args.stop:
	for svc in services:
		g = services[svc]
		g.stop()
elif args.start:
	for svc in services:
		g = services[svc]
		g.start()
elif args.restart:
	for svc in services:
		g = services[svc]
		g.restart()
elif args.monitor:
	if len(services) > 1:
		print('ERROR: --monitor can only be used with a single service instance at a time.', file=sys.stderr)
		sys.exit(1)
	g = list(services.values())[0]
	menu_monitor(g)
elif args.logs:
	if len(services) > 1:
		print('ERROR: --log can only be used with a single service instance at a time.', file=sys.stderr)
		sys.exit(1)
	g = list(services.values())[0]
	g.print_logs()
elif args.backup:
	menu_backup(game, args.max_backups)
elif args.restore != '':
	menu_restore(game, args.restore)
elif args.check_update:
	menu_check_update(game)
elif args.get_services:
	menu_get_services(game)
elif args.get_configs:
	if args.service == 'ALL':
		menu_get_game_configs(game)
	else:
		g = list(services.values())[0]
		menu_get_service_configs(g)
elif args.set_config != None:
	option, value = args.set_config
	if args.service == 'ALL':
		menu_set_game_config(game, option, value)
	else:
		g = list(services.values())[0]
		menu_set_service_config(g, option, value)
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
