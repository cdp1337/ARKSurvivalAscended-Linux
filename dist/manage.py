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
import sys
import subprocess
import readline
from typing import Union
import os
import re
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
import yaml
from rcon.source import Client
from rcon import SessionTimeout
from rcon.exceptions import WrongPassword
import tempfile

def get_enabled_firewall() -> str:
	"""
	Returns the name of the enabled firewall on the system.
	Checks for UFW, Firewalld, and iptables in that order.

	Returns:
		str: The name of the enabled firewall ('ufw', 'firewalld', 'iptables') or 'none' if none are enabled.
	"""

	# Check for UFW
	try:
		ufw_status = subprocess.run(['ufw', 'status'], capture_output=True, text=True)
		if 'Status: active' in ufw_status.stdout:
			return 'ufw'
	except FileNotFoundError:
		pass

	# Check for Firewalld
	try:
		firewalld_status = subprocess.run(['firewall-cmd', '--state'], capture_output=True, text=True)
		if 'running' in firewalld_status.stdout:
			return 'firewalld'
	except FileNotFoundError:
		pass

	# Check for iptables
	try:
		iptables_status = subprocess.run(['iptables', '-L'], capture_output=True, text=True)
		if iptables_status.returncode == 0:
			return 'iptables'
	except FileNotFoundError:
		pass

	return 'none'

def get_available_firewall() -> str:
	"""
	Returns the name of the available firewall on the system.
	Checks for UFW, Firewalld, and iptables in that order.

	Returns:
		str: The name of the available firewall ('ufw', 'firewalld', 'iptables') or 'none' if none are available.
	"""

	# Check for UFW
	try:
		subprocess.run(['ufw', '--version'], capture_output=True, text=True)
		return 'ufw'
	except FileNotFoundError:
		pass

	# Check for Firewalld
	try:
		subprocess.run(['firewall-cmd', '--version'], capture_output=True, text=True)
		return 'firewalld'
	except FileNotFoundError:
		pass

	# Check for iptables
	try:
		subprocess.run(['iptables', '--version'], capture_output=True, text=True)
		return 'iptables'
	except FileNotFoundError:
		pass

	return 'none'

def firewall_allow(port: int, protocol: str = 'tcp', comment: str = None) -> None:
	"""
	Allows a specific port through the system's firewall.
	Supports UFW, Firewalld, and iptables.

	Args:
		port (int): The port number to allow.
		protocol (str, optional): The protocol to use ('tcp' or 'udp'). Defaults to 'tcp'.
		comment (str, optional): An optional comment for the rule. Defaults to None.
	"""

	firewall = get_available_firewall()

	if firewall == 'ufw':
		cmd = ['ufw', 'allow', f'{port}/{protocol}']
		if comment:
			cmd.extend(['comment', comment])
		subprocess.run(cmd, check=True)

	elif firewall == 'firewalld':
		cmd = ['firewall-cmd', '--permanent', '--add-port', f'{port}/{protocol}']
		subprocess.run(cmd, check=True)
		subprocess.run(['firewall-cmd', '--reload'], check=True)

	elif firewall == 'iptables':
		cmd = ['iptables', '-A', 'INPUT', '-p', protocol, '--dport', str(port), '-j', 'ACCEPT']
		if comment:
			cmd.extend(['-m', 'comment', '--comment', comment])
		subprocess.run(cmd, check=True)
		subprocess.run(['service', 'iptables', 'save'], check=True)

	else:
		print('No supported firewall found on the system.', file=sys.stderr)

def firewall_remove(port: int, protocol: str = 'tcp') -> None:
	"""
	Removes a specific port from the system's firewall.
	Supports UFW, Firewalld, and iptables.

	Args:
		port (int): The port number to remove.
		protocol (str, optional): The protocol to use ('tcp' or 'udp'). Defaults to 'tcp'.
	"""

	firewall = get_available_firewall()

	if firewall == 'ufw':
		cmd = ['ufw', 'delete', 'allow', f'{port}/{protocol}']
		subprocess.run(cmd, check=True)

	elif firewall == 'firewalld':
		cmd = ['firewall-cmd', '--permanent', '--remove-port', f'{port}/{protocol}']
		subprocess.run(cmd, check=True)
		subprocess.run(['firewall-cmd', '--reload'], check=True)

	elif firewall == 'iptables':
		cmd = ['iptables', '-D', 'INPUT', '-p', protocol, '--dport', str(port), '-j', 'ACCEPT']
		subprocess.run(cmd, check=True)
		subprocess.run(['service', 'iptables', 'save'], check=True)

	else:
		raise RuntimeError("No supported firewall found on the system.")
##
# Simple Yes/No prompt function for shell scripts

def prompt_yn(prompt: str = 'Yes or no?', default: str = 'y') -> bool:
	"""
	Prompt the user with a Yes/No question and return their response as a boolean.

	Args:
		prompt (str): The question to present to the user.
		default (str, optional): The default answer if the user just presses Enter.
			Must be 'y' or 'n'. Defaults to 'y'.

	Returns:
		bool: True if the user answered 'yes', False if 'no'.
	"""
	valid = {'y': True, 'n': False}
	if default not in valid:
		raise ValueError("Invalid default answer: must be 'y' or 'n'")

	prompt += " [Y/n]: " if default == "y" else " [y/N]: "

	while True:
		choice = input(prompt).strip().lower()
		if choice == "":
			return valid[default]
		elif choice in ['y', 'yes']:
			return True
		elif choice in ['n', 'no']:
			return False
		else:
			print("Please respond with 'y' or 'n'.")


def prompt_text(prompt: str = 'Enter text: ', default: str = '', prefill: bool = False) -> str:
	"""
	Prompt the user to enter text input and return the entered string.

	Arguments:
		prompt (str): The prompt message to display to the user.
		default (str, optional): The default text to use if the user provides no input. Defaults to ''.
		prefill (bool, optional): If True, prefill the input with the default text. Defaults to False.
	Returns:
		str: The text input provided by the user.
	"""
	if prefill:
		readline.set_startup_hook(lambda: readline.insert_text(default))
		try:
			return input(prompt).strip()
		finally:
			readline.set_startup_hook()
	else:
		ret = input(prompt).strip()
		return default if ret == '' else ret


class Table:
	"""
	Displays data in a table format
	"""

	def __init__(self, columns: Union[list, None] = None):
		"""
		Initialize the table with the columns to display
		:param columns:
		"""
		self.header = columns
		"""
		List of table headers to render, or None to omit
		"""

		self.align = []
		"""
		Alignment for each column, l = left, c = center, r = right
		
		eg: if a table has 3 columns and the first and last should be right aligned:
		table.align = ['r', 'l', 'r']
		"""

		self.data = []
		"""
		List of text data to display, add more with `add()`
		"""

		self.borders = True
		"""
		Set to False to disable borders ("|") around the table
		"""

	def _text_width(self, string: str) -> int:
		"""
		Get the visual width of a string, taking into account extended ASCII characters
		:param string:
		:return:
		"""
		width = 0
		for char in string:
			if ord(char) > 127:
				width += 2
			else:
				width += 1
		return width

	def add(self, row: list):
		self.data.append(row)

	def render(self):
		"""
		Render the table with the given list of services

		:param services: Services[]
		:return:
		"""
		rows = []
		col_lengths = []

		if self.header is not None:
			row = []
			for col in self.header:
				col_lengths.append(self._text_width(col))
				row.append(col)
			rows.append(row)
		else:
			col_lengths = [0] * len(self.data[0])

		if self.borders and self.header is not None:
			rows.append(['-BORDER-'] * len(self.header))

		for row_data in self.data:
			row = []
			for i in range(len(row_data)):
				val = str(row_data[i])
				row.append(val)
				col_lengths[i] = max(col_lengths[i], self._text_width(val))
			rows.append(row)

		for row in rows:
			vals = []
			is_border = False
			if self.borders and self.header and row[0] == '-BORDER-':
				is_border = True

			for i in range(len(row)):
				if i < len(self.align):
					align = self.align[i] if self.align[i] != '' else 'l'
				else:
					align = 'l'

				# Adjust the width of the total column width by the difference of icons within the text
				# This is required because icons are 2-characters in visual width.
				if is_border:
					width = col_lengths[i]
					if align == 'r':
						vals.append(' %s:' % ('-' * width,))
					elif align == 'c':
						vals.append(':%s:' % ('-' * width,))
					else:
						vals.append(' %s ' % ('-' * width,))
				else:
					width = col_lengths[i] - (self._text_width(row[i]) - len(row[i]))
					if align == 'r':
						vals.append(row[i].rjust(width))
					elif align == 'c':
						vals.append(row[i].center(width))
					else:
						vals.append(row[i].ljust(width))

			if self.borders:
				if is_border:
					print('|%s|' % '|'.join(vals))
				else:
					print('| %s |' % ' | '.join(vals))
			else:
				print('  %s' % '  '.join(vals))


def print_header(title: str, width: int = 80, clear: bool = False) -> None:
	"""
	Prints a formatted header with a title and optional subtitle.

	Args:
		title (str): The main title to display.
		width (int, optional): The total width of the header. Defaults to 80.
		clear (bool, optional): Whether to clear the console before printing. Defaults to False.
	"""
	if clear:
		# Clear the terminal prior to output
		os.system('cls' if os.name == 'nt' else 'clear')
	else:
		# Just print some newlines
		print("\n" * 3)
	border = "=" * width
	print(border)
	print(title.center(width))
	print(border)


