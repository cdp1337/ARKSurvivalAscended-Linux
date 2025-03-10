#!/usr/bin/env python3

import re
import shutil
import uuid
from glob import glob
import os
import stat
from pprint import pprint
import json
import urllib.request


class Script:
	def __init__(self, file: str, type: str):
		self.file = file
		self.type = type
		self.title = None
		self.readme = None
		self.author = None
		self.guid = None
		self.category = None
		self.draft = False
		self.trmm_timeout = 60
		self.supports = []
		self.supports_detailed = []
		self.scriptlets = []
		self.imports = []
		self.args = []
		self.env = []
		self.syntax = []
		self.syntax_arg_map = []
		self.description = ''
		self.content_header = ''
		self.content_body = ''
		self._generated_usage = False

	def parse(self):
		"""
		Parse a script file to produce a single distributable file with all dependencies included
		:return:
		"""
		print('Parsing file %s' % self.file)
		line_number = 0
		in_header = True
		parse_description = True
		header_section = None
		multiline_header = False

		self._parse_guid()

		if os.path.exists(os.path.join(os.path.dirname(self.file), 'README.md')):
			self.readme = os.path.join(os.path.dirname(self.file), 'README.md')

		with open(self.file, 'r') as f:
			for line in f:
				line_number += 1
				write = True

				if line.startswith('# scriptlet:'):
					# Check for "# scriptlet:..." replacements
					in_header = False
					include = line[12:].strip()
					line = self._parse_include(self.file, line_number, include)
				elif line.startswith('# script:'):
					# Check for "# script:..." replacements
					in_header = False
					include = line[9:].strip()
					line = self._parse_script(self.file, line_number, include)
				elif line.startswith('import ') and self.type == 'python':
					in_header = False
					self._parse_import(line)
					write = False
				elif line.startswith('from scriptlets.') and self.type == 'python':
					in_header = False
					# Treat this as a scriptlet include
					# Trim "from scriptlets." off the beginning to get the filename
					line = line[16:].strip()
					# Trim anything after "import..."; we'll just include the whole file
					line = line[:line.index(' import')]
					line = line.replace('.', '/') + '.py'
					line = self._parse_include(self.file, line_number, line)
				elif re.match(r'^from .* import .*', line) and self.type == 'python':
					in_header = False
					self._parse_import(line)
					write = False
				elif line.strip() == '# compile:usage':
					in_header = False
					line = self.generate_usage()
				elif line.strip() == '# compile:argparse':
					in_header = False
					line = self.generate_argparse()
				elif in_header and self.type == 'python' and line.strip() == '"""':
					multiline_header = not multiline_header
				elif in_header and self.type == 'powershell' and line.strip() == '<#':
					multiline_header = True
				elif in_header and self.type == 'powershell' and line.strip() == '#>':
					multiline_header = False
					in_header = False

				if line_number > 1 and in_header and not multiline_header:
					if self.type == 'python':
						# Lines that do not start with '"""' indicate that we are no longer in the file header
						in_header = line.startswith('"""') or line.startswith('#')
					elif not line.startswith('#'):
						# End of '#' lines indicate an end of the header
						in_header = False

				if in_header:
					att_start = '\t' if multiline_header else '#  '

					# Process header tags
					if self.title is None and self.type == 'python' and multiline_header and line.strip() != '':
						if line.startswith('"""'):
							# Allow the title to be placed on the first line of the docstring block
							t = line[3:].strip()
							self.title =  t if len(t) > 0 else None
						else:
							self.title = line.strip()
					elif self.title is None and line.strip() != '#' and not multiline_header and line_number > 1:
						self.title = line[1:].strip()
					elif '@AUTHOR' in line:
						parse_description = False
						self._parse_author(line[9:].strip())
					elif '@SUPPORTS' in line:
						parse_description = False
						self._parse_supports(line)
					elif '@CATEGORY' in line:
						parse_description = False
						self.category = line[11:].strip()
					elif '@TRMM-TIMEOUT' in line:
						parse_description = False
						self.trmm_timeout = int(line[15:].strip())
					elif re.match(r'^(# |\.|)trmm arguments(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'trmm_args'
					elif re.match(r'^(# |\.|)trmm environment(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'trmm_env'
					elif re.match(r'^(# |\.|)syntax(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'syntax'
					elif re.match(r'^(# |\.|)supports(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'supports'
					elif re.match(r'^(# |\.|)category(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'category'
					elif re.match(r'^(# |\.|)title(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'title'
					elif re.match(r'^(# |\.|)draft(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'draft'
					elif re.match(r'^(# |\.|)author(:|)$', line.lower().strip()):
						parse_description = False
						header_section = 'author'
					elif line[0:len(att_start)] == att_start and header_section == 'trmm_args':
						self._parse_arg(line)
					elif line[0:len(att_start)] == att_start and header_section == 'trmm_env':
						self._parse_env(line)
					elif line[0:len(att_start)] == att_start and header_section == 'syntax':
						line = self._parse_syntax(line)
					elif line[0:len(att_start)] == att_start and header_section == 'supports':
						self._parse_supports(line)
					elif line[0:len(att_start)] == att_start and header_section == 'category':
						self.category = line[1:].strip()
					elif line[0:len(att_start)] == att_start and header_section == 'title':
						self.title = line[1:].strip()
					elif line[0:len(att_start)] == att_start and header_section == 'draft':
						val = line[1:].strip().lower()
						self.draft = (val == '1' or val == 'true' or val == 'yes')
					elif line[0:len(att_start)] == att_start and header_section == 'author':
						self._parse_author(line[1:].strip())
					elif line.lower().startswith('# category: '):
						parse_description = False
						header_section = None
						self.category = line[12:].strip()
					elif line.strip() == '#' and header_section is not None:
						header_section = None
						parse_description = False
					elif line.strip() == '' and header_section is not None:
						header_section = None
						parse_description = False
					elif parse_description and line_number > 1:
						if line.strip() == '#':
							self.description += '\n'
						else:
							self.description += line[2:]

				if write:
					if in_header:
						self.content_header += line
					else:
						self.content_body += line

		# Post-parsing operations
		self.description = self.description.strip()

	def write(self):
		"""
		Write generated script to the filesystem
		:return:
		"""
		dest_file = 'dist/' + self.file[4:]
		if not os.path.exists(os.path.dirname(dest_file)):
			os.makedirs(os.path.dirname(dest_file))

		# Generate the compiled file
		with open(dest_file, 'w') as dest_f:
			dest_f.write(self.content_header)
			if self.type == 'python':
				dest_f.write('\n'.join(self.imports))
			dest_f.write(self.content_body)
		# Ensure new file is executable
		os.chmod(dest_file, 0o775)

		# Store the TRMM metafile
		#script_name = os.path.basename(self.file)[:-3]
		#with open(os.path.join(os.path.dirname(dest_file), script_name + '.json'), 'w') as dest_f:
		#	dest_f.write(json.dumps([self.as_trmm_meta()], indent=4))

	def _parse_import(self, line: str):
		"""
		Parse Python-style 'import' statements to the parent script
		:param line:
		:return:
		"""
		# import blah
		if not line.strip() in self.imports:
			self.imports.append(line.strip())

	def _parse_script(self, src_file: str, src_line: int, include: str):
		file = os.path.join('scripts', include)
		if not os.path.exists(file):
			print('ERROR - script %s not found' % include)
			print('  in file %s at line %d' % (src_file, src_line))
			return '# ERROR - script ' + include + ' not found\n\n'

		out = ''
		with open(file, 'r') as f:
			escape = True
			for line in f:
				# Provide options for escaping or not escaping lines
				# Useful for injecting variables from the calling script.
				if 'compile:noescape' in line:
					escape = False
					continue
				if 'compile:escape' in line:
					escape = True
					continue

				# @todo language-specific escaping
				out += line if not escape else line.replace('$', '\\$')

		if not out.endswith('\n'):
			out += '\n'
		return out

	def _parse_include(self, src_file: str, src_line: int, include: str):
		if include not in self.scriptlets:
			self.scriptlets.append(include)
			file = os.path.join('scriptlets', include)
			if not os.path.exists(file):
				# Try to auto-download scripts from the repository
				if not os.path.exists(os.path.dirname(file)):
					os.makedirs(os.path.dirname(file))
				try:
					print('Trying to auto-download %s scriptlet from Github' % include)
					url_path = 'https://raw.githubusercontent.com/eVAL-Agency/ScriptsCollection/refs/heads/main/scriptlets/%s'
					urllib.request.urlretrieve(url_path % include, file)
				except Exception as e:
					print('Could not download scriptlet %s' % include)

			if os.path.exists(file):
				script = Script(file, self.type)
				script.scriptlets = self.scriptlets
				script.imports = self.imports
				# Parse the source
				script.parse()
				return script.content_header + script.content_body
			else:
				print('ERROR - script %s not found' % include)
				print('  in file %s at line %d' % (src_file, src_line))
				return '# ERROR - scriptlet ' + include + ' not found\n\n'
		else:
			return ''

	def _parse_syntax(self, line: str) -> str:
		"""
		Parse a syntax line and extract any arguments

		Supports `SOMEVAR=--some-arg` syntax for generating the usage() and parse argument functionality

		:param line:
		:return:
		"""
		#   -n - Run in non-interactive mode, (will not ask for prompts)
		line = line[1:].strip()
		arg_map = re.match(
			r'^((?P<var>[A-Za-z][A-Za-z0-9_]*)=)?' +
			r'(?P<tacks>[\-]+)(?P<name>[A-Za-z\-]*)' +
			r'(?P<type>[= ])' +
			r'(\<(?P<var_type>.+)\>)?' +
			r'(?P<comment>.*)$',
			line
		)
		if arg_map:
			tacks = arg_map.group('tacks')
			arg_var = arg_map.group('var')
			arg_name = arg_map.group('name')
			arg_type = arg_map.group('type')
			arg_default = '0' if arg_type == ' ' else ''
			var_type = arg_map.group('var_type')
			if arg_var is None:
				arg_var = arg_name

			if arg_type == '=':
				# Key/Value pairs require a variable type to be set, defaults to STRING
				var_type = 'string' if var_type is None else var_type

			if var_type is None:
				line = tacks + arg_name + arg_type + arg_map.group('comment')
			else:
				line = tacks + arg_name + arg_type + '<' + var_type + '>' + arg_map.group('comment')

			arg_required = 'REQUIRED' in line
			if 'DEFAULT=' in line:
				arg_default = line[line.find('DEFAULT=')+8:]
				if arg_default[0] == '"':
					# Default contains quotes, grab the content between them
					arg_default = arg_default[1:]
					arg_default = arg_default[:arg_default.find('"')]
				elif arg_default[0] == "'":
					# Default contains single quote, grab the content between them
					arg_default = arg_default[1:]
					arg_default = arg_default[:arg_default.find("'")]
				else:
					# Default is a value, grab the first word
					arg_default = arg_default.split(' ')[0]

			self.syntax_arg_map.append({
				'var': arg_var,
				'name': tacks + arg_name,
				'type': arg_type,
				'var_type': var_type,
				'required': arg_required,
				'default': arg_default
			})
		self.syntax.append(line)

		return ('#   ' if self.type == 'shell' else '\t') + line + '\n'

	def _parse_arg(self, line: str):
		#   -n - Run in non-interactive mode, (will not ask for prompts)
		line = line[1:].strip()
		self.args.append(line)

	def _parse_env(self, line: str):
		#   ZABBIX_SERVER - Hostname or IP of Zabbix server
		line = line[1:].strip()
		self.env.append(line)

	def _parse_guid(self):
		hashedValueEven = hashedValueOdd = 3074457345618258791
		KnuthMultiValue = 3074457345618258799
		i = 1
		for char in self.file.replace('\\', '/'):
			i += 1
			if i % 2 == 0:
				hashedValueEven = (hashedValueEven + ord(char)) * KnuthMultiValue
			else:
				hashedValueOdd = (hashedValueOdd + ord(char)) * KnuthMultiValue

		frame = bytearray()
		frame.append(0xff & hashedValueEven)
		frame.append(0xff & hashedValueEven >> 8)
		frame.append(0xff & hashedValueEven >> 16)
		frame.append(0xff & hashedValueEven >> 24)
		frame.append(0xff & hashedValueEven >> 32)
		frame.append(0xff & hashedValueEven >> 40)
		frame.append(0xff & hashedValueEven >> 48)
		frame.append(0xff & hashedValueEven >> 56)
		frame.append(0xff & hashedValueOdd)
		frame.append(0xff & hashedValueOdd >> 8)
		frame.append(0xff & hashedValueOdd >> 16)
		frame.append(0xff & hashedValueOdd >> 24)
		frame.append(0xff & hashedValueOdd >> 32)
		frame.append(0xff & hashedValueOdd >> 40)
		frame.append(0xff & hashedValueOdd >> 48)
		frame.append(0xff & hashedValueOdd >> 56)
		self.guid = uuid.UUID(bytes=bytes(frame)).__str__()


	def _parse_author(self, line):
		if '<' in line and '>' in line:
			n = line[:line.find('<')].strip()
			e = line[line.find('<')+1:line.find('>')].strip()
			self.author = {'name': n, 'email': e}
		else:
			self.author = {'name': line, 'email': None}

	def _parse_supports(self, line):
		if line.lower().startswith('# @supports'):
			# @SUPPORTS ubuntu, debian, centos
			line = line[11:].strip()
		else:
			# Supports:\n#  Distro Name\n...
			line = line[1:].strip()
		s = line.lower()
		maps = [
			('archlinux', ('linux-all', 'archlinux', 'arch')),
			('centos', ('linux-all', 'rhel-all', 'centos')),
			('debian', ('linux-all', 'debian-all', 'debian')),
			('fedora', ('linux-all', 'rhel-all', 'fedora')),
			('linuxmint', ('linux-all', 'debian-all', 'linuxmint')),
			('redhat', ('linux-all', 'rhel-all', 'redhat', 'rhel')),
			('rocky', ('linux-all', 'rhel-all', 'rocky', 'rockylinux')),
			('suse', ('linux-all', 'suse', 'opensuse')),
			('ubuntu', ('linux-all', 'debian-all', 'ubuntu')),
			('windows', ('windows',))
		]
		for os_key, lookups in maps:
			for lookup in lookups:
				if lookup in s and os_key not in self.supports:
					self.supports.append(os_key)
					self.supports_detailed.append((os_key, line))

	def generate_usage(self) -> str:
		"""
		Generate a usage function for this file based on inline documentation strings
		:return:
		"""
		self._generated_usage = True
		code = []
		code.append('function usage() {')
		code.append('  cat >&2 <<EOD')
		if len(self.syntax) > 0:
			code.append('Usage: $0 [options]')
		else:
			code.append('Usage: $0')
		code.append('')
		if len(self.syntax) > 0:
			code.append('Options:')
			for arg in self.syntax:
				code.append('    ' + arg.replace('$', '\\$'))
			code.append('')
		code.append(self.description.strip().replace('$', '\\$'))
		code.append('EOD')
		code.append('  exit 1')
		code.append('}')
		code.append('')
		code.append('')
		return '\n'.join(code)

	def generate_argparse(self) -> str:
		if self.type == 'shell':
			return self._generate_argparse_shell()
		elif self.type == 'powershell':
			return self._generate_argparse_powershell()
		else:
			return ''

	def _generate_argparse_powershell(self) -> str:
		params = []
		for arg in self.syntax_arg_map:
			if arg['var_type'] == 'integer':
				arg['var_type'] = 'int'
			params.append('\t[%s]$%s = %s' % (arg['var_type'], arg['var'], arg['default']))

		return '# Parse arguments\nparam (\n' + ',\n'.join(params) + '\n)\n\n'

	def _generate_argparse_shell(self) -> str:
		code = []

		code.append('# Parse arguments')
		# Print default arguments to at least have them defined
		for arg in self.syntax_arg_map:
			if arg['type'] == '=':
				code.append('%s="%s"' % (arg['var'], arg['default']))
			else:
				code.append('%s=0' % arg['var'])

		# Print primary WHILE loop to iterate over arguments and parse each
		code.append('while [ "$#" -gt 0 ]; do')
		code.append('\tcase "$1" in')
		for arg in self.syntax_arg_map:
			if arg['type'] == '=':
				# --version=*) VERSION="${1#*=}"; shift 1;;
				code.append('\t\t%s=*) %s="${1#*=}"; shift 1;;' % (arg['name'], arg['var']))
			else:
				# --noninteractive) NONINTERACTIVE=1; shift 1;;
				code.append('\t\t%s) %s=1; shift 1;;' % (arg['name'], arg['var']))

		# Include a "help" option if usage() was generated
		if self._generated_usage:
			code.append('\t\t-h|--help) usage;;')
		code.append('\tesac')
		code.append('done')
		for arg in self.syntax_arg_map:
			if arg['required']:
				code.append('if [ -z "$%s" ]; then' % arg['var'])
				if self._generated_usage:
					code.append('\tusage')
				else:
					code.append('\techo "ERROR: %s is required" >&2' % arg['name'])
				code.append('fi')
		code.append('')
		code.append('')
		return '\n'.join(code)

		# @todo Support #-p) pidfile="$2"; shift 2;;


	def __str__(self):
		return 'Script: %s' % self.file

	def get_full_author(self) -> str:
		if self.author is None:
			return ''
		elif self.author['email']:
			return '%s <%s>' % (self.author['name'], self.author['email'])
		else:
			return self.author['name']

	def asdict(self):
		return {
			'file': self.file,
			'title': self.title,
			'readme': self.readme,
			'author': self.author,
			'supports': self.supports,
			'supports_detailed': self.supports_detailed,
			'category': self.category,
			'trmm_timeout': self.trmm_timeout,
			'guid': self.guid,
			'syntax': self.syntax,
			'args': self.args,
			'env': self.env,
			'draft': self.draft
		}

	def as_trmm_meta(self):
		# TRMM treats all *nix distros as just "linux"
		all_platforms = (
			('linux', ('archlinux', 'centos', 'debian', 'fedora', 'linuxmint', 'redhat', 'rocky', 'suse', 'ubuntu')),
			('macos', ('macos',)),
			('windows', ('windows',)),
		)
		platforms = []

		for platform, distros in all_platforms:
			if any([x in self.supports for x in distros]):
				platforms.append(platform)

		filename = os.path.basename(self.file)
		# Fix windows-style directory separators
		filename = filename.replace('\\', '/')

		return {
			'$schema': 'https://raw.githubusercontent.com/amidaware/community-scripts/main/community_scripts.schema.json',
			'guid': self.guid,
			'filename': filename,
			'args': self.args,
			'env': self.env,
			'submittedBy': self.get_full_author(),
			'name': self.title,
			'syntax': self.syntax,
			'default_timeout': str(self.trmm_timeout),
			'shell': self.type,
			'supported_platforms': platforms,
			'category': self.category,
		}


# Clean the dist directory
if os.path.exists('dist'):
	shutil.rmtree('dist')

scripts = []

#s = Script('src/github/linux_install_github_runner.sh', 'shell')
#s.parse()
#s.write()
#pprint(s.asdict())
#exit(1)

# Parse and company any script files
for file in glob('src/**/*.sh', recursive=True):
	script = Script(file, 'shell')
	# Parse the source
	script.parse()
	script.write()
	# Add to stack to update project docs
	scripts.append(script)

for file in glob('src/**/*.py', recursive=True):
	script = Script(file, 'python')
	# Parse the source
	script.parse()
	script.write()
	# Add to stack to update project docs
	scripts.append(script)

for file in glob('src/**/*.ps1', recursive=True):
	script = Script(file, 'powershell')
	# Parse the source
	script.parse()
	script.write()
	# Add to stack to update project docs
	scripts.append(script)

# Locate and copy any README files
for file in glob('src/**/README.md', recursive=True):
	print('Copying README %s' % file)
	dest_file = 'dist/' + file[4:]
	if not os.path.exists(os.path.dirname(dest_file)):
		os.makedirs(os.path.dirname(dest_file))

	shutil.copy(file, dest_file)

# Generate project README
scripts.sort(key=lambda x: '-'.join([x.category if x.category else 'ZZZ', x.title if x.title else x.file]))
scripts_table = []
scripts_table.append('| Category / Script | Supports |')
scripts_table.append('|-------------------|----------|')
for script in scripts:
	if script.draft:
		continue
	title = script.title if script.title else script.file
	readme = script.readme if script.readme else None
	if readme is not None:
		# Fix windows-style directory separators
		readme = readme.replace('\\', '/')
		# Swap src/ with dist/ for the href target, (folks usually want to see the compiled version, not the source)
		readme = readme.replace('src/', 'dist/')
		# Markdown-ify it
		readme = '[![README](.supplemental/images/icons/readme.svg "README")](%s)' % readme
	else:
		readme = ''

	href = script.file
	# Fix windows-style directory separators
	href = href.replace('\\', '/')
	# Swap src/ with dist/ for the href target, (folks usually want to see the compiled version, not the source)
	href = href.replace('src/', 'dist/')

	if script.type == 'shell':
		type = '![Bash/Shell](.supplemental/images/icons/bash.svg "Bash/Shell")'
	elif script.type == 'powershell':
		type = '![PowerShell](.supplemental/images/icons/powershell.svg "PowerShell")'
	elif script.type == 'python':
		type = '![Python](.supplemental/images/icons/python.svg "Python")'
	else:
		type = script.type[0].upper() + script.type[1:]

	category = script.category if script.category else 'Uncategorized'
	os_support = []
	supported = script.supports_detailed
	supported.sort(key = lambda x: x[0])
	for support in supported:
		os_support.append('![%s](.supplemental/images/icons/%s.svg "%s")' % (support[0], support[0], support[1]))
	scripts_table.append('| %s [%s / %s](%s) %s | %s |' % (type, category, title, href, readme, ' '.join(os_support)))

if os.path.exists('.supplemental/README-template.md'):
	replacements = {
		'%%SCRIPTS_TABLE%%': '\n'.join(scripts_table),
	}
	with open('.supplemental/README-template.md', 'r') as f:
		template = f.read()
		for key, value in replacements.items():
			template = template.replace(key, value)

	with open('README.md', 'w') as f:
		f.write(template)

# Generate TRMM metafile
with open('dist/community_scripts.json', 'w') as f:
	meta = []
	for script in scripts:
		if script.draft:
			continue
		data = script.as_trmm_meta()
		data['filename'] = script.file[4:]
		meta.append(data)
	f.write(json.dumps(meta, indent=4))