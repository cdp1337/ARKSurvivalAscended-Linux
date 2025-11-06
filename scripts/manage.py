#!/usr/bin/env python3

import os
import shutil
import sys
from time import sleep, time
from typing import Union

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
#sys.path.insert(0, os.path.join(here, 'libs'))

import subprocess
import readline
import re
from rcon.source import Client
from rcon import SessionTimeout
from rcon.exceptions import WrongPassword
import configparser
from urllib import request
from urllib import error as urlerror
import json


# Require sudo / root to run this script
if os.geteuid() != 0:
	print("This script must be run as root")
	sys.exit(1)


def rlinput(prompt, prefill=''):
	"""
	Use Readline to read input with a pre-filled value that can be edited by the user
	:param prompt:
	:param prefill:
	:return:
	"""
	readline.set_startup_hook(lambda: readline.insert_text(prefill))
	try:
		return input(prompt)  # or raw_input in Python 2
	finally:
		readline.set_startup_hook()


def str_len(s: str) -> int:
	"""
	Regular len(s) but counts emoji as 2 characters
	:param s:
	:return:
	"""
	length = 0
	for c in s:
		if ord(c) > 0xFFF:
			length += 2
		else:
			length += 1
	return length


def str_ljust(s: str, length: int) -> str:
	"""
	Regular str.ljust() but counts emoji as 2 characters
	:param s:
	:param length:
	:return:
	"""
	characters = len(s)
	width = str_len(s)
	return s.ljust(length - (width - characters))


def discord_alert(message: str, parameters: list):
	enabled = config['Discord'].get('enabled', '0') == '1'
	webhook = config['Discord'].get('webhook', '')
	message = Messages.get(message)

	# Verify the number of '%s' replacements in the string
	# This is important because this is a user-definable string, and users may forget to include '%s'.
	if message.count('%s') < len(parameters):
		message = message + ' %s' * (len(parameters) - message.count('%s'))
	message = message % tuple(parameters)

	if enabled and webhook != '':
		print('Sending to discord: ' + message)
		req = request.Request(
			webhook,
			headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0'},
			method='POST'
		)
		data = json.dumps({'content': message}).encode('utf-8')
		try:
			with request.urlopen(req, data=data) as resp:
				pass
		except urlerror.HTTPError as e:
			print('Could not notify Discord: %s' % e)
	else:
		print('Would be sent to discord: ' + message)


class Messages:
	messages = {
		'map_started': {
			'title': 'Map Started (Discord)',
			'default': ':green_square: %s has started'
		},
		'map_stopping': {
			'title': 'Map Stopping (Discord)',
			'default': ':small_red_triangle_down: %s shutting down'
		},
		'maps_stopping': {
			'title': 'Maps Stopping (Discord)',
			'default': ':small_red_triangle_down: Shutting down: %s'
		},
		'shutdown_5min': {
			'title': 'Shutdown Warning 5 Minutes',
			'default': 'Server is shutting down in 5 minutes'
		},
		'shutdown_4min': {
			'title': 'Shutdown Warning 4 Minutes',
			'default': 'Server is shutting down in 4 minutes'
		},
		'shutdown_3min': {
			'title': 'Shutdown Warning 3 Minutes',
			'default': 'Server is shutting down in 3 minutes'
		},
		'shutdown_2min': {
			'title': 'Shutdown Warning 2 Minutes',
			'default': 'Server is shutting down in 2 minutes'
		},
		'shutdown_1min': {
			'title': 'Shutdown Warning 1 Minute',
			'default': 'Server is shutting down in 1 minute'
		},
		'shutdown_30sec': {
			'title': 'Shutdown Warning 30 Seconds',
			'default': 'Server is shutting down in 30 seconds!'
		},
		'shutdown_now': {
			'title': 'Shutdown Warning NOW',
			'default': 'Server is shutting down NOW!'
		},
	}

	@classmethod
	def get(cls, msg: str) -> str:
		"""
		Get the user-defined message or default value if not configured

		:param msg:
		:return:
		"""
		if msg not in cls.messages:
			# Message not defined; just return the input message key
			return msg

		legacy_discords = ('map_started', 'map_stopping', 'maps_stopping')

		configured_message = config['Messages'].get(msg, '')
		if configured_message == '':
			# No configured message, check Discord legacy keys or use default.
			if msg in legacy_discords:
				# The management system prior to 2025.10.31 stored Discord messages in Discord.
				configured_message = config['Discord'].get(msg, '')

		return configured_message if configured_message != '' else cls.messages[msg]['default']


