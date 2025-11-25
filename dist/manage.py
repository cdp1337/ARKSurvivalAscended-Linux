#!/usr/bin/env python3
import argparse
import configparser
import json
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
from pathlib import Path
from typing import List
from pprint import pprint

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

		for row_data in self.data:
			row = []
			for i in range(len(row_data)):
				val = str(row_data[i])
				row.append(val)
				col_lengths[i] = max(col_lengths[i], self._text_width(val))
			rows.append(row)

		for row in rows:
			vals = []
			for i in range(len(row)):
				if i < len(self.align):
					align = self.align[i] if self.align[i] != '' else 'l'
				else:
					align = 'l'

				# Adjust the width of the total column width by the difference of icons within the text
				# This is required because icons are 2-characters in visual width.
				width = col_lengths[i] - (self._text_width(row[i]) - len(row[i]))

				if align == 'r':
					vals.append(row[i].rjust(width))
				elif align == 'c':
					vals.append(row[i].center(width))
				else:
					vals.append(row[i].ljust(width))

			if self.borders:
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
		with request.urlopen('https://api.ipify.org') as resp:
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
		self.desc = ''
		self.steam_id = ''

		self.services = []
		"""
		:type list<BaseService>:
		List of available services (instances) for this game
		"""

		self._svcs = None

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

	def set_option(self, option: str, value: str):
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
			val = prompt_yn(option, default)
		else:
			val = prompt_text(option, default=val, prefill=True)

		self.set_option(option, val)

	def get_services(self) -> dict:
		"""
		Get a dictionary of available services (instances) for this game

		:return:
		"""
		if self._svcs is None:
			self._svcs = {}
			for svc in self.services:
				self._svcs[svc] = GameService(svc, self)
		return self._svcs

	def is_active(self) -> bool:
		"""
		Check if any service instance is currently running or starting
		:return:
		"""
		for svc in self.get_services().values():
			if svc.is_running() or svc.is_starting() or svc.is_stopping():
				return True
		return False

	def check_update_available(self) -> bool:
		"""
		Check if there's an update available for this game

		:return:
		"""
		return False


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
		self.configs = {}

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
			val = prompt_yn(option, default)
		else:
			val = prompt_text(option, default=val, prefill=True)

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

	def post_start(self):
		"""
		Perform the necessary operations for after a game has started
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
			subprocess.run(['systemctl', 'start', self.service])

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
					break
				time.sleep(.5)
		except KeyboardInterrupt:
			print('Cancelled startup wait check, (game is probably still started)')

	def pre_stop(self):
		"""
		Perform operations necessary for safely stopping a server

		Called automatically via systemd
		:return:
		"""
		pass

	def stop(self):
		"""
		Stop this service in systemd
		:return:
		"""
		if os.geteuid() != 0:
			print('ERROR - Unable to stop game service unless run with sudo', file=sys.stderr)
			return

		print('Stopping server, please wait...')
		subprocess.run(['systemctl', 'stop', self.service])

	def restart(self):
		"""
		Restart this service in systemd
		:return:
		"""
		if not self.is_running():
			print('Game is not currently running!', file=sys.stderr)
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
								option.get('default'),
								option.get('type', 'str'),
								option.get('help', '')
							)

	def add_option(self, name, section, key, default, val_type, help_text):
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
		self.options[name] = (section, key, default, val_type, help_text)
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
	def convert_from_system_type(cls, value: Union[str, int, bool], val_type: str) -> str:
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
			elif value:
				return 'True'
			else:
				return 'False'
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
	def __init__(self, group_name: str):
		super().__init__(group_name)

		self.values = {}
		"""
		:type dict<str, str>
		Dictionary of current values for options set in the CLI
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
		val_type = self.options[name][3]
		val = self.values.get(name, default)

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
		return False

	def load(self, arguments: str):
		"""
		Load the configuration file from disk
		:return:
		"""
		# Use a tokenizer to parse options and flags
		options_done = False
		quote = None
		param = ''
		values = []
		# Add a space at the end to flush the last param
		arguments += ' '
		for c in arguments:
			if quote is None and c in ['"', "'"]:
				quote = c
				continue
			if quote is not None and c == quote:
				quote = None
				continue

			if not options_done and quote is None and c in ['?', ' ']:
				# '?' separates options
				if param == '':
					continue

				if '=' in param:
					opt_key, opt_val = param.split('=', 1)
					values.append((opt_key, opt_val, 'option'))
				else:
					values.append((param, '', 'option'))

				# Reset for next param
				param = ''
				if c == ' ':
					options_done = True
				continue

			if options_done and quote is None and c == '-':
				# Tack can be safely ignored
				continue

			if options_done and quote is None and c == ' ':
				# ' ' separates flags
				if param == '':
					continue

				if '=' in param:
					opt_key, opt_val = param.split('=', 1)
					values.append((opt_key, opt_val, 'flag'))
				else:
					opt_key = param
					values.append((opt_key, '', 'flag'))

				param = ''
				continue

			# Default behaviour; just append the character
			param += c

		# Arguments have been pulled from the command line, now set the values based on the options available
		for val in values:
			opt_key, opt_val, opt_group = val
			lower_key = opt_key.lower()
			if lower_key in self._keys:
				actual_key = self._keys[lower_key]
				section = self.options[actual_key][0]
				val_type = self.options[actual_key][3]
				if section != opt_group:
					print('Option type mismatch for %s: expected %s, got %s' % (opt_key, section, opt_group), file=sys.stderr)
					continue

				if opt_val == '' and val_type == 'bool':
					# Allow boolean flags to be set without a value
					self.values[actual_key] = 'True'
				else:
					self.values[actual_key] = opt_val
			else:
				print('Unknown option: %s, not present in configuration!' % opt_key, file=sys.stderr)

	def save(self):
		pass

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

			if val_type == 'bool' and raw_val.lower() in ('true', '1', 'yes'):
				# Booleans in command lines are simply present if True or absent if False.
				if section == 'flag':
					flags.append('-%s' % key)
				else:
					opts.append(key)
			else:
				if '"' in raw_val:
					raw_val = "'%s'" % raw_val
				elif "'" in raw_val or ' ' in raw_val or '?' in raw_val or '=' in raw_val:
					raw_val = '"%s"' % raw_val

				if section == 'flag':
					flags.append('-%s=%s' % (key, raw_val))
				else:
					opts.append('%s=%s' % (key, raw_val))

		return '%s %s' % ('?'.join(opts), ' '.join(flags))


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

		# Escape '%' characters that may be present
		value = value.replace('%', '%%')

		section = self.options[name][0]
		key = self.options[name][1]
		val_type = self.options[name][3]
		str_value = BaseConfig.convert_from_system_type(value, val_type)
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
	#def __init__(self, service: str, game: BaseGameApp):
	#	super().__init__(service, game)

	def _rcon_cmd(self, cmd) -> Union[None,str]:
		"""
		Execute a raw command with RCON and return the result

		:param cmd:
		:return: None if RCON not available, or the result of the command
		"""
		if not self.is_running():
			# If service is not running, don't even try to connect.
			return None

		if not self.is_api_enabled():
			# RCON is not available due to settings
			return None

		try:
			with Client('127.0.0.1', self.get_api_port(), passwd=self.get_api_password(), timeout=2) as client:
				return client.run(cmd).strip()
		except:
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