def get_wan_ip() -> Union[str, None]:
	"""
	Get the external IP address of this server
	:return: str: The external IP address as a string, or None if it cannot be determined
	"""
	try:
		with request.urlopen('https://api.ipify.org', timeout=2) as resp:
			return resp.read().decode('utf-8')
	except urllib_error.HTTPError:
		return None
	except urllib_error.URLError:
		return None

def steamcmd_parse_manifest(manifest_content):
	"""
	Parses a SteamCMD manifest file content and returns a dictionary
	with the all the relevant information.

	Example format of content to parse:

	"2131400"
	{
		"common"
		{
			"name"		"VEIN Dedicated Server"
			"type"		"Tool"
			"parent"		"1857950"
			"ReleaseState"		"released"
			"oslist"		"windows,linux"
			"osarch"		"64"
			"osextended"		""
			"icon"		"7573f431d9ecd0e9dc21f4406f884b92152508fd"
			"clienticon"		"b5de75f7c5f84027200fdafe0483caaeb80f7dbe"
			"clienttga"		"6012ea81d68607ad0dfc5610e61f17101373c1fd"
			"freetodownload"		"1"
			"associations"
			{
			}
			"gameid"		"2131400"
		}
		"extended"
		{
			"gamedir"		""
		}
		"config"
		{
			"installdir"		"VEIN Dedicated Server"
			"launch"
			{
				"0"
				{
					"executable"		"VeinServer.exe"
					"type"		"default"
					"config"
					{
						"oslist"		"windows"
					}
					"description_loc"
					{
						"english"		"VEIN Dedicated Server"
					}
					"description"		"VEIN Dedicated Server"
				}
				"1"
				{
					"executable"		"VeinServer.sh"
					"type"		"default"
					"config"
					{
						"oslist"		"linux"
					}
					"description_loc"
					{
						"english"		"VEIN Dedicated Server"
					}
					"description"		"VEIN Dedicated Server"
				}
			}
			"uselaunchcommandline"		"1"
		}
		"depots"
		{
			"228989"
			{
				"config"
				{
					"oslist"		"windows"
				}
				"depotfromapp"		"228980"
				"sharedinstall"		"1"
			}
			"228990"
			{
				"config"
				{
					"oslist"		"windows"
				}
				"depotfromapp"		"228980"
				"sharedinstall"		"1"
			}
			"2131401"
			{
				"config"
				{
					"oslist"		"windows"
				}
				"manifests"
				{
					"public"
					{
						"gid"		"3422721066391688500"
						"size"		"13373528354"
						"download"		"4719647568"
					}
					"experimental"
					{
						"gid"		"5376672931011513884"
						"size"		"14053570688"
						"download"		"4881399680"
					}
				}
			}
			"2131402"
			{
				"config"
				{
					"oslist"		"linux"
				}
				"manifests"
				{
					"public"
					{
						"gid"		"4027172715479418364"
						"size"		"14134939630"
						"download"		"4869512928"
					}
					"experimental"
					{
						"gid"		"643377871134354986"
						"size"		"14712396815"
						"download"		"4982816608"
					}
				}
			}
			"branches"
			{
				"public"
				{
					"buildid"		"20727232"
					"timeupdated"		"1762674215"
				}
				"experimental"
				{
					"buildid"		"20729593"
					"description"		"Bleeding-edge updates"
					"timeupdated"		"1762704776"
				}
			}
			"privatebranches"		"1"
		}
	}

	:param manifest_content: str, content of the SteamCMD manifest file
	:return: dict, parsed manifest data
	"""
	lines = manifest_content.splitlines()
	stack = []
	current_dict = {}
	current_key = None

	for line in lines:
		line = line.strip()
		if line == '{':
			new_dict = {}
			if current_key is not None:
				current_dict[current_key] = new_dict
			stack.append((current_dict, current_key))
			current_dict = new_dict
			current_key = None
		elif line == '}':
			if stack:
				current_dict, current_key = stack.pop()
		else:
			match = re.match(r'"(.*?)"\s*"(.*?)"', line)
			if match:
				key, value = match.groups()
				current_dict[key] = value
			else:
				match = re.match(r'"(.*?)"', line)
				if match:
					current_key = match.group(1)

	return current_dict



def steamcmd_get_app_details(app_id: str, steamcmd_path: str = None) -> Union[dict, None]:
	"""
	Get detailed information about a Steam app using steamcmd

	Returns a dictionary with:

	- common
		- name
		- type
		- parent
		- ReleaseState
		- oslist
		- osarch
		- osextended
		- icon
		- clienticon
		- clienttga
		- freetodownload
		- associations
		- gameid
	- extended
		- gamedir
	- config
		- installdir
		- launch
		- uselaunchcommandline
	- depots

	:param app_id:
	:param steamcmd_path:
	:return:
	"""
	if steamcmd_path is None:
		# Try to find steamcmd in the common locations
		paths = ("/usr/games/steamcmd", "/usr/local/games/steamcmd", "/opt/steamcmd/steamcmd.sh")
		for path in paths:
			if os.path.exists(path):
				steamcmd_path = path
				break
		else:
			print('steamcmd not found in common locations. Please provide the path to steamcmd.', file=sys.stderr)
			return None

	# Construct the command to get app details
	command = [
		steamcmd_path,
		"+login", "anonymous",
		"+app_info_update", "1",
		"+app_info_print", str(app_id),
		"+quit"
	]

	try:
		# Run the steamcmd command
		result = subprocess.run(command, capture_output=True, text=True, check=True)

		# Output from command should be Steam manifest format, parse it
		dat = steamcmd_parse_manifest(result.stdout)
		if app_id in dat:
			return dat[app_id]
		else:
			print(f"App ID {app_id} not found in steamcmd output.", file=sys.stderr)
			return None

	except subprocess.CalledProcessError as e:
		print(f"Error running steamcmd: {e}")
		return None


def steamcmd_check_app_update(app_manifest: str):
	if not os.path.exists(app_manifest):
		print(f"App manifest file {app_manifest} does not exist.", file=sys.stderr)
		return False

	# App manifest is a local copy of the app JSON data
	with open(app_manifest, 'r') as f:
		details = steamcmd_parse_manifest(f.read())

	if 'AppState' not in details:
		print(f"Invalid app manifest format in {app_manifest}.", file=sys.stderr)
		return False

	# Pull local data about the installed game from its manifest file
	app_id = details['AppState']['appid']
	build_id = details['AppState']['buildid']

	if 'MountedConfig' in details['AppState'] and 'BetaKey' in details['AppState']['MountedConfig']:
		branch = details['AppState']['MountedConfig']['BetaKey']
	else:
		branch = 'public'

	# Pull the latest app details from SteamCMD
	details = steamcmd_get_app_details(app_id)

	# Ensure some basic data integrity
	if 'depots' not in details:
		print(f"No depot information found for app {app_id}.", file=sys.stderr)
		return False

	if 'branches' not in details['depots']:
		print(f"No branch information found for app {app_id}.", file=sys.stderr)
		return False

	if branch not in details['depots']['branches']:
		print(f"Branch {branch} not found for app {app_id}.", file=sys.stderr)
		return False

	# Just check if the build IDs differ
	available_build_id = details['depots']['branches'][branch]['buildid']
	return build_id != available_build_id