class Services:
	"""
	Service definition and handler
	"""
	def __init__(self, file):
		"""
		Initialize and load the service definition
		:param file:
		"""
		self.file = file
		self.name = file.split('/')[-1].replace('.conf', '')
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
				args = extracted_keys.group('args') + ' '
				self.session = None
				self.port = None
				self.mods = []
				self.cluster_id = None
				self.other_options = ''
				self.other_flags = ''
				self.options = {}

				# Use a tokenizer to parse options and flags
				options_done = False
				quote = None
				param = ''
				for c in args:
					if quote is None and c in ['"', "'"]:
						quote = c
						continue
					if quote is not None and c == quote:
						quote = None
						continue

					if not options_done and quote is None and c in ['?', ' ']:
						# '?' separates options
						if '=' in param:
							opt_key, opt_val = param.split('=', 1)
							if opt_key == 'SessionName':
								self.session = opt_val
							else:
								self.options[opt_key] = opt_val
						else:
							self.options[param] = ''
						param = ''
						if c == ' ':
							options_done = True
						continue

					if options_done and quote is None and c == '-':
						# Tack can be safely ignored
						continue

					if options_done and c == ' ':
						# ' ' separates flags
						if param == '':
							continue

						if '=' in param:
							opt_key, opt_val = param.split('=', 1)
						else:
							opt_key = param
							opt_val = ''

						if opt_key.lower() == 'port':
							self.port = opt_val
						elif opt_key.lower() == 'mods':
							if ',' in opt_val:
								self.mods += opt_val.split(',')
							else:
								self.mods.append(opt_val)
						elif opt_key.lower() == 'clusterid':
							self.cluster_id = opt_val
						else:
							self.other_flags += '-' + param + ' '

						param = ''
						continue

					# Default behaviour; just append the character
					param += c

				self.other_flags = self.other_flags.strip()


	def save(self):
		"""
		Save the service definition back to the service file
		and reload systemd with the new updates.
		:return:
		"""
		options = '?'.join([
			self.map,
			'listen',
			'SessionName="%s"' % self.session
		])

		for key, val in self.options.items():
			if val == '':
				options += '?%s' % key
			elif '?' in val or "'" in val or ' ' in val:
				options += '?%s="%s"' % (key, val)
			else:
				options += '?%s=%s' % (key, val)

		# Strip excessive question marks
		options = options.replace('????', '?')
		options = options.replace('???', '?')
		options = options.replace('??', '?')

		flags = '-port=%s' % self.port

		if len(self.mods):
			flags += ' -mods=%s' % ','.join(self.mods)
		if self.cluster_id:
			flags += ' -clusterid=%s' % self.cluster_id
		if self.other_flags:
			flags += ' ' + self.other_flags

		line = 'ExecStart=%s run ArkAscendedServer.exe %s %s' % (self.runner, options, flags)

		# Save the compiled line back to the service file, (along with the header)
		with open(self.file, 'w') as f:
			f.write('[Service]\n')
			f.write('# Edit this line to adjust start parameters of the server\n')
			f.write('# After modifying, please remember to run  to apply changes to the system.\n')
			f.write(line + '\n')

		# Reload the service
		subprocess.run(['systemctl', 'daemon-reload'])

	def _rcon_cmd(self, cmd) -> Union[None,str]:
		"""
		Execute a raw command with RCON and return the result

		:param cmd:
		:return: None if RCON not available, or the result of the command
		"""
		if not self.is_running():
			# If service is not running, don't even try to connect.
			return None

		if not self.is_rcon_available():
			# RCON is not available due to settings
			return None

		try:
			port = int(self.get_option('RCONPort', only_override=True))
			pswd = self.get_option('ServerAdminPassword')
			with Client('127.0.0.1', port, passwd=pswd, timeout=2) as client:
				return client.run(cmd).strip()
		except:
			return None

	def rcon_get_number_players(self) -> Union[None, int]:
		"""
		Get the total number of players currently logged in,
		or None if RCON is not available
		:return:
		"""
		ret =  self._rcon_cmd('ListPlayers')
		if ret is None:
			return None
		elif ret == 'No Players Connected':
			return 0
		else:
			return len(ret.split('\n'))

	def rcon_save_world(self):
		"""
		Issue a Save command on the server
		:return:
		"""
		self._rcon_cmd('SaveWorld')

	def rcon_message(self, message: str):
		"""
		Send a message to the game server
		:param message:
		:return:
		"""
		self._rcon_cmd('ServerChat %s' % message)

	def get_map_description(self) -> str:
		if self.map == 'BobsMissions_WP':
			return 'Club'
		elif self.map.endswith('_WP'):
			return self.map[:-3]
		else:
			return self.map

	def rename(self, new_name):
		"""
		Rename the session name
		:param new_name:
		:return:
		"""
		new_name = new_name.replace('"', '')
		if config['Manager'].get('JoinedSessionName', 'True') == 'True':
			# Add the map description to the session name if enabled (default option)
			new_name = new_name + ' (' + self.get_map_description() + ')'

		self.session = new_name
		self.save()

	def is_enabled(self) -> bool:
		"""
		Check if this service is enabled in systemd
		:return:
		"""
		return subprocess.run(
			['systemctl', 'is-enabled', self.name],
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
			check=False
		).stdout.decode().strip() == 'enabled'

	def is_running(self) -> bool:
		"""
		Check if this service is currently running
		:return:
		"""
		return subprocess.run(
			['systemctl', 'is-active', self.name],
			stdout=subprocess.PIPE
		).stdout.decode().strip() == 'active'

	def is_rcon_available(self) -> bool:
		"""
		Check if RCON is enabled for this service
		:return:
		"""
		return (
			self.get_option('RCONEnabled') == 'True' and
			self.get_option('RCONPort', only_override=True) != '' and
			self.get_option('ServerAdminPassword') != ''
		)

	def enable(self):
		"""
		Enable this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'enable', self.name])

	def disable(self):
		"""
		Disable this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'disable', self.name])

	def start(self):
		"""
		Start this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'start', self.name])

	def stop(self):
		"""
		Stop this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'stop', self.name])

	def restart(self):
		"""
		Restart this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'restart', self.name])

	def get_mod_names(self) -> list:
		"""
		Get the list of mod names for this service
		:return:
		"""
		names = []
		for mod in self.mods:
			mod_name = ModLibrary.resolve_mod_name(mod)
			if mod_name is not None:
				names.append(mod_name + ' (' + mod + ')')
			else:
				names.append('⚠️  NOT INSTALLED (' + mod + ')')
		return names

	def get_pid(self) -> int:
		"""
		Get the PID of the running service, or 0 if not running
		:return:
		"""
		pid = subprocess.run([
			'systemctl', 'show', '-p', 'MainPID', self.name
		], stdout=subprocess.PIPE).stdout.decode().strip()[8:]

		return int(pid)

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

	def get_memory_usage(self) -> str:
		"""
		Get the formatted memory usage of the service, or N/A if not running
		:return:
		"""

		pid = self.get_game_pid()

		if pid == 0:
			return 'N/A'

		mem = subprocess.run([
			'ps', 'h', '-p', str(pid), '-o', 'rss'
		], stdout=subprocess.PIPE).stdout.decode().strip()

		if mem.isdigit():
			mem = int(mem)
			if mem >= 1024 * 1024:
				mem_gb = mem / (1024 * 1024)
				return '%.2f GB' % mem_gb
			else:
				mem_mb = mem // 1024
				return '%.0f MB' % mem_mb
		else:
			return 'N/A'

	def get_cpu_usage(self) -> str:
		"""
		Get the formatted CPU usage of the service, or N/A if not running
		:return:
		"""

		pid = self.get_game_pid()

		if pid == 0:
			return 'N/A'

		cpu = subprocess.run([
			'ps', 'h', '-p', str(pid), '-o', '%cpu'
		], stdout=subprocess.PIPE).stdout.decode().strip()

		if cpu.replace('.', '', 1).isdigit():
			return '%.0f%%' % float(cpu)
		else:
			return 'N/A'

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

	def get_num_player_profiles(self) -> int:
		"""
		Get the number of player profiles saved for this service
		:return:
		"""
		profiles_path = self.get_saved_location()
		if os.path.exists(profiles_path):
			return len([
				name for name in os.listdir(profiles_path)
				if name.endswith('.arkprofile')
			])
		return 0

	def get_map_file_size(self) -> int:
		"""
		Get the size of the map data on disk in MB
		:return:
		"""
		map_path = os.path.join(self.get_saved_location(), self.map + '.ark')
		if os.path.exists(map_path):
			return round(os.path.getsize(map_path) // (1024 * 1024))
		else:
			return 0

	def get_option(self, key: str, only_override: bool = False) -> str:
		"""
		Get a specific configuration option for this service,
		from either the service definition or the shared settings.
		:param key: Option key to retrieve
		:param only_override: Set to True to only check the service definition
		:return:
		"""
		if key in self.options:
			return self.options[key]
		elif not only_override and shared_settings is not None:
			return shared_settings['ServerSettings'].get(key, '')
		else:
			return ''

	def get_options(self) -> str:
		"""
		Get all local-defined options as a formatted string
		:return:
		"""
		opts = []
		for key, val in self.options.items():
			# Hide system options
			if key in ('RCONEnabled', 'RCONPort', 'ServerAdminPassword'):
				continue
			if val == '':
				opts.append(key)
			elif '?' in val or "'" in val or ' ' in val:
				opts.append('%s="%s"' % (key, val))
			else:
				opts.append('%s=%s' % (key, val))

		return '?'.join(opts)

	def set_options(self, opts: str):
		"""
		Set all local-defined options from a formatted string
		:param opts:
		:return:
		"""
		# Preserve system options
		options = {}
		for key in ('RCONEnabled', 'RCONPort', 'ServerAdminPassword'):
			val = self.get_option(key, True)
			if val != '':
				options[key] = val

		param = ''
		quote = None
		opts += '?'
		for c in opts:
			if quote is None and c in ['"', "'"]:
				quote = c
				continue

			if quote is not None and c == quote:
				quote = None
				continue

			if quote is None and c == '?':
				if param == '':
					continue

				if '=' in param:
					opt_key, opt_val = param.split('=', 1)
					options[opt_key] = opt_val
				else:
					options[param] = ''

				param = ''
				continue

			param += c

		self.options = options


class Table:
	"""
	Displays a table of data
	"""
	def __init__(self, columns: list):
		"""
		Initialize the table with the columns to display
		:param columns:
		"""
		self.columns = columns
		self.headers = {
			'num': '#',
			'map': 'Map',
			'session': 'Session',
			'port': 'Port',
			'rcon': 'RCON',
			'enabled': 'Auto-Start',
			'running': 'Status',
			'admin_password': 'Admin Password',
			'players': 'Players',
			'mods': 'Mods',
			'cluster': 'Cluster ID',
			'map_size': 'Map Size (MB)',
			'player_profiles': 'Player Profiles',
			'memory': 'Mem',
		}

	def render(self, services: list):
		"""
		Render the table with the given list of services

		:param services: Services[]
		:return:
		"""
		headers = []
		rows = []
		col_lengths = []

		for col in self.columns:
			if col in self.headers:
				col_lengths.append(len(self.headers[col]))
				headers.append(self.headers[col])
			else:
				col_lengths.append(3)
				headers.append('???')

		row_counter = 0
		for service in services:
			row = []
			row_counter += 1
			counter = 0
			for col in self.columns:
				if col == 'num':
					row.append(str(row_counter))
				elif col == 'map':
					row.append(service.map)
				elif col == 'session':
					row.append(service.session)
				elif col == 'port':
					row.append(service.port)
				elif col == 'rcon':
					row.append(service.get_option('RCONPort', True) if service.is_rcon_available() else 'N/A')
				elif col == 'enabled':
					row.append('✅ Enabled' if service.is_enabled() else '❌ Disabled')
				elif col == 'running':
					row.append('✅ Running' if service.is_running() else '❌ Stopped')
				elif col == 'admin_password':
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
				else:
					row.append('???')

				col_lengths[counter] = max(col_lengths[counter], str_len(row[-1]))
				counter += 1
			rows.append(row)

		counter = 0
		vals = []
		while counter < len(headers):
			vals.append(headers[counter].ljust(col_lengths[counter]))
			counter += 1
		print('| %s |' % ' | '.join(vals))

		counter = 0
		vals = []
		while counter < len(headers):
			vals.append('-'.ljust(col_lengths[counter], '-'))
			counter += 1
		print('|-%s-|' % '-|-'.join(vals))

		for row in rows:
			counter = 0
			vals = []
			while counter < len(row):
				vals.append(str_ljust(row[counter], col_lengths[counter]))
				counter += 1
			print('| %s |' % ' | '.join(vals))


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


def _safe_stop_inner(services, time_message):
	"""

	:param services: Services[]
	:param time_message: str
	:return:
	"""
	players_connected = False
	for s in services:
		if s.is_running():
			players = s.rcon_get_number_players()
			if players is None:
				print('Unable to get player count for %s, RCON is probably not available' % s.session)
				s.stop()
			elif players > 0:
				print('%s has %s players connected, sending warning' % (s.session, players))
				s.rcon_message(time_message)
				players_connected = True
			else:
				# RCON enabled, but no players connected.  GREAT!
				print('Saving %s' % s.session)
				s.rcon_save_world()
				sleep(10)
				print('Shutting down %s' % s.session)
				s.stop()
	return players_connected


def print_error_log(num_lines = 20):
	"""
	Print the last lines of the error log
	:param num_lines: Number of lines (default 20) to display
	:return:
	"""
	log_file = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Logs', 'ShooterGame.log')
	subprocess.call(['tail', '-n', str(num_lines), log_file], stdout=sys.stdout)


def safe_stop(services):
	"""
	Safely stop all requested service files
	:param services: Services[]
	:return:
	"""

	maps = []
	for s in services:
		if s.is_running():
			maps.append(s.session)
	if len(maps) > 1:
		discord_alert('maps_stopping', [', '.join(maps)])
	elif len(maps) == 1:
		discord_alert('map_stopping', [maps[0]])

	players_connected = _safe_stop_inner(services, Messages.get('shutdown_5min'))

	if players_connected:
		print('Waiting a minute until the next warning (5 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_4min'))

	if players_connected:
		print('Waiting a minute until the next warning (4 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_3min'))

	if players_connected:
		print('Waiting a minute until the next warning (3 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_2min'))

	if players_connected:
		print('Waiting a minute until the next warning (2 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_1min'))

	if players_connected:
		print('Waiting 30 seconds until the next warning (1 minute remaining)')
		sleep(30)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_30sec'))

	if players_connected:
		print('Last warning')
		sleep(30)
		_safe_stop_inner(services, Messages.get('shutdown_now'))

	for s in services:
		if s.is_running():
			players = s.rcon_get_number_players()
			if players is not None:
				# RCON enabled, we can request a manual save
				print('Saving %s' % s.session)
				s.rcon_save_world()
				sleep(10)
			print('Shutting down %s' % s.session)
			s.stop()


def safe_restart(services):
	"""

	:param services: Services[]
	:return:
	"""
	running_services = []
	for s in services:
		if s.is_running():
			running_services.append(s)

	safe_stop(running_services)

	print('Running maps have been stopped, waiting a moment to restart them')
	sleep(5)
	safe_start(running_services, True)


def safe_start(services, ignore_enabled = False):
	"""
	Start all enabled services that are not currently running
	:param services: Services[]
	:param ignore_enabled: bool Set to True to ignore the enabled flag
	:return:
	"""
	for s in services:
		if not s.is_enabled() and not ignore_enabled:
			print('Skipping disabled map %s' % s.session)
		elif s.is_running():
			print('%s already running' % s.session)
		else:
			start_timer = time()
			print('Starting %s, please wait, may take a minute...' % s.session)
			print('loading................')
			s.start()
			check_counter = 0
			ready = False
			while check_counter < 600:
				check_counter += 1
				# Watch the exit status of the service,
				# if this changes to something other than 0, it indicates a game crash.
				exec_status = int(subprocess.run([
					'systemctl', 'show', '-p', 'ExecMainStatus', s.name
				], stdout=subprocess.PIPE).stdout.decode().strip()[15:])

				if exec_status == 1:
					print_error_log()
					print('❗⛔❗ WARNING - Service has exited with status 1')
					print('This may indicate corrupt files, please check logs and verify files with Steam.')
					return
				elif exec_status == 15:
					print_error_log()
					print('❗⛔❗ WARNING - Service has exited with status 15')
					print('This may indicate that your server ran out of memory.')
					return
				elif exec_status != 0:
					print_error_log()
					print('❗⛔❗ WARNING - Service has exited with status %s' % exec_status)
					return

				if s.get_pid() == 0:
					print_error_log()
					print('❗⛔❗ WARNING - Process has crashed!')
					return

				status_rcon = 'waiting'
				if check_counter >= 120:
					# After a bit of time, start checking if RCON is available.
					# That is the indication that the server is ready.
					if s.is_rcon_available():
						players_connected = s.rcon_get_number_players()
						if players_connected is None:
							status_rcon = '❌'
						else:
							status_rcon = '✅'
							ready = True
					else:
						# RCON is not enabled so we do not know when it's really available.
						status_rcon = '???'
						ready = True

				# Clear the last line status output and provide a new dynamic update
				seconds_elapsed = round(time() - start_timer)
				since_minutes = str(seconds_elapsed // 60)
				since_seconds = seconds_elapsed % 60
				if since_seconds < 10:
					since_seconds = '0' + str(since_seconds)
				else:
					since_seconds = str(since_seconds)
				print(
					'\033[1A\033[K Time: %s, CPU: %s, Memory: %s, RCON: %s' % (
						since_minutes + ':' + since_seconds,
						s.get_cpu_usage(),
						s.get_memory_usage(),
						status_rcon
					)
				)

				if ready:
					discord_alert('map_started', [s.session])
					break

				sleep(0.5)

			if not ready:
				print_error_log()
				print('❗⛔❗ WARNING - Service did not become ready in time, please check logs!')


def save_config():
	"""
	Save the management application configuration to disk
	:return:
	"""
	with open(os.path.join(here, '.settings.ini'), 'w') as f:
		config.write(f)
	os.chmod(os.path.join(here, '.settings.ini'), 0o600)


def header(line):
	"""
	Print a header line
	:param line: string
	:return:
	"""
	#os.system('clear')
	# Instead of clearing the screen, just print some newlines.
	# This way errors from the previous screen will be visible.
	print('')
	print('')
	print('')
	print('')
	print('== %s ==' % line)
	print('')


def menu_service(service):
	"""
	Interface for managing an individual service
	:param service:
	:return:
	"""
	while True:
		ModLibrary.refresh_data()

		header('Service Details')
		running = service.is_running()
		if service.is_rcon_available() and running:
			players = service.rcon_get_number_players()
			if players is None:
				players = 'N/A (unable to retrieve player count)'
		else:
			players = 'N/A'

		# Retrieve the WAN IP of this instance; can be useful for direct access.
		req = request.Request('http://wan.eval.bz', headers={'User-Agent': 'ARK-Ascended-Management'}, method='GET')
		try:
			with request.urlopen(req) as resp:
				wan = resp.read().decode('utf-8')
		except urlerror.HTTPError:
			wan = 'N/A'
		except urlerror.URLError:
			wan = 'N/A'
		except json.JSONDecodeError:
			wan = 'N/A'

		print('Map:         %s' % service.map)
		print('Session:     %s' % service.session)
		print('WAN IP:      %s' % wan)
		print('Port:        %s (UDP)' % service.port)
		print('RCON:        %s (TCP)' % service.get_option('RCONPort', True))
		print('Auto-Start:  %s' % ('Yes' if service.is_enabled() else 'No'))
		print('Status:      %s' % ('Running' if running else 'Stopped'))
		print('Players:     %s' % players)
		print('Mods:        %s' % '\n             '.join(service.get_mod_names()))
		print('Cluster ID:  %s' % (service.cluster_id or ''))
		print('Options:     %s' % service.get_options())
		print('Flags:       %s' % service.other_flags)
		if running:
			print('Memory:      %s' % service.get_memory_usage())
			print('CPU:         %s' % service.get_cpu_usage())
			print('Map Size:    %s MB' % service.get_map_file_size())
			connect_pw = service.get_option('ServerPassword')
			if connect_pw == '':
				print('Connect Cmd: open %s:%s' % (wan, service.port))
			else:
				print('Connect Cmd: open %s:%s?%s' % (wan, service.port, connect_pw))
		print('')

		# Check for common recent issues with the server
		log = subprocess.run([
			'journalctl', '--since', '10 minutes ago', '--no-pager', '-u', service.name
		], stdout=subprocess.PIPE).stdout.decode().strip()
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
			options.append('[M]ods | [C]luster | re[N]ame | [F]lags | [O]ptions')

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
				if val in service.mods:
					service.mods.remove(val)
				else:
					service.mods.append(val)
				service.save()
		elif opt == 'c':
			val = rlinput('Enter new cluster id: ', service.cluster_id).strip()
			service.cluster_id = val
			service.save()
		elif opt == 'n':
			name = service.session
			if '(' in name:
				name = name[:name.index('(')]
			val = rlinput('Please enter new name: ', name).strip()
			if val != '':
				service.rename(val)
		elif opt == 'f':
			val = rlinput('Enter new flags: ', service.other_flags).strip()
			service.other_flags = val
			service.save()
		elif opt == 'o':
			print('')
			print('Enter options for this map seperated by a question mark (?).')
			val = rlinput('Enter new options: ', service.get_options()).strip()
			service.set_options(val)
			service.save()
		elif opt == 's':
			safe_start([service], True)
		elif opt == 't':
			safe_stop([service])
		elif opt == 'r':
			safe_restart([service])
		else:
			print('Invalid option')


def menu_mods():
	"""
	Interface to manage mods across all maps
	:return:
	"""
	while True:
		# Pull mod data to know which mods are unused
		ModLibrary.refresh_data()
		mods_installed = ModLibrary.get_mods()
		mods_used = []

		running = False
		for service in services:
			if service.is_running():
				running = True
			for mod in service.mods:
				if mod not in mods_used:
					mods_used.append(mod)
		header('Mods Configuration')
		table = Table(['session', 'mods', 'running'])
		table.render(services)
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
					if val not in s.mods:
						s.mods.append(val)
						s.save()
		elif opt == 'd':
			val = input('Enter the mod ID to disable: ').strip()
			if val != '':
				for s in services:
					if val in s.mods:
						s.mods.remove(val)
						s.save()
		else:
			print('Invalid option')


def menu_cluster():
	while True:
		running = False
		for service in services:
			if service.is_running():
				running = True
		header('Cluster Configuration')
		table = Table(['session', 'cluster', 'running'])
		table.render(services)
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
				if s.cluster_id and s.cluster_id not in vals:
					vals.append(s.cluster_id)
			if len(vals) == 1:
				val = rlinput('Enter new cluster id: ', vals[0]).strip()
			else:
				val = input('Enter new cluster id: ').strip()
			for s in services:
				s.cluster_id = val
				s.save()
		else:
			print('Invalid option')


def menu_admin_password():
	"""
	Interface to manage rcon and administration password
	:return:
	"""
	while True:
		running = False
		header('Admin and RCON Configuration')
		table = Table(['session', 'admin_password', 'rcon', 'running'])
		table.render(services)
		for service in services:
			if service.is_running():
				running = True
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
				s.options['RCONEnabled'] = 'True'
				s.save()
		elif opt == 'd' and not running:
			print('WARNING - disabling RCON will prevent clean shutdowns!')
			for s in services:
				s.options['RCONEnabled'] = 'False'
				s.save()
		elif opt == 'c' and not running:
			val = input('Enter new password: ').strip()
			if val:
				for s in services:
					s.options['ServerAdminPassword'] = val.replace('"', '').replace(' ', '')
					s.save()
		else:
			print('Invalid option')


def menu_discord():
	while True:
		header('Discord Integration')
		enabled = config['Discord'].get('enabled', '0') == '1'
		webhook = config['Discord'].get('webhook', '')
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
				config['Discord']['webhook'] = opt
				config['Discord']['enabled'] = '1'
				save_config()
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
			except urlerror.HTTPError as e:
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
					config['Discord']['webhook'] = val
					save_config()
			elif opt == 'e':
				config['Discord']['enabled'] = '1'
				save_config()
			elif opt == 'd':
				config['Discord']['enabled'] = '0'
				save_config()
			else:
				print('Invalid option')


def menu_messages():
	messages = []
	for key in Messages.messages:
		messages.append((key, Messages.messages[key]['title']))

	while True:
		header('Player Messages')
		print('The following messages will be sent to players when certain events occur.')
		print('')
		counter = 0
		for key, title in messages:
			counter += 1
			print('| %s | %s | %s' % (str(counter).ljust(2), title.ljust(28), Messages.get(key)))

		print('')
		opt = input('[1-%s] change message | [B]ack: ' % counter).lower()
		key = None
		val = ''

		if opt == 'b':
			return
		elif 1 <= int(opt) <= counter:
			key = messages[int(opt)-1][0]
			print('')
			print('Edit the message, left/right works to move cursor.  Blank to use default.')
			val = rlinput('%s: ' % messages[int(opt)-1][1], Messages.get(key)).strip()
		else:
			print('Invalid option')

		if key is not None:
			config['Messages'][key] = val.replace('%', '%%')
			save_config()


def menu_backup_restore():
	while True:
		header('Backups and Restore')
		print('')
		backups = []
		if os.path.exists(os.path.join(here, 'backups')):
			for f in os.listdir(os.path.join(here, 'backups')):
				if f.endswith('.tgz'):
					backups.append(f)
		print('Existing Backups:')
		counter = 0
		for b in backups:
			counter += 1
			backup_size = os.path.getsize(os.path.join(here, 'backups', b))
			backup_size_mb = round(backup_size / (1024 * 1024))
			print('%s - %s (%s MB)' % (counter, b, backup_size_mb))
		if len(backups) == 0:
			print('No backups found')

		print('')
		if len(backups) > 0:
			print('Enter 1-%s to restore a backup' % len(backups))
		print('[N]ew Backup | [B]ack')
		opt = input(': ').lower()

		if opt == 'n':
			print('Creating new backup... please wait a moment')
			subprocess.run([os.path.join(here, 'backup.sh')], stderr=sys.stderr, stdout=sys.stdout)
		elif opt == 'b':
			return
		elif opt.isdigit() and 1 <= int(opt) <= len(backups):
			print('Restoring a backup will overwrite existing game data!  Continue? [y/N]')
			confirm = input(': ').lower()
			if confirm == 'y':
				print('Restoring backup... please wait a moment')
				subprocess.run([os.path.join(here, 'restore.sh'), 'backups/' + backups[int(opt)-1]], stderr=sys.stderr, stdout=sys.stdout)


def menu_wipe():
	while True:
		header('Wipe User Data')
		print('Wiping user data will remove all player progress, including characters, items, and structures.')
		print('This action is irreversible and will reset the game to its initial state.')
		print('')
		table = Table(['num', 'map', 'map_size', 'player_profiles'])
		table.render(services)

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


def menu_main():
	stay = True
	while stay:
		running = False
		for s in services:
			if s.is_running():
				running = True
		header('Welcome to the ARK Survival Ascended Linux Server Manager')
		print('Find an issue? https://github.com/cdp1337/ARKSurvivalAscended-Linux/issues')
		print('Want to help support this project? https://ko-fi.com/bitsandbytes')
		print('')
		table = Table(['num', 'map', 'session', 'port', 'rcon', 'enabled', 'running', 'memory', 'players'])
		table.render(services)

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

# Get the script configuration, useful for settings not directly related to the game
config = configparser.ConfigParser()
config.read(os.path.join(here, '.settings.ini'))
if 'Discord' not in config.sections():
	config['Discord'] = {}
if 'Messages' not in config.sections():
	config['Messages'] = {}
if 'Manager' not in config.sections():
	config['Manager'] = {}

shared_settings = None
shared_path = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'GameUserSettings.ini')
if os.path.exists(shared_path):
	shared_settings = configparser.ConfigParser(strict=False)
	shared_settings.read(shared_path)
	if 'ServerSettings' not in shared_settings.sections():
		shared_settings['ServerSettings'] = {}

services = []
services_path = os.path.join(here, 'services')
for f in os.listdir(services_path):
	if f.endswith('.conf'):
		services.append(Services(os.path.join(services_path, f)))


if '--stop-all' in sys.argv:
	safe_stop(services)
elif '--backup' in sys.argv:
	# Stop all services prior to backup
	safe_stop(services)
	# Run the backup procedure
	subprocess.run([os.path.join(here, 'backup.sh')], stderr=sys.stderr, stdout=sys.stdout)
	# Start all enabled service
	safe_start(services)
elif '--start-all' in sys.argv:
	safe_start(services)
elif '--is-running' in sys.argv:
	for s in services:
		if s.is_running():
			sys.exit(0)
	sys.exit(1)
else:
	menu_main()