class UnrealConfigParser:
	"""
	Class to parse and modify Unreal Engine INI configuration files
	Version 1.2.0
	Forked from https://github.com/xwoojin/UEConfigParser
	Licensed under MIT License
	"""
	def __init__(self):
		"""Constructor"""
		self.content: List[str] = []
		self.changed = False

	def is_empty(self) -> bool:
		"""
		Check if the content is empty
		"""
		return len(self.content) == 0

	def is_changed(self) -> bool:
		"""
		Check if the content has been changed
		"""
		return self.changed

	def is_filename(self, file_path: str):
		"""
		Check if the file exists
		:param file_path: Path to the file
		"""
		return Path(file_path).name == file_path

	def read_file(self, file_path: str):
		"""Read and store file contents
			Args:
				file_path: Path to the INI file
			Raises:
				FileNotFoundError: If file doesn't exist
		"""
		if not os.path.exists(file_path):
			raise FileNotFoundError(f'File not found: {file_path}')

		with open(file_path, 'r', encoding='utf-8') as file:
			self.content = file.readlines()

		self.changed = False

	def write_file(self, output_path: str, newline_option=None):
		"""
		Writes output to a file with the changes made
		:param output_path: Path to the output file
		:param newline_option: Newline character to use. Options: 'None','\n', '\r\n' (default: None)
		"""
		file_path = output_path
		if self.is_filename(output_path):
			file_path = os.path.join(os.getcwd(), output_path)
		if not os.path.exists(os.path.dirname(file_path)):
			try:
				os.makedirs(os.path.dirname(file_path))
			except Exception as e:
				print(f'Directory create error: {file_path}', end='')
				print(e)
		try:
			with open(file_path, 'w', encoding='utf-8', newline=newline_option) as file:
				file.writelines(self.content)
			self.changed = False
		except Exception as e:
			print(f'File write error: ', end='')
			print(e)
			raise

	def is_section(self, line: str, section: str) -> bool:
		"""
		Checks if the line is a section
		:param line: Line to check
		:param section: Section name to compare
		"""
		if line.startswith('[') and line.endswith(']'):
			current_section = line[1:-1].strip()
			return current_section == section
		return False

	def add_key(self, section: str, key: str, value: str):
		"""
		Adds a key to a section
		:param section: Section name to add the key
		:param key: Key name to add
		:param value: Value to add
		"""
		in_section = False
		updated_lines = []
		section_found = False
		for index, line in enumerate(self.content):
			stripped = line.strip()
			if self.is_section(stripped, section):
				in_section = True
				section_found = True

			if in_section and (index + 1 == len(self.content) or self.content[index + 1].strip().startswith('[')):
				# Look-ahead to see if next line is a new section or end of file
				updated_lines.append(f"{key}={value}\n")
				self.changed = True
				in_section = False

			updated_lines.append(line)
		if not section_found:
			updated_lines.append(f'\n[{section}]\n')
			updated_lines.append(f'{key}={value}\n')
			self.changed = True
		self.content = updated_lines

	def add_key_after_match(self, section: str, substring: str, new_line: str):
		"""
		Adds a new line after the line in the specified section where the substring matches.

		:param section: The section name to search in
		:param substring: The substring to search for in lines within the section
		:param new_line: The new line to append after the matched line
		:raises ValueError: If the section or matching substring is not found
		"""
		in_section = False
		updated_lines = []
		section_found = False
		found = False
		for index, line in enumerate(self.content):
			stripped = line.strip()
			if self.is_section(stripped, section):
				in_section = True
				section_found = True
			if in_section and substring in stripped and not found:
				updated_lines.append(line)  # Add the current line
				updated_lines.append(new_line + '\n')  # Add the new line after the match
				self.changed = True
				found = True
			else:
				updated_lines.append(line)

			# If we exit the section
			if in_section and self.is_section(line, section) and stripped[1:-1] != section:
				in_section = False

		if not section_found:
			updated_lines.append(f'\n[{section}]\n')
			updated_lines.append(f'{new_line}\n')
			self.changed = True
		self.content = updated_lines

	def remove_key(self, section: str, key: str):
		"""
		Removes a key from a section
		:param section: Section name to remove the key
		:param key: Key name to remove
		"""
		in_section = False
		exists = False
		updated_lines = []
		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped and not stripped.startswith((';', '#')):
					current_key, value = map(str.strip, stripped.split('=', 1))
					if current_key == key:
						exists = True
						self.changed = True
						continue
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def remove_key_by_substring_search(self, section: str, substring: str, search_in_comment=False):
		"""
		Removes a key from a section
		:param section: Section name to remove the key
		:param key: Key name to remove
		"""
		in_section = False
		exists = False
		updated_lines = []
		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped:
					search = True
					if stripped.startswith(';') or stripped.startswith('#'):
						if not search_in_comment:
							search = False
					if search:
						if substring in stripped:
							exists = True
							self.changed = True
							continue
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def replace_value_with_same_key(self, section: str, key: str, new_value: str, spacing=False):
		"""
		Modifies the value of a key in a section
		:param section: Section name to modify
		:param key: Key name to modify
		:param new_value: New value to set
		:param spacing: Add space between key and the value (default: False)
		"""
		in_section = False
		exists = False
		updated_lines = []
		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped and not stripped.startswith((';', '#')):
					current_key, value = map(str.strip, stripped.split('=', 1))
					if current_key == key:
						if spacing:
							line = f'{key} = {new_value}\n'
						else:
							line = f'{key}={new_value}\n'
						self.changed = True
						exists = True
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def comment_key(self, section: str, key: str):
		"""
		Disables a key by commenting it out
		:param section: Section name to modify
		:param key: Key name to disable
		"""
		in_section = False
		exists = False
		updated_lines = []
		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped and not stripped.startswith((';', '#')):
					current_key, value = map(str.strip, stripped.split('=', 1))
					if current_key == key:
						line = f';{line}'
						self.changed = True
						exists = True
			updated_lines.append(line)
		if not exists:
			return False
		self.content = updated_lines
		return True

	def uncomment_key(self, section: str, key: str):
		"""
		Enables a key by uncommenting it
		:param section: Section name to modify
		:param key: Key name to enable
		"""
		in_section = False
		exists = False
		updated_lines = []
		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and stripped.startswith(';') and '=' in stripped:
					uncommented_line = stripped[1:].strip()
					current_key, value = map(str.strip, uncommented_line.split('=', 1))
					if current_key == key:
						line = uncommented_line + '\n'
						self.changed = True
						exists = True
			updated_lines.append(line)
		if not exists:
			return False
		self.content = updated_lines
		return True

	def set_value_by_substring_search(self, section: str, match_substring: str, new_value: str, search_in_comment=False):
		"""
		Updates the value of any key in the given section if the full 'key=value' string contains the match_substring. (even partial match)

		:param section: The section to search in.
		:param match_substring: The substring to match within the 'key=value' string.
		:param new_value: The new value to set if the substring matches.
		"""
		in_section = False
		updated_lines = []
		exists = False

		for line in self.content:
			search = True
			updated = False
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped:
					if stripped.startswith((';', '#')):
						if not search_in_comment:
							search = False
					if search:
						key, value = map(str.strip, stripped.split('=', 1))
						if match_substring in stripped:
							line = f'{key}={new_value}\n'
							self.changed = True
							exists = True
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def comment_by_substring_search(self, section: str, match_substring: str, search_in_comment=False):
		"""
		comment entire key if value is matched in given section  (even partial match)

		:param section: The section to search in.
		:param key: The key whose value needs to be updated.
		:param match_substring: The substring to match in the current value.
		"""
		in_section = False
		exists = False
		updated_lines = []

		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped and not exists:
					search = True
					if stripped.startswith(';') or stripped.startswith('#'):
						if not search_in_comment:
							search = False
					if search:
						current_key, value = map(str.strip, stripped.split('=', 1))
						if match_substring in value:
							line = f';{line}'
							self.changed = True
							exists = True
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def uncomment_by_substring_search(self, section: str, match_substring: str):
		"""
		uncomment entire key if value is matched in given section  (even partial match)

		:param section: The section to search in.
		:param match_substring: The substring to match in the current value.
		"""
		in_section = False
		exists = False
		updated_lines = []

		for line in self.content:
			if not exists:
				stripped = line.strip()
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and stripped.startswith(';'):
					uncommented_line = stripped[1:].strip()
					if match_substring in stripped:
						line = uncommented_line + '\n'
						self.changed = True
						exists = True
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def replace_value_by_substring_search(self, section: str, match_substring: str, new_substring: str, search_in_comment=False):
		"""
		Replaces a substring in the values as it treats key=value entire line as a single string within a given section.

		:param section: The section to search in.
		:param match_substring: The substring to match in the current value.
		:param new_substring: The new substring to replace the match.
		"""
		in_section = False
		exists = False
		updated_lines = []
		for line in self.content:
			search = True
			found = False
			stripped = line.strip()
			if not exists:
				if self.is_section(stripped, section):
					in_section = True
				elif stripped.startswith('[') and stripped.endswith(']'):
					in_section = False
				if in_section and '=' in stripped:
					if stripped.startswith(';') or stripped.startswith('#'):
						if not search_in_comment:
							search = False
					if search:
						if match_substring in stripped:
							line = stripped.replace(match_substring, new_substring) + '\n'
							self.changed = True
							exists = True
							found = True
			updated_lines.append(line)

		if not exists:
			return False
		self.content = updated_lines
		return True

	def display(self):
		"""
		Prints the lines to the console
		"""
		for line in self.content:
			print(line, end='')
		print(' ')

	def get_key(self, section: str, key: str, default: str = '') -> str:
		"""
		Get the value of a requested section/key.

		:param section: Section name to modify
		:param key: Key name to retrieve
		:param default: Default value if key not found

		:return: Value of the key or default if not found
		"""
		in_section = False
		for line in self.content:
			stripped = line.strip()
			if self.is_section(stripped, section):
				in_section = True
			elif stripped.startswith('[') and stripped.endswith(']'):
				in_section = False

			if in_section and '=' in stripped:
				uncommented_line = stripped[1:].strip() if stripped.startswith(';') else stripped
				current_key, value = map(str.strip, uncommented_line.split('=', 1))
				if current_key == key:
					return value

		return default

	def set_key(self, section: str, key: str, value: str):
		"""
		Sets a key/value pair to a section, creating it if necessary

		:param section: Section name to add the key
		:param key: Key name to add
		:param value: Value to add
		"""
		in_section = False
		updated_lines = []
		found = False
		for line in self.content:
			stripped = line.strip()
			if self.is_section(stripped, section):
				in_section = True
			elif stripped.startswith('[') and stripped.endswith(']'):
				in_section = False

			if in_section and '=' in stripped:
				if stripped.startswith(';'):
					uncommented_line = stripped[1:].strip()
					commented = True
				else:
					uncommented_line = stripped
					commented = False
				current_key, prev_value = map(str.strip, uncommented_line.split('=', 1))
				if current_key == key:
					# Key found; replace the line with the new value
					line = ';' if commented else '' + f"{key}={value}\n"
					self.changed = prev_value != value
					found = True
			updated_lines.append(line)

		if found:
			self.content = updated_lines
		else:
			self.add_key(section, key, value)


class UnrealConfig(BaseConfig):
	def __init__(self, group_name: str, path: str):
		super().__init__(group_name)
		self.path = path
		self.parser = UnrealConfigParser()

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
		type = self.options[name][3]
		val = self.parser.get_key(section, key, default)

		return BaseConfig.convert_to_system_type(val, type)

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
		self.parser.set_key(section, key, str_value)

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
		return self.parser.get_key(section, key, '') != ''

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
			self.parser.read_file(self.path)

	def save(self):
		"""
		Save the configuration file back to disk
		:return:
		"""
		if self.parser.is_changed():
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

			self.parser.write_file(self.path)
			if chown:
				os.chown(self.path, uid, gid)


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