class BaseApp:
	"""
	Game application manager
	"""

	def __init__(self):
		self.name = ''
		"""
		:type str:
		Short name for this game
		"""

		self.desc = ''
		"""
		:type str:
		Description / full name of this game
		"""

		self.services = []
		"""
		:type list<str>:
		List of available services (instances) for this game
		"""

		self._svcs = None
		"""
		:type list<BaseService>:
		Cached list of service instances for this game
		"""

		self.configs = {}
		"""
		:type dict<str, BaseConfig>: 
		Dictionary of configuration files for this game
		"""

		self.configured = False

	def load(self):
		"""
		Load the configuration files
		:return:
		"""
		for config in self.configs.values():
			if config.exists():
				config.load()
				self.configured = True

	def save(self):
		"""
		Save the configuration files back to disk
		:return:
		"""
		for config in self.configs.values():
			config.save()

	def get_options(self) -> list:
		"""
		Get a list of available configuration options for this game
		:return:
		"""
		opts = []
		for config in self.configs.values():
			opts.extend(list(config.options.keys()))

		# Sort alphabetically
		opts.sort()

		return opts

	def get_option_value(self, option: str) -> Union[str, int, bool]:
		"""
		Get a configuration option from the game config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_value(option)

		print('Invalid option: %s, not present in game configuration!' % option, file=sys.stderr)
		return ''

	def get_option_default(self, option: str) -> str:
		"""
		Get the default value of a configuration option
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_default(option)

		print('Invalid option: %s, not present in game configuration!' % option, file=sys.stderr)
		return ''

	def get_option_type(self, option: str) -> str:
		"""
		Get the type of a configuration option from the game config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_type(option)

		print('Invalid option: %s, not present in game configuration!' % option, file=sys.stderr)
		return ''

	def get_option_help(self, option: str) -> str:
		"""
		Get the help text of a configuration option from the game config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.options[option][4]

		print('Invalid option: %s, not present in game configuration!' % option, file=sys.stderr)
		return ''

	def option_value_updated(self, option: str, previous_value, new_value):
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""
		pass

	def set_option(self, option: str, value: Union[str, int, bool]):
		"""
		Set a configuration option in the game config
		:param option:
		:param value:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				previous_value = config.get_value(option)
				if previous_value == value:
					# No change
					return

				config.set_value(option, value)
				config.save()

				self.option_value_updated(option, previous_value, value)
				return

		print('Invalid option: %s, not present in game configuration!' % option, file=sys.stderr)

	def get_option_options(self, option: str):
		"""
		Get the list of possible options for a configuration option
		:param options:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_options(option)

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return []

	def prompt_option(self, option: str):
		"""
		Prompt the user to set a configuration option for the game
		:param option:
		:return:
		"""
		val_type = self.get_option_type(option)
		val = self.get_option_value(option)
		help_text = self.get_option_help(option)

		print('')
		if help_text:
			print(help_text)
		if val_type == 'bool':
			default = 'y' if val else 'n'
			val = prompt_yn('%s: ' % option, default)
		else:
			val = prompt_text('%s: ' % option, default=val, prefill=True)

		self.set_option(option, val)

	def get_services(self) -> list:
		"""
		Get a dictionary of available services (instances) for this game

		:return:
		"""
		if self._svcs is None:
			self._svcs = []
			for svc in self.services:
				self._svcs.append(GameService(svc, self))
		return self._svcs

	def is_active(self) -> bool:
		"""
		Check if any service instance is currently running or starting
		:return:
		"""
		for svc in self.get_services():
			if svc.is_running() or svc.is_starting() or svc.is_stopping():
				return True
		return False

	def check_update_available(self) -> bool:
		"""
		Check if there's an update available for this game

		:return:
		"""
		return False

	def update(self) -> bool:
		"""
		Update the game server

		:return:
		"""
		return False

	def send_discord_message(self, message: str):
		"""
		Send a message to the configured Discord webhook

		:param message:
		:return:
		"""
		if not self.get_option_value('Discord Enabled'):
			print('Discord notifications are disabled.')
			return

		if self.get_option_value('Discord Webhook URL') == '':
			print('Discord webhook URL is not set.')
			return

		print('Sending to discord: ' + message)
		req = request.Request(
			self.get_option_value('Discord Webhook URL'),
			headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0'},
			method='POST'
		)
		data = json.dumps({'content': message}).encode('utf-8')
		try:
			with request.urlopen(req, data=data) as resp:
				pass
		except urllib_error.HTTPError as e:
			print('Could not notify Discord: %s' % e)

	def get_save_directory(self) -> Union[str, None]:
		"""
		Get the save directory for this game, or None if not applicable

		:return:
		"""
		return None

	def get_save_files(self) -> Union[list, None]:
		"""
		Get the list of save files/directories for this game, or None if not applicable

		:return:
		"""
		return None

	def backup(self, max_backups: int = 0) -> bool:
		"""
		Perform a backup of the game configuration and save files

		:param max_backups: Maximum number of backups to keep (0 = unlimited)
		:return:
		"""
		self.prepare_backup()
		backup_path = self.complete_backup(max_backups)
		print('Backup saved to %s' % backup_path)
		return True

	def prepare_backup(self) -> str:
		"""
		Prepare a backup directory for this game and return the file path

		:return:
		"""
		here = os.path.dirname(os.path.realpath(__file__))
		temp_store = os.path.join(here, '.save')
		save_source = self.get_save_directory()
		save_files = self.get_save_files()

		# Temporary directories for various file sources
		for d in ['config', 'save']:
			p = os.path.join(temp_store, d)
			if not os.path.exists(p):
				os.makedirs(p)

		# Copy the various configuration files used by the game
		for cfg in self.configs.values():
			src = cfg.path
			if src and os.path.exists(src):
				print('Backing up configuration file: %s' % src)
				dst = os.path.join(temp_store, 'config', os.path.basename(src))
				shutil.copy(src, dst)

		# Include service-specific configuration files too
		for svc in self.get_services():
			p = os.path.join(temp_store, svc.service)
			if not os.path.exists(p):
				os.makedirs(p)
			for cfg in svc.configs.values():
				src = cfg.path
				if src and os.path.exists(src):
					print('Backing up configuration file: %s' % src)
					dst = os.path.join(p, os.path.basename(src))
					shutil.copy(src, dst)

		# Copy save files if specified
		if save_source and save_files:
			for f in save_files:
				src = os.path.join(save_source, f)
				dst = os.path.join(temp_store, 'save', f)
				if os.path.exists(src):
					if os.path.isfile(src):
						print('Backing up save file: %s' % src)
						if not os.path.exists(os.path.dirname(dst)):
							os.makedirs(os.path.dirname(dst))
						shutil.copy(src, dst)
					else:
						print('Backing up save directory: %s' % src)
						if not os.path.exists(dst):
							os.makedirs(dst)
						shutil.copytree(src, dst, dirs_exist_ok=True)
				else:
					print('Save file %s does not exist, skipping...' % src, file=sys.stderr)

		return temp_store

	def complete_backup(self, max_backups: int = 0) -> str:
		"""
		Complete the backup process by creating the final archive and cleaning up temporary files

		:return:
		"""
		here = os.path.dirname(os.path.realpath(__file__))
		target_dir = os.path.join(here, 'backups')
		temp_store = os.path.join(here, '.save')
		base_name = self.name
		# Ensure no weird characters in the name
		replacements = {
			'/': '_',
			'\\': '_',
			':': '',
			'*': '',
			'?': '',
			'"': '',
			"'": '',
			' ': '_'
		}
		for old, new in replacements.items():
			base_name = base_name.replace(old, new)

		if os.geteuid() == 0:
			stat_info = os.stat(here)
			uid = stat_info.st_uid
			gid = stat_info.st_gid
		else:
			uid = None
			gid = None

		# Ensure target directory exists; this will store the finalized backups
		if not os.path.exists(target_dir):
			os.makedirs(target_dir)
			if uid is not None:
				os.chown(target_dir, uid, gid)

		# Create the final archive
		timestamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
		backup_name = '%s-backup-%s.tar.gz' % (base_name, timestamp)
		backup_path = os.path.join(target_dir, backup_name)
		print('Creating backup archive: %s' % backup_path)
		shutil.make_archive(backup_path[:-7], 'gztar', temp_store)

		# Ensure consistent ownership
		if uid is not None:
			os.chown(backup_path, uid, gid)

		# Cleanup
		shutil.rmtree(temp_store)

		# Remove old backups if necessary
		if max_backups > 0:
			backups = []
			for f in os.listdir(target_dir):
				if f.startswith('%s-backup-' % base_name) and f.endswith('.tar.gz'):
					full_path = os.path.join(target_dir, f)
					backups.append((full_path, os.path.getmtime(full_path)))
			backups.sort(key=lambda x: x[1])  # Sort by modification time
			while len(backups) > max_backups:
				old_backup = backups.pop(0)
				os.remove(old_backup[0])
				print('Removed old backup: %s' % old_backup[0])

		return backup_path

	def restore(self, path: str) -> bool:
		"""
		Restore a backup from the given filename

		:param path:
		:return:
		"""
		temp_store = self.prepare_restore(path)
		if temp_store is False:
			return False
		self.complete_restore()
		return True

	def prepare_restore(self, filename) -> Union[str, bool]:
		"""
		Prepare to restore a backup by extracting it to a temporary location

		:param filename:
		:return:
		"""
		if not os.path.exists(filename):
			print('Backup file %s does not exist, cannot continue!' % filename, file=sys.stderr)
			return False

		if self.is_active():
			print('Game server is currently running, please stop it before restoring a backup!', file=sys.stderr)
			return False

		here = os.path.dirname(os.path.realpath(__file__))
		temp_store = os.path.join(here, '.restore')
		os.makedirs(temp_store, exist_ok=True)
		save_dest = self.get_save_directory()

		if os.geteuid() == 0:
			stat_info = os.stat(here)
			uid = stat_info.st_uid
			gid = stat_info.st_gid
		else:
			uid = None
			gid = None

		# Extract the archive to the temporary location
		print('Extracting backup archive: %s' % filename)
		shutil.unpack_archive(filename, temp_store)

		# Copy the various configuration files used by the game
		for cfg in self.configs.values():
			dst = cfg.path
			if dst:
				src = os.path.join(temp_store, 'config', os.path.basename(dst))
				if os.path.exists(src):
					print('Restoring configuration file: %s' % dst)
					shutil.copy(src, dst)
					if uid is not None:
						os.chown(dst, uid, gid)

		# Include service-specific configuration files too
		for svc in self.get_services():
			p = os.path.join(temp_store, svc.service)
			if os.path.exists(p):
				for cfg in svc.configs.values():
					dst = cfg.path
					if dst:
						src = os.path.join(p, os.path.basename(dst))
						if os.path.exists(src):
							print('Restoring configuration file: %s' % dst)
							shutil.copy(src, dst)
							if uid is not None:
								os.chown(dst, uid, gid)

		# If the save destination is specified, perform those files/directories too.
		if save_dest:
			save_src = os.path.join(temp_store, 'save')
			if os.path.exists(save_src):
				for item in os.listdir(save_src):
					src = os.path.join(save_src, item)
					dst = os.path.join(save_dest, item)
					print('Restoring save file: %s' % dst)
					if os.path.isfile(src):
						shutil.copy(src, dst)
					else:
						shutil.copytree(src, dst, dirs_exist_ok=True)
					if uid is not None:
						if os.path.isfile(dst):
							os.chown(dst, uid, gid)
						else:
							for root, dirs, files in os.walk(dst):
								for momo in dirs:
									os.chown(os.path.join(root, momo), uid, gid)
								for momo in files:
									os.chown(os.path.join(root, momo), uid, gid)

		return temp_store

	def complete_restore(self):
		"""
		Complete the restore process by cleaning up temporary files

		:return:
		"""
		here = os.path.dirname(os.path.realpath(__file__))
		temp_store = os.path.join(here, '.restore')

		# Cleanup
		shutil.rmtree(temp_store)

