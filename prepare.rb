#!/usr/bin/ruby
require 'rubygems'
require 'fileutils'
require 'net/http'
require 'json'

# Getting any available user-data
response = Net::HTTP.start('169.254.169.254', 80) do |http|
  http.get('/2009-04-04/user-data')
end

# Have to call #name, because Class#=== checks #is_a?, and is thus unsuitable
# for a case statement
case response.code_type.name
when 'Net::HTTPOK'
  @user_data = JSON.parse(response.body)
when 'Net::HTTPNotFound'
  
else
  raise "EC2 API unavailable"
end

# Configuring the fstab based on instance type

response = Net::HTTP.start('169.254.169.254', 80) do |http|
  http.get('/2009-04-04/meta-data/instance-type')
end

raise "EC2 API unavailable" unless response.code_type == Net::HTTPOK
@instance_type = response.body

@stores = case @instance_type
when 'm1.xlarge' || 'c1.xlarge'
  ['sdb', 'sdc', 'sdd', 'sde']
when 'm1.large'
  ['sdb', 'sdc']
when 'm1.small' | 'c1.medium'
  ['sda2']
else
  raise "Invalid instance type returned by the EC2 API"
end

fstab, old = '/etc/fstab', '/etc/fstab.old'
FileUtils.mv fstab, old unless File.file? old

lines = File.open(old, 'r') {|f| f.read }.each_line.map {|f| f.split(/\s+/) }

lines.map! do |line|
  if line[0] =~ %r ^#?(/dev/(?:#{@stores.join '|'}))$ 
    line[0] = $1
    FileUtils.mkdir_p line[1]
    system "/bin/mount -t #{line[2]} #{line[0]} #{line[1]} -o #{line[3]}"
  end
  line
end

# Further configuring the fstab based on fstab entries provided by the user

if @user_data['fstab']
  fstab_extra = @user_data['fstab'].map {|f| f.split(/\s+/) }
  ebs_index = lines.index(lines.select {|l| l.include? "EBS" } .first)
  lines.insert(ebs_index + 1, *fstab_extra)

  fstab_extra.each do |line|
    FileUtils.mkdir_p line[1]
    system "/bin/mount -t #{line[2]} #{line[0]} #{line[1]} -o #{line[3]}"
  end
end

# Now we write out the modified fstab

File.open(fstab, 'w') do |f|
  lines.each {|line| f.puts line.join("\t") }
end

# Setting up the host and domain name

if @user_data['hostname']
  system "sed -i 's/myhost/#{@user_data['hostname']}/' /etc/rc.conf"
  system "hostname '#{@user_data['hostname']}'"
  system "sysctl kernel.hostname='#{@user_data['hostname']}'"
end

if @user_data['domain']
  File.open('/etc/conf.d/nisdomainname', 'w') {|f|
    f.print "NISDOMAINNAME=\"#{@user_data['domain']}\"" }
  system "nisdomainname '#{@user_data['domain']}'"
end

system "/etc/rc.d/syslog-ng restart"

if @user_data['hostname'] and @user_data['domain']
  response = Net::HTTP.start('169.254.169.254', 80) do |http|
    http.get('/2009-04-04/meta-data/local-ipv4')
  end
  
  if response.code_type == Net::HTTPOK
    @local_ipv4 = response.body
    
    File.open('/etc/hosts', 'a') do |hosts|
      hosts.print [
        @local_ipv4,
        [@user_data['hostname'], @user_data['domain']].join('.'),
        @user_data['hostname']
      ].join("\t")
    end
  end
end