class SteamApp(BaseApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()
		self.steam_id = ''

	def check_update_available(self) -> bool:
		"""
		Check if a SteamCMD update is available for this game

		:return:
		"""
		here = os.path.dirname(os.path.realpath(__file__))
		return steamcmd_check_app_update(os.path.join(here, 'AppFiles', 'steamapps', 'appmanifest_%s.acf' % self.steam_id))

	def update(self):
		"""
		Update the game server via SteamCMD

		:return:
		"""
		# Stop any running services before updating
		services = []
		for service in self.get_services():
			if service.is_running() or service.is_starting():
				print('Stopping service %s for update...' % service.service)
				services.append(service.service)
				subprocess.Popen(['systemctl', 'stop', service.service])

		if len(services) > 0:
			# Wait for all services to stop, may take 5 minutes if players are online.
			print('Waiting up to 5 minutes for all services to stop...')
			counter = 0
			while counter < 30:
				all_stopped = True
				counter += 1
				for service in self.get_services():
					if service.is_running() or service.is_starting() or service.is_stopping():
						all_stopped = False
						break
				if all_stopped:
					break
				time.sleep(10)
		else:
			print('No running services found, proceeding with update...')

		here = os.path.dirname(os.path.realpath(__file__))
		cmd = [
			'/usr/games/steamcmd',
			'+force_install_dir',
			os.path.join(here, 'AppFiles'),
			'+login',
			'anonymous',
			'+app_update',
			self.steam_id,
			'validate',
			'+quit'
		]

		if os.geteuid() == 0:
			stat_info = os.stat(here)
			uid = stat_info.st_uid
			cmd = [
				'sudo',
				'-u',
				'#%s' % uid
			] + cmd

		res = subprocess.run(cmd)

		if len(services) > 0:
			print('Update completed, restarting previously running services...')
			for service in services:
				subprocess.Popen(['systemctl', 'start', service])
				time.sleep(10)

		return res.returncode == 0


class BaseService:
	"""
	Service definition and handler
	"""
	def __init__(self, service: str, game: BaseApp):
		"""
		Initialize and load the service definition
		:param file:
		"""
		self.service = service
		self.game = game
		self.configured = False
		self.configs = {}

	def load(self):
		"""
		Load the configuration files
		:return:
		"""
		for config in self.configs.values():
			if config.exists():
				config.load()
				self.configured = True

	def get_options(self) -> list:
		"""
		Get a list of available configuration options for this service
		:return:
		"""
		opts = []
		for config in self.configs.values():
			opts.extend(list(config.options.keys()))

		# Sort alphabetically
		opts.sort()

		return opts

	def get_option_value(self, option: str) -> Union[str, int, bool]:
		"""
		Get a configuration option from the service config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_value(option)

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return ''

	def get_option_default(self, option: str) -> str:
		"""
		Get the default value of a configuration option
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_default(option)

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return ''

	def get_option_type(self, option: str) -> str:
		"""
		Get the type of a configuration option from the service config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_type(option)

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return ''

	def get_option_help(self, option: str) -> str:
		"""
		Get the help text of a configuration option from the service config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.options[option][4]

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return ''

	def option_value_updated(self, option: str, previous_value, new_value):
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""
		pass

	def set_option(self, option: str, value: Union[str, int, bool]):
		"""
		Set a configuration option in the service config
		:param option:
		:param value:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				previous_value = config.get_value(option)
				if previous_value == value:
					# No change
					return

				config.set_value(option, value)
				config.save()

				self.option_value_updated(option, previous_value, value)
				return

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)

	def option_has_value(self, option: str) -> bool:
		"""
		Check if a configuration option has a value set in the service config
		:param option:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.has_value(option)

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return False

	def get_option_options(self, option: str):
		"""
		Get the list of possible options for a configuration option
		:param options:
		:return:
		"""
		for config in self.configs.values():
			if option in config.options:
				return config.get_options(option)

		print('Invalid option: %s, not present in service configuration!' % option, file=sys.stderr)
		return []

	def option_ensure_set(self, option: str):
		"""
		Ensure that a configuration option has a value set, using the default if not
		:param option:
		:return:
		"""
		if not self.option_has_value(option):
			default = self.get_option_default(option)
			self.set_option(option, default)

	def get_name(self) -> str:
		"""
		Get the display name of this service
		:return:
		"""
		return self.service

	def get_port(self) -> Union[int, None]:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		return None

	def prompt_option(self, option: str):
		"""
		Prompt the user to set a configuration option for the service
		:param option:
		:return:
		"""
		val_type = self.get_option_type(option)
		val = self.get_option_value(option)
		help_text = self.get_option_help(option)

		print('')
		if help_text:
			print(help_text)
		if val_type == 'bool':
			default = 'y' if val else 'n'
			val = prompt_yn('%s: ' % option, default)
		else:
			val = prompt_text('%s: ' % option, default=val, prefill=True)

		self.set_option(option, val)

	def get_player_max(self) -> Union[int, None]:
		"""
		Get the maximum player count on the server, or None if the API is unavailable
		:return:
		"""
		pass

	def get_player_count(self) -> Union[int, None]:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		pass

	def get_pid(self) -> int:
		"""
		Get the PID of the running service, or 0 if not running
		:return:
		"""
		pid = subprocess.run([
			'systemctl', 'show', '-p', 'MainPID', self.service
		], stdout=subprocess.PIPE).stdout.decode().strip()[8:]

		return int(pid)

	def get_process_status(self) -> int:
		return int(subprocess.run([
			'systemctl', 'show', '-p', 'ExecMainStatus', self.service
		], stdout=subprocess.PIPE).stdout.decode().strip()[15:])

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""
		pass

	def get_memory_usage(self) -> str:
		"""
		Get the formatted memory usage of the service, or N/A if not running
		:return:
		"""

		pid = self.get_game_pid()

		if pid == 0 or pid is None:
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

		if pid == 0 or pid is None:
			return 'N/A'

		cpu = subprocess.run([
			'ps', 'h', '-p', str(pid), '-o', '%cpu'
		], stdout=subprocess.PIPE).stdout.decode().strip()

		if cpu.replace('.', '', 1).isdigit():
			return '%.0f%%' % float(cpu)
		else:
			return 'N/A'

	def get_exec_start_status(self) -> Union[dict, None]:
		"""
		Get the ExecStart status of the service
		This includes:

		* path - string: Path of the ExecStartPre command
		* arguments - string: Arguments passed to the ExecStartPre command
		* start_time - datetime: Time the ExecStartPre command started
		* stop_time - datetime: Time the ExecStartPre command stopped
		* pid - int: PID of the ExecStartPre command
		* code - string: Exit code of the ExecStartPre command
		* status - int: Exit status of the ExecStartPre command
		* runtime - int: Runtime of the ExecStartPre command in seconds

		:return:
		"""
		return self._get_exec_status('ExecStart')

	def get_exec_start_pre_status(self) -> Union[dict, None]:
		"""
		Get the ExecStart status of the service
		This includes:

		* path - string: Path of the ExecStartPre command
		* arguments - string: Arguments passed to the ExecStartPre command
		* start_time - datetime: Time the ExecStartPre command started
		* stop_time - datetime: Time the ExecStartPre command stopped
		* pid - int: PID of the ExecStartPre command
		* code - string: Exit code of the ExecStartPre command
		* status - int: Exit status of the ExecStartPre command
		* runtime - int: Runtime of the ExecStartPre command in seconds

		:return:
		"""
		return self._get_exec_status('ExecStartPre')


	def _get_exec_status(self, lookup: str) -> Union[dict, None]:
		"""
		Get the ExecStartPre status of the service
		This includes:

		* path - string: Path of the ExecStartPre command
		* arguments - string: Arguments passed to the ExecStartPre command
		* start_time - datetime: Time the ExecStartPre command started
		* stop_time - datetime: Time the ExecStartPre command stopped
		* pid - int: PID of the ExecStartPre command
		* code - string: Exit code of the ExecStartPre command
		* status - int: Exit status of the ExecStartPre command
		* runtime - int: Runtime of the ExecStartPre command in seconds

		:return:
		"""

		output = subprocess.run([
			'systemctl', 'show', '-p', lookup, self.service
		], stdout=subprocess.PIPE).stdout.decode().strip()[len(lookup)+1:]
		if output == '':
			return None

		output = output[1:-1]  # Remove surrounding {}
		parts = output.split(' ; ')
		result = {}
		for part in parts:
			if '=' not in part:
				continue
			key, val = part.split('=', 1)
			key = key.strip()
			val = val.strip()
			if key == 'path':
				result['path'] = val
			elif key == 'argv[]':
				result['arguments'] = val
			elif key == 'start_time':
				val = val[1:-1]  # Remove surrounding []
				if val == 'n/a':
					result['start_time'] = None
				else:
					result['start_time'] = datetime.datetime.strptime(val, '%a %Y-%m-%d %H:%M:%S %Z')
			elif key == 'stop_time':
				val = val[1:-1]
				if val == 'n/a':
					result['stop_time'] = None
				else:
					result['stop_time'] = datetime.datetime.strptime(val, '%a %Y-%m-%d %H:%M:%S %Z')
			elif key == 'pid':
				result['pid'] = int(val)
			elif key == 'code':
				if val == '(null)':
					result['code'] = None
				else:
					result['code'] = val
			elif key == 'status':
				if '/' in val:
					result['status'] = int(val.split('/')[0])
				else:
					result['status'] = int(val)

		if result['start_time'] and result['stop_time']:
			delta = result['stop_time'] - result['start_time']
			result['runtime'] = int(delta.total_seconds())
		else:
			result['runtime'] = 0

		return result

	def _is_enabled(self) -> str:
		"""
		Get the output of systemctl is-enabled for this service

		* enabled - Service is enabled
		* disabled - Service is disabled
		* static - Service is static and cannot be enabled/disabled
		* masked - Service is masked

		:return:
		"""
		return subprocess.run(
			['systemctl', 'is-enabled', self.service],
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
			check=False
		).stdout.decode().strip()

	def _is_active(self) -> str:
		"""
		Returns a string based on the status of the service:

		* active - Running
		* reloading - Running but reloading configuration
		* inactive - Stopped
		* failed - Failed to start
		* activating - Starting
		* deactivating - Stopping

		:return:
		"""
		return subprocess.run(
			['systemctl', 'is-active', self.service],
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
			check=False
		).stdout.decode().strip()

	def is_enabled(self) -> bool:
		"""
		Check if this service is enabled in systemd
		:return:
		"""
		return self._is_enabled() == 'enabled'

	def is_running(self) -> bool:
		"""
		Check if this service is currently running
		:return:
		"""
		return self._is_active() == 'active'

	def is_starting(self) -> bool:
		"""
		Check if this service is currently starting
		:return:
		"""
		return self._is_active() == 'activating'

	def is_stopping(self) -> bool:
		"""
		Check if this service is currently stopping
		:return:
		"""
		return self._is_active() == 'deactivating'

	def is_api_enabled(self) -> bool:
		"""
		Check if an API is available for this service
		:return:
		"""
		return False

	def enable(self):
		"""
		Enable this service in systemd
		:return:
		"""
		if os.geteuid() != 0:
			print('ERROR - Unable to enable game service unless run with sudo', file=sys.stderr)
			return
		subprocess.run(['systemctl', 'enable', self.service])

	def disable(self):
		"""
		Disable this service in systemd
		:return:
		"""
		if os.geteuid() != 0:
			print('ERROR - Unable to disable game service unless run with sudo', file=sys.stderr)
			return
		subprocess.run(['systemctl', 'disable', self.service])

	def print_logs(self, lines: int = 20):
		"""
		Print the latest logs from this service
		:param lines:
		:return:
		"""
		subprocess.run(['journalctl', '-u', self.service, '-n', str(lines), '--no-pager'])

	def get_logs(self, lines: int = 20) -> str:
		"""
		Get the latest logs from this service
		:param lines:
		:return:
		"""
		return subprocess.run(
			['journalctl', '-u', self.service, '-n', str(lines), '--no-pager'],
			stdout=subprocess.PIPE
		).stdout.decode()

	def send_message(self, message: str):
		"""
		Send a message to all players via the game API
		:param message:
		:return:
		"""
		pass

	def save_world(self):
		"""
		Force a world save via the game API
		:return:
		"""
		pass

	def start(self):
		"""
		Start this service in systemd
		:return:
		"""
		if self.is_running():
			print('Game is currently running!', file=sys.stderr)
			return

		if self.is_starting():
			print('Game is currently starting!', file=sys.stderr)
			return

		if os.geteuid() != 0:
			print('ERROR - Unable to stop game service unless run with sudo', file=sys.stderr)

		try:
			print('Starting game via systemd, please wait a minute...')
			start_timer = time.time()
			subprocess.Popen(['systemctl', 'start', self.service])
			time.sleep(10)

			ready = False
			counter = 0
			print('loading...')
			while counter < 240:
				counter += 1
				pid = self.get_pid()
				exec_status = self.get_process_status()

				if exec_status != 0:
					self.print_logs()
					print('Game failed to start, ExecMainStatus: %s' % str(exec_status), file=sys.stderr)
					return

				if pid == 0:
					self.print_logs()
					print('Game failed to start, no PID found.', file=sys.stderr)
					return

				memory = self.get_memory_usage()
				cpu = self.get_cpu_usage()
				seconds_elapsed = round(time.time() - start_timer)
				since_minutes = str(seconds_elapsed // 60)
				since_seconds = seconds_elapsed % 60
				if since_seconds < 10:
					since_seconds = '0' + str(since_seconds)
				else:
					since_seconds = str(since_seconds)

				if self.is_api_enabled():
					players = self.get_player_count()
					if players is not None:
						ready = True
						api_status = 'CONNECTED'
					else:
						api_status = 'waiting'
				else:
					api_status = 'not enabled'
					# API is not enabled so just assume ready after some time
					if seconds_elapsed >= 60:
						ready = True

				print(
					'\033[1A\033[K Time: %s, PID: %s, CPU: %s, Memory: %s, API: %s' % (
						since_minutes + ':' + since_seconds,
						str(pid),
						cpu,
						memory,
						api_status
					)
				)

				if ready:
					print('Game has started successfully!')
					time.sleep(5)
					break
				time.sleep(1)
		except KeyboardInterrupt:
			print('Cancelled startup wait check, (game is probably still started)')

	def pre_stop(self) -> bool:
		"""
		Perform operations necessary for safely stopping a server

		Called automatically via systemd
		:return:
		"""
		# Send a message to Discord that the instance is stopping
		msg = self.game.get_option_value('Instance Stopping (Discord)')
		if msg != '':
			if '{instance}' in msg:
				msg = msg.replace('{instance}', self.get_name())
			self.game.send_discord_message(msg)

		# Send message to players in-game that the server is shutting down,
		# (only if the API is available)
		if self.is_api_enabled():
			timers = (
				(self.game.get_option_value('Shutdown Warning 5 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 4 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 3 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 2 Minutes'), 60),
				(self.game.get_option_value('Shutdown Warning 1 Minute'), 30),
				(self.game.get_option_value('Shutdown Warning 30 Seconds'), 30),
				(self.game.get_option_value('Shutdown Warning NOW'), 0),
			)
			for timer in timers:
				players = self.get_player_count()
				if players is not None and players > 0:
					print('Players are online, sending warning message: %s' % timer[0])
					self.send_message(timer[0])
					if timer[1]:
						time.sleep(timer[1])
				else:
					break

		# Force a world save before stopping, if the API is available
		if self.is_api_enabled():
			print('Forcing server save')
			self.save_world()
			time.sleep(5)

		return True

	def post_start(self) -> bool:
		"""
		Perform the necessary operations for after a game has started
		:return:
		"""
		if self.is_api_enabled():
			counter = 0
			print('Waiting for API to become available...', file=sys.stderr)
			time.sleep(15)
			while counter < 24:
				players = self.get_player_count()
				if players is not None:
					msg = self.game.get_option_value('Instance Started (Discord)')
					if msg != '':
						if '{instance}' in msg:
							msg = msg.replace('{instance}', self.get_name())
						self.game.send_discord_message(msg)
					return True
				else:
					print('API not available yet', file=sys.stderr)

				# Is the game PID still available?
				if self.get_pid() == 0:
					print('Game process has exited unexpectedly!', file=sys.stderr)
					return False

				if self.get_game_pid() == 0:
					print('Game server process has exited unexpectedly!', file=sys.stderr)
					return False

				time.sleep(10)
				counter += 1

			print('API did not reply within the allowed time!', file=sys.stderr)
			return False
		else:
			# API not available, so nothing to check.
			return True

	def stop(self):
		"""
		Stop this service in systemd
		:return:
		"""
		if os.geteuid() != 0:
			print('ERROR - Unable to stop game service unless run with sudo', file=sys.stderr)
			return

		print('Stopping server, please wait...')
		subprocess.Popen(['systemctl', 'stop', self.service])
		time.sleep(10)

	def restart(self):
		"""
		Restart this service in systemd
		:return:
		"""
		if not self.is_running():
			print('%s is not currently running!' % self.service, file=sys.stderr)
			return

		self.stop()
		self.start()


class BaseConfig:
	def __init__(self, group_name: str, *args, **kwargs):
		self.options = {}
		"""
		:type dict<str, tuple<str, str, str, str, str>>
		Primary dictionary of all options on this config
		
		* Item 0: Section
		* Item 1: Key
		* Item 2: Default Value
		* Item 3: Type (str, int, bool)
		* Item 4: Help Text
		"""

		self._keys = {}
		"""
		:type dict<str, str>
		Map of lowercase option keys to name for quick lookup
		"""

		# Load the configuration definitions from configs.yaml
		here = os.path.dirname(os.path.realpath(__file__))

		if os.path.exists(os.path.join(here, 'configs.yaml')):
			with open(os.path.join(here, 'configs.yaml'), 'r') as cfgfile:
				cfgdata = yaml.safe_load(cfgfile)
				for cfgname, cfgoptions in cfgdata.items():
					if cfgname == group_name:
						for option in cfgoptions:
							self.add_option(
								option.get('name'),
								option.get('section'),
								option.get('key'),
								option.get('default', None),
								option.get('type', 'str'),
								option.get('help', ''),
								option.get('options', None)
							)

	def add_option(self, name, section, key, default='', val_type='str', help_text='', options=None):
		"""
		Add a configuration option to the available list

		:param name:
		:param section:
		:param key:
		:param default:
		:param val_type:
		:param help_text:
		:return:
		"""

		# Ensure boolean defaults are stored as strings
		# They get re-converted back to bools on retrieval
		if val_type == 'bool':
			if default is True:
				default = 'True'
			elif default is False:
				default = 'False'
			elif default is None:
				# No default specified, default to False
				default = 'False'

		if default is None:
			default = ''

		self.options[name] = (section, key, default, val_type, help_text, options)
		# Primary dictionary of all options on this config

		self._keys[key.lower()] = name
		# Map of lowercase option names to sections for quick lookup

	@classmethod
	def convert_to_system_type(cls, value: str, val_type: str) -> Union[str, int, bool]:
		"""
		Convert a string value to the appropriate system type
		:param value:
		:param val_type:
		:return:
		"""
		# Auto convert
		if value == '':
			return ''
		elif val_type == 'int':
			return int(value)
		elif val_type == 'bool':
			return value.lower() in ('1', 'true', 'yes', 'on')
		else:
			return value

	@classmethod
	def convert_from_system_type(cls, value: Union[str, int, bool, list, float], val_type: str) -> Union[str, list]:
		"""
		Convert a system type value to a string for storage
		:param value:
		:param val_type:
		:return:
		"""
		if val_type == 'bool':
			if value == '':
				# Allow empty values to defer to default
				return ''
			elif value is True or (str(value).lower() in ('1', 'true', 'yes', 'on')):
				return 'True'
			else:
				return 'False'
		elif val_type == 'list':
			if isinstance(value, list):
				return value
			else:
				# Assume comma-separated string
				return [item.strip() for item in str(value).split(',')]
		elif val_type == 'float':
			# Unreal likes floats to be stored with 6 decimal places
			return f'{float(value):.6f}'
		else:
			return str(value)

	def get_value(self, name: str) -> Union[str, int, bool]:
		"""
		Get a configuration option from the config

		:param name: Name of the option
		:return:
		"""
		pass

	def set_value(self, name: str, value: Union[str, int, bool]):
		"""
		Set a configuration option in the config

		:param name: Name of the option
		:param value: Value to save
		:return:
		"""
		pass

	def has_value(self, name: str) -> bool:
		"""
		Check if a configuration option has been set

		:param name: Name of the option
		:return:
		"""
		pass

	def get_default(self, name: str) -> Union[str, int, bool]:
		"""
		Get the default value of a configuration option
		:param name:
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not available in configuration!' % (name, ), file=sys.stderr)
			return ''

		default = self.options[name][2]
		val_type = self.options[name][3]

		return BaseConfig.convert_to_system_type(default, val_type)

	def get_type(self, name: str) -> str:
		"""
		Get the type of a configuration option from the config

		:param name:
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not available in configuration!' % (name, ), file=sys.stderr)
			return ''

		return self.options[name][3]

	def get_help(self, name: str) -> str:
		"""
		Get the help text of a configuration option from the config

		:param name:
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not available in configuration!' % (name, ), file=sys.stderr)
			return ''

		return self.options[name][4]

	def get_options(self, name: str):
		"""
		Get the list of valid options for a configuration option from the config

		:param name:
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not available in configuration!' % (name, ), file=sys.stderr)
			return None

		return self.options[name][5]

	def exists(self) -> bool:
		"""
		Check if the config file exists on disk
		:return:
		"""
		pass

	def load(self, *args, **kwargs):
		"""
		Load the configuration file from disk
		:return:
		"""
		pass

	def save(self, *args, **kwargs):
		"""
		Save the configuration file back to disk
		:return:
		"""
		pass


class CLIConfig(BaseConfig):
	def __init__(self, group_name: str, path: str = None):
		super().__init__(group_name)

		self.values = {}
		"""
		:type dict<str, str>
		Dictionary of current values for options set in the CLI
		"""

		self.path = path
		"""
		:type str:
		Optional path to file that contains the CLI arguments and executable.
		"""

		self.format = None
		"""
		:type str:
		Optional format of the line in the file that contains the arguments.
		If set will be used to automatically extract and parse the command flags.
		
		Use [OPTIONS] to denote where options should be injected.
		"""

		self.flag_sep = '='
		"""
		:type str:
		Some applications expect flag key/values to be separated by a space or by an '=' character.
		If set, this will be used when saving the configuration back to file.
		"""

	def get_value(self, name: str) -> Union[str, int, bool]:
		"""
		Get a configuration option from the config

		:param name: Name of the option
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not available in configuration!' % (name, ), file=sys.stderr)
			return ''

		default = self.options[name][2]
		if default is None:
			default = ''
		val_type = self.options[name][3]
		val = self.values.get(name, default)

		if val_type == 'bool':
			# CLI arguments treat booleans differently; they are true if they are present in general.
			return val == '' or val.lower() == 'true'
		else:
			return BaseConfig.convert_to_system_type(val, val_type)

	def set_value(self, name: str, value: Union[str, int, bool]):
		"""
		Set a configuration option in the config

		:param name: Name of the option
		:param value: Value to save
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not available in configuration!' % (name, ), file=sys.stderr)
			return

		val_type = self.options[name][3]
		str_value = BaseConfig.convert_from_system_type(value, val_type)
		self.values[name] = str_value

	def has_value(self, name: str) -> bool:
		"""
		Check if a configuration option has been set

		:param name: Name of the option
		:return:
		"""
		if name not in self.options:
			return False

		return name in self.values and self.values[name] != ''

	def exists(self) -> bool:
		"""
		Check if the config file exists on disk
		:return:
		"""
		return self.path is not None and os.path.exists(self.path)

	def load(self, arguments: str = ''):
		"""
		Load the configuration file from disk
		:return:
		"""
		if self.path is not None and os.path.exists(self.path) and self.format is not None:
			# Load the file and extract the arguments line
			if '[OPTIONS]' in self.format:
				match = self.format[:self.format.index('[OPTIONS]')].strip()
			else:
				match = self.format.strip()

			with open(self.path, 'r') as f:
				for line in f:
					line = line.strip()
					if line.startswith(match):
						# Extract the arguments
						arguments = line[len(match):].strip()
						break

		# Use a tokenizer to parse options and flags
		buffer = ''
		args = []
		quote = None
		# Add a space at the end to flush the last param
		arguments += ' '
		for c in arguments:
			if quote is None and c in ['"', "'"]:
				quote = c
				continue
			if quote is not None and c == quote:
				quote = None
				continue

			if quote is not None:
				# Quoted strings always just get appended to the buffer
				buffer += c
				continue

			if c in [' ', '?', '-']:
				# These denote separators
				# Flush the buffer first
				if buffer.strip() != '':
					args.append(buffer.strip())
				buffer = c
			else:
				# Normal character, just append to buffer
				buffer += c

		options_done = False
		values = []
		# Split args into options and flags as they behave differently.
		for arg in args:
			if not options_done:
				if arg.startswith('-'):
					# Flags start here
					options_done = True

				else:
					# Option
					if arg.startswith('?'):
						arg = arg[1:]
					if '=' in arg:
						opt_key, opt_val = arg.split('=', 1)
						values.append([opt_key, opt_val, 'option'])
					else:
						values.append([arg, '', 'option'])
					continue

			# Flag
			if arg.startswith('-'):
				arg = arg[1:]
				if '=' in arg:
					opt_key, opt_val = arg.split('=', 1)
					values.append([opt_key, opt_val, 'flag'])
				else:
					values.append([arg, '', 'flag'])
			else:
				# Continuation of a previous argument probably.
				idx = len(values) - 1
				if idx >= 0:
					if values[idx][1] == '':
						values[idx][1] = arg
					elif isinstance(values[idx][1], list):
						values[idx][1].append(arg)
					else:
						values[idx][1] = [values[idx][1], arg]

		# Build a simple list of known options by their key
		opts = {}
		for o in self.options:
			opts[self.options[o][1]] = o

		# Compare against known options and set values
		for val in values:
			opt_key, opt_val, opt_group = val
			option = None
			if opt_key in opts:
				option = opts[opt_key]
			elif isinstance(opt_val, list):
				# Some values can be complicated, ie: with Valheim "modifier portals casual"
				# This may be mapped to "modifier portals" with the value of "casual"
				check = opt_key
				i = 0
				while i < len(opt_val):
					val = opt_val[i]
					i += 1
					check += ' ' + val
					if check in opts:
						option = opts[check]
						opt_val = opt_val[i:]
						if len(opt_val) == 1:
							opt_val = opt_val[0]
						elif len(opt_val) == 0:
							opt_val = ''
						break
			elif opt_val != '':
				# Check for single-value extensions
				if (opt_key + ' ' + opt_val) in opts:
					option = opts[opt_key + ' ' + opt_val]
					opt_val = ''

			if option is None:
				print('Could not find option for key: %s' % (opt_key, ), file=sys.stderr)
				continue

			self.values[option] = opt_val

	def save(self):
		if self.path is not None and os.path.exists(self.path) and self.format is not None:
			# Load the file and extract the arguments line
			if '[OPTIONS]' in self.format:
				match = self.format[:self.format.index('[OPTIONS]')].strip()
			else:
				match = self.format.strip()

			new_cmd = str(self)
			if new_cmd.startswith('?'):
				if '?' in match:
					# Run them together
					new_cmd = match + new_cmd
				else:
					# Remove leading '?' if the match includes it
					new_cmd = match + new_cmd[1:]
			else:
				new_cmd = match + ' ' + new_cmd
			new_contents = []
			with open(self.path, 'r') as f:
				for line in f:
					line = line.strip()
					if line.startswith(match):
						# Replace this line with the new rendered options
						line = new_cmd
					new_contents.append(line)

			with open(self.path, 'w') as f:
				f.write('\n'.join(new_contents) + '\n')

	def __str__(self) -> str:
		opts = []
		flags = []

		for name in self.options.keys():
			if name not in self.values:
				# Skip any options not set
				continue

			section = self.options[name][0]
			key = self.options[name][1]
			val_type = self.options[name][3]
			raw_val = self.values[name]

			if val_type == 'bool':
				if raw_val.lower() in ('true', '1', 'yes', ''):
					if section == 'flag':
						flags.append('-%s' % key)
					else:
						opts.append('%s=True' % key)
			else:
				if '"' in raw_val:
					raw_val = "'%s'" % raw_val
				elif "'" in raw_val or ' ' in raw_val or '?' in raw_val or '=' in raw_val or '-' in raw_val:
					raw_val = '"%s"' % raw_val

				if raw_val != '':
					# Only append keys that have values.
					if section == 'flag':
						flags.append('-%s%s%s' % (key, self.flag_sep, raw_val))
					else:
						opts.append('%s=%s' % (key, raw_val))

		ret = []
		if len(opts) > 0:
			ret.append('?' + '?'.join(opts))
		if len(flags) > 0:
			ret.append(' '.join(flags))
		return ' '.join(ret)


class INIConfig(BaseConfig):
	def __init__(self, group_name: str, path: str):
		super().__init__(group_name)
		self.path = path
		self.parser = configparser.ConfigParser()

	def get_value(self, name: str) -> Union[str, int, bool]:
		"""
		Get a configuration option from the config

		:param name: Name of the option
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not present in %s configuration!' % (name, os.path.basename(self.path)), file=sys.stderr)
			return ''

		section = self.options[name][0]
		key = self.options[name][1]
		default = self.options[name][2]
		val_type = self.options[name][3]
		if section not in self.parser:
			val = default
		else:
			val = self.parser[section].get(key, default)
		return BaseConfig.convert_to_system_type(val, val_type)

	def set_value(self, name: str, value: Union[str, int, bool]):
		"""
		Set a configuration option in the config

		:param name: Name of the option
		:param value: Value to save
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not present in %s configuration!' % (name, os.path.basename(self.path)), file=sys.stderr)
			return

		section = self.options[name][0]
		key = self.options[name][1]
		val_type = self.options[name][3]
		str_value = BaseConfig.convert_from_system_type(value, val_type)

		# Escape '%' characters that may be present
		str_value = str_value.replace('%', '%%')

		if section not in self.parser:
			self.parser[section] = {}
		self.parser[section][key] = str_value

	def has_value(self, name: str) -> bool:
		"""
		Check if a configuration option has been set

		:param name: Name of the option
		:return:
		"""
		if name not in self.options:
			return False

		section = self.options[name][0]
		key = self.options[name][1]
		if section not in self.parser:
			return False
		else:
			return self.parser[section].get(key, '') != ''

	def exists(self) -> bool:
		"""
		Check if the config file exists on disk
		:return:
		"""
		return os.path.exists(self.path)

	def load(self):
		"""
		Load the configuration file from disk
		:return:
		"""
		if os.path.exists(self.path):
			self.parser.read(self.path)

	def save(self):
		"""
		Save the configuration file back to disk
		:return:
		"""
		with open(self.path, 'w') as cfgfile:
			self.parser.write(cfgfile)

		# Change ownership to game user if running as root
		if os.geteuid() == 0:
			# Determine game user based on parent directories
			check_path = os.path.dirname(self.path)
			while check_path != '/' and check_path != '':
				if os.path.exists(check_path):
					stat_info = os.stat(check_path)
					uid = stat_info.st_uid
					gid = stat_info.st_gid
					os.chown(self.path, uid, gid)
					break
				check_path = os.path.dirname(check_path)


class RCONService(BaseService):
	def _api_cmd(self, cmd) -> Union[None,str]:
		"""
		Execute a raw command with RCON and return the result

		:param cmd:
		:return: None if RCON not available, or the result of the command
		"""
		if not (self.is_running() or self.is_starting() or self.is_stopping()):
			# If service is not running, don't even try to connect.
			return None

		if not self.is_api_enabled():
			# RCON is not available due to settings
			return None

		# Safety checks to ensure we have the necessary info, (regardless of is_api_enabled)
		port = self.get_api_port()
		if port is None:
			print("RCON port is not set!  Please populate get_api_port definition.", file=sys.stderr)
			return None

		password = self.get_api_password()
		if password is None:
			print("RCON password is not set!  Please populate get_api_password definition.", file=sys.stderr)
			return None

		try:
			with Client('127.0.0.1', port, passwd=password, timeout=2) as client:
				return client.run(cmd).strip()
		except Exception as e:
			print(str(e), file=sys.stderr)
			return None

	def is_api_enabled(self) -> bool:
		"""
		Check if RCON is enabled for this service
		:return:
		"""
		pass

	def get_api_port(self) -> int:
		"""
		Get the RCON port from the service configuration
		:return:
		"""
		pass

	def get_api_password(self) -> str:
		"""
		Get the RCON password from the service configuration
		:return:
		"""
		pass


class UnrealConfig(BaseConfig):
	def __init__(self, group_name: str, path: str):
		super().__init__(group_name)
		self.path = path
		self._data = []
		self._values = {}
		self._use_array_operators = False
		self._is_changed = False

	def get_value(self, name: str) -> Union[str, int, bool, list]:
		"""
		Get a configuration option from the config

		:param name: Name of the option
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not present in %s configuration!' % (name, os.path.basename(self.path)), file=sys.stderr)
			return ''

		section = self.options[name][0]
		key = self.options[name][1]
		default = self.options[name][2]
		val_type = self.options[name][3]
		if section not in self._values:
			val = default
		else:
			if '/' in key:
				# Struct key
				parts = key.split('/')
				current = self._values[section]
				for part in parts:
					if part in current:
						current = current[part]
					else:
						current = default
						break
				val = current
			elif key not in self._values[section]:
				val = default
			else:
				val = self._values[section][key]

		return BaseConfig.convert_to_system_type(val, val_type)

	def _find_or_create_value(self, section: list, key: str, str_value: Union[str, list]) -> list:
		"""
		Find or create a keyvalue in a given section
		and return the full section data.

		:param section:
		:param key:
		:param str_value:
		:return:
		"""
		found = False
		new_data = []
		for item in section:
			if item['type'] == 'keyvalue' and item['key'] == key:
				if found:
					# This key has already been handled, so skip any more of them.
					continue
				if isinstance(str_value, list):
					# Multiple values, need to handle duplicates
					c = 0
					for val in str_value:
						if c > 0 and self._use_array_operators:
							new_data.append({'type': 'keyvalue', 'key': key, 'value': val, 'op': '+'})
						else:
							new_data.append({'type': 'keyvalue', 'key': key, 'value': val})
						c += 1
				else:
					# Simple value
					new_data.append({'type': 'keyvalue', 'key': key, 'value': str_value})
				found = True
			else:
				new_data.append(item)
		if not found:
			new_data.append({'type': 'keyvalue', 'key': key, 'value': str_value})

		return new_data

	def _find_or_create_struct_value(self, section: list, key: str, str_value: Union[str, list]) -> list:
		"""
		Find or create an idividual struct keyvalue in a given section
		and return the full section data.

		:param section:
		:param key:
		:param str_value:
		:return:
		"""
		found = False
		group = key.split('/')[0]
		key = key.split('/')[1]
		new_data = []

		for item in section:
			if item['type'] == 'keystruct' and item['key'] == group:
				if found:
					# This key has already been handled, so skip any more of them.
					continue
				else:
					# Update the struct value
					struct_data = item['value']
					struct_data[key] = str_value
					new_data.append({'type': 'keystruct', 'key': group, 'value': struct_data})
					found = True
			else:
				new_data.append(item)
		if not found:
			struct_data = {key: str_value}
			new_data.append({'type': 'keystruct', 'key': group, 'value': struct_data})

		return new_data

	def set_value(self, name: str, value: Union[str, int, bool, list, float]):
		"""
		Set a configuration option in the config

		:param name: Name of the option
		:param value: Value to save
		:return:
		"""
		if name not in self.options:
			print('Invalid option: %s, not present in %s configuration!' % (name, os.path.basename(self.path)), file=sys.stderr)
			return

		section = self.options[name][0]
		key = self.options[name][1]
		val_type = self.options[name][3]
		str_value = BaseConfig.convert_from_system_type(value, val_type)

		if section not in self._values:
			# Create the section
			self._values[section] = {}
			self._data.append([{'type': 'section', 'value': section}])

		# Ensure the updated value is in the data structure
		# First, find the section in the data
		new_data = []
		for sec in self._data:
			if sec[0]['type'] == 'section' and sec[0]['value'] == section:
				if '/' in key:
					# Struct key
					new_data.append(self._find_or_create_struct_value(sec, key, str_value))
				else:
					# Found it, add the keyvalue or update existing
					new_data.append(self._find_or_create_value(sec, key, str_value))
			else:
				# Not matched, but keep the data
				new_data.append(sec)

		self._data = new_data
		self._values[section][key] = str_value
		self._is_changed = True

	def has_value(self, name: str) -> bool:
		"""
		Check if a configuration option has been set

		:param name: Name of the option
		:return:
		"""
		if name not in self.options:
			return False

		section = self.options[name][0]
		key = self.options[name][1]
		if section not in self._values:
			return False
		else:
			if key not in self._values[section]:
				return False
			else:
				return self._values[section][key] != ''

	def exists(self) -> bool:
		"""
		Check if the config file exists on disk
		:return:
		"""
		return os.path.exists(self.path)

	def load(self):
		"""
		Load the configuration file from disk
		:return:
		"""
		if os.path.exists(self.path):
			with open(self.path, 'r', encoding='utf-8') as f:
				section = []
				last_section = ''
				for line in f.readlines():
					data = None
					stripped = line.strip()
					if stripped == '':
						continue
					elif stripped.startswith(';'):
						# Comment line
						data = {'type': 'comment', 'value': stripped[1:].strip()}
					elif stripped.startswith('[') and stripped.endswith(']'):
						# Section header
						data = {'type': 'section', 'value': stripped[1:-1].strip()}
					elif '=' in stripped:
						# Key-value pair
						parts = stripped.split('=', 1)
						key = parts[0].strip()
						value = parts[1].strip()
						if key.startswith('+'):
							# Array operator detected
							self._use_array_operators = True
							op = key[0]
							key = key[1:].strip()
							data = {'type': 'keyvalue', 'key': key, 'value': value, 'op': op}
						elif value.startswith('(') and value.endswith(')'):
							# Struct detected
							struct_str = value[1:-1].strip()
							struct_data = self._parse_struct(struct_str)
							data = {'type': 'keystruct', 'key': key, 'value': struct_data}
						else:
							data = {'type': 'keyvalue', 'key': key, 'value': value}

					if data is not None:
						if data['type'] == 'section':
							# New section!
							if len(section) > 0:
								self._data.append(section)
							section = []
							section.append(data)
							last_section = data['value']
						elif data['type'] == 'keystruct':
							section.append(data)
							if last_section not in self._values:
								self._values[last_section] = {}
							self._values[last_section][data['key']] = data['value']
						elif data['type'] == 'keyvalue':
							section.append(data)
							if last_section not in self._values:
								self._values[last_section] = {}
							# Auto-handle duplicate keys by converting them to a list.
							# UE is weird.
							if data['key'] in self._values[last_section]:
								# Existing key, convert to list
								existing_value = self._values[last_section][data['key']]
								if not isinstance(existing_value, list):
									existing_value = [existing_value]
								existing_value.append(data['value'])
								self._values[last_section][data['key']] = existing_value
							else:
								self._values[last_section][data['key']] = data['value']
						else:
							section.append(data)
				if len(section) > 0:
					self._data.append(section)
		self._is_changed = False

	def _skip_escaping(self, s):
		"""
		Simple check to see if a given value should have escaping skipped.

		:param s:
		:return:
		"""
		if not isinstance(s, str):
			# ints/floats do not require escaping
			return isinstance(s, (int, float, bool))

		if s == 'True' or s == 'False':
			# Boolean values do not require escaping
			return True

		if s == '':
			# Empty values always require quoting
			return False

		# match integers and decimals (optional leading +/-)
		return re.match(r'^[+-]?\d+(?:\.\d+)?$', s) is not None

	def _parse_struct(self, struct_str: str) -> dict:
		"""
		Parse a UE struct string into a dictionary

		:param struct_str:
		:return:
		"""
		result = {}
		key = ''
		sub_key = ''
		buffer = ''
		quote = None
		group = None
		vals = []
		for c in struct_str:
			if c in ('"', "'") and quote is None:
				# Quote start
				quote = c
				continue
			elif quote is not None and c == quote:
				# Quote end
				quote = None
				continue
			elif quote is not None:
				# Quoted text, (skip parsing)
				buffer += c
				continue

			if c == '(':
				group = c
				continue
			elif c == ')' and group is not None:
				group = None
				#if buffer != '':
				if sub_key != '':
					if isinstance(vals, list):
						# This needs to be a dictionary in this case.
						vals = {}
					vals[sub_key] = buffer
					sub_key = ''
				else:
					vals.append(buffer)

				if key == '':
					# This is a list of values, not a dictionary.
					if isinstance(result, dict):
						result = []
					result.append(vals)
				else:
					result[key] = vals
				vals = []
				buffer = ''
				key = ''
				continue

			if c == '=' and buffer != '':
				if group is not None:
					# When inside a group, this indicates it's a dict.
					sub_key = buffer
				else:
					key = buffer
				buffer = ''
			elif c == ',':
				if sub_key != '':
					if isinstance(vals, list):
						# This needs to be a dictionary in this case.
						vals = {}
					vals[sub_key] = buffer
					sub_key = ''
				elif key != '':
					if group is not None:
						# Inside a group, usually a list
						vals.append(buffer)
					else:
						result[key] = buffer
						key = ''
				buffer = ''
			else:
				buffer += c
		if key != '':
			result[key] = buffer
		return result

	def _pack_struct(self, struct_data: dict) -> str:
		"""
		Pack a dictionary into a UE struct string

		:param struct_data:
		:return:
		"""
		parts = []
		if isinstance(struct_data, list):
			# List of values
			for value in struct_data:
				if isinstance(value, dict):
					val_str = self._pack_struct(value)
				elif value == '' or ':' in value or ',' in value:
					# Needs quoting
					val_str = '"%s"' % value.replace('"', '\\"')
				else:
					val_str = value
				parts.append(val_str)
			return '(' + ','.join(parts) + ')'
		else:
			for key in struct_data:
				value = struct_data[key]
				if isinstance(value, list):
					val_str = '(' + ','.join(value) + ')'
				elif self._skip_escaping(value):
					# No quoting required
					val_str = str(value)
				else:
					# Default for structs is to quote values.
					val_str = '"%s"' % value.replace('"', '\\"')
				parts.append('%s=%s' % (key, val_str))
			return '(' + ','.join(parts) + ')'

	def fetch(self) -> str:
		"""
		Render the configuration file to a string, used in saving back to the disk.

		:return:
		"""
		output_lines = []
		for section in self._data:
			for item in section:
				if item['type'] == 'comment':
					output_lines.append('; %s' % item['value'])
				elif item['type'] == 'section':
					if len(output_lines) > 0:
						output_lines.append('')  # Blank line before new section
					output_lines.append('[%s]' % item['value'])
				elif item['type'] == 'keyvalue':
					if 'op' in item:
						output_lines.append('%s%s=%s' % (item['op'], item['key'], item['value']))
					else:
						output_lines.append('%s=%s' % (item['key'], item['value']))
				elif item['type'] == 'keystruct':
					struct_str = self._pack_struct(item['value'])
					output_lines.append('%s=%s' % (item['key'], struct_str))
		return '\n'.join(output_lines).strip() + '\n'

	def save(self):
		"""
		Save the configuration file back to disk
		:return:
		"""
		if not self._is_changed:
			# No changes, skip save
			return

		gid = None
		uid = None
		chown = False

		if os.geteuid() == 0:
			# Determine game user based on parent directories
			check_path = os.path.dirname(self.path)
			while check_path != '/' and check_path != '':
				if os.path.exists(check_path):
					stat_info = os.stat(check_path)
					uid = stat_info.st_uid
					gid = stat_info.st_gid
					chown = True
					break
				check_path = os.path.dirname(check_path)

		# Prepare atomic write to a temporary file in the same directory
		dirname = os.path.dirname(self.path) or '.'
		temp_file = None
		try:
			# Determine mode to use for the new file. If target exists use its mode, otherwise default to 0o644
			if os.path.exists(self.path):
				target_mode = os.stat(self.path).st_mode & 0o777
			else:
				# Try to inherit from parent dir if possible
				try:
					parent_mode = os.stat(dirname).st_mode & 0o777
					# Use a sensible default based on parent directory while respecting the process umask.
					prev_umask = os.umask(0)
					try:
						target_mode = parent_mode & (~prev_umask)
					finally:
						# Restore the previous umask immediately
						os.umask(prev_umask)
				except Exception:
					target_mode = 0o644

			# Create a NamedTemporaryFile in same directory; do not delete automatically
			tf = tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=dirname, delete=False)
			temp_file = tf.name
			try:
				# Write contents and flush to disk
				tf.write(self.fetch())
				tf.flush()
				os.fsync(tf.fileno())
			finally:
				tf.close()

			# Set permissions on the temp file to match target_mode
			try:
				os.chmod(temp_file, target_mode)
			except Exception:
				# chmod failure is non-fatal, proceed
				pass

			# Atomically replace target with temp file
			os.replace(temp_file, self.path)
			temp_file = None

			# Restore ownership if required
			if chown and uid is not None and gid is not None:
				try:
					os.chown(self.path, uid, gid)
				except PermissionError:
					# If we can't chown, proceed silently
					pass
			# Mark as clean
			self._is_changed = False
		except Exception:
			# Cleanup temporary file on error
			if temp_file and os.path.exists(temp_file):
				try:
					os.unlink(temp_file)
				except Exception:
					pass
			raise


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
		services_path = os.path.join(here, 'services')
		for f in os.listdir(services_path):
			if f.endswith('.conf'):
				self.services.append(f[:-5])

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
