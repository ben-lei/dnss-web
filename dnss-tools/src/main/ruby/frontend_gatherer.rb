#!/bin/ruby
require 'json'
require 'pg'
require_relative 'common'
require_relative 'dn-weapons'
require_relative 'dn-skills'

##############################################################################
# Hopefully only thing you have to edit
##############################################################################
JSON_DIRECTORY = 'C:\\Users\\Ben\\IdeaProjects\\dn-skill-sim\\dnss-web\\src\\main\\webapp\\resources\\json'
# JSON_DIRECTORY = 'E:\\json'

##############################################################################
# get all messages
##############################################################################
messages = Hash.new
@conn.exec('SELECT * FROM messages').each_dnt {|message| messages[message['id']] = message['data']}

##############################################################################
# gets all the jobs [write]
# notes:
#   jobnumber => 0 = base, 1 = first advancement, etc.
##############################################################################
jobs = Hash.new
query = <<sql_query
  SELECT j._id,
          m._data as jobname,
         LOWER(_englishname) as englishname,
         _parentjob,
         _jobnumber,
         _jobicon
  FROM jobs j
  INNER JOIN messages m
    ON _jobname = m._id
  WHERE _service is TRUE
sql_query
@conn.exec(query).each_dnt do |job|
  job['skills'] = Hash.new
  job['message'] = Array.new    # prepare to store messages needed for skill descriptions
  jobs[job['id']] = job
  jobs[job['id']].delete('id')
end

# puts JSON.pretty_generate jobs

##############################################################################
# get all the skills of all classes
##############################################################################
query = <<sql_query
  SELECT _id,
         _nameid,
         _iconimageindex,
         _needjob,
         _skilltype as type,
         _needweapontype1, _needweapontype2,
         _maxlevel
  FROM skills
  WHERE _needjob > 0
  ORDER BY _needjob ASC
sql_query
@conn.exec(query).each_dnt do |skill|
  jobs[skill['needjob']]['skills'][skill['id']] = skill
  skill['nameid'] = get_local_message_id(jobs[skill['needjob']]['message'], skill['nameid'], messages)

  skill['levels'] = Array.new
  skill['image'] = '%02d' % ((skill['iconimageindex'] / 200) + 1)
  skill['icon'] = skill['iconimageindex'] % 200

  skill['needweapon'] = Array.new
  skill['needweapon'] << skill['needweapontype1'] unless skill['needweapontype1'] == -1
  skill['needweapon'] << skill['needweapontype2'] unless skill['needweapontype2'] == -1

  # delete these
  ['id', 'needjob', 'iconimageindex', 'needweapontype1', 'needweapontype2'].each {|a| skill.delete(a)}
end

##############################################################################
# get the skill tree for each class
##############################################################################
query = <<sql_query
  SELECT _needjob,
         _skilltableid as skillid,
         _parentskillid1, _parentskillid2,
         _needparentskilllevel1, _needparentskilllevel2,
         _needbasicsp1, _needfirstsp1
  FROM skill_tree
  INNER JOIN skills
    ON _skilltableid = skills._id
sql_query

@conn.exec(query).each_dnt do |tree|
  job = jobs[tree['needjob']]
  skills = job['skills']
  skill = skills[tree['skillid']]
  skill['requires'] = Array.new
  skill['requires'] << {'id' => tree['parentskillid1'], :level => tree['needparentskilllevel1']} unless tree['parentskillid1'] == 0
  skill['requires'] << {'id' => tree['parentskillid2'], :level => tree['needparentskilllevel2']} unless tree['parentskillid2'] == 0
  skill['sp_requires'] = [tree['needbasicsp1'], tree['needfirstsp1']]
end

##############################################################################
# get default skills
##############################################################################
queries = Array.new
base_query = <<sql_query
  SELECT _defaultskill%1$d as id, _needjob
  FROM default_create
  INNER JOIN skills s
    ON s._id = _defaultskill%1$d
  INNER JOIN jobs j
    ON j._id = _needjob
  WHERE _jobnumber = 0
sql_query
(1..10).each {|i| queries << base_query % i}
query = queries.join("UNION\n")
@conn.exec(query).each_dnt do |skill|
  job = jobs[skill['needjob']]
  if job['default_skills'].nil?
    job['default_skills'] = Array.new
  end

  job['default_skills'] << skill['id']
end


##############################################################################
# get all base jobs, and then get all tables of the base classes
# Notes:
#   _decreasehp, at this point of time, is always 0
##############################################################################
jobs.select {|id, job| job['jobnumber'] == 0}.each_value do |job|
  query = <<-sql_query
    SELECT  _needjob,
           _skillindex as id,
           _levellimit as required_level,
           _decreasesp as mpcost,
           _skillexplanationid as explanationid, _skillexplanationidparam,
           _needskillpoint as spcost
    FROM skills_%s_pve s
    INNER JOIN skills
      ON _skillindex = skills._id
    WHERE _needjob > 0
      AND _nameid > 0
    ORDER BY _skillindex, _skilllevel ASC
  sql_query

  @conn.exec(query % job['englishname']).each_dnt do |skill|
    jobs[skill['needjob']]['skills'][skill['id']]['levels'] << skill

    skillparams = skill['skillexplanationidparam'].to_s
    skillparams = skillparams.split(',').map {|str| str.strip.message_format(messages)}
    skill['explanationid'] = get_local_message_id(jobs[skill['needjob']]['message'], skill['explanationid'], messages)

    ['id', 'needjob', 'skillexplanationidparam'].each {|a| skill.delete(a)}
  end
end

##############################################################################
# get all the jobs, subjobs, etc. 
##############################################################################
job_tree = Hash.new
jobs.select {|k,v| v['jobnumber'] == 0}.each do |k,v|
  job_tree[k] = {
    'jobname' => v['jobname'],
    'identifier' => v['englishname'],
    'advancements' => Hash.new
  }
end

jobs.select {|k,v| v['jobnumber'] == 1}.each do |k,v|
  primary = v['parentjob']
  jtree = job_tree[primary]['advancements']
  jtree[k] = {
    'jobname' => v['jobname'],
    'identifier' => v['englishname'],
    'advancements' => Hash.new
  }
end

jobs.select {|k,v| v['jobnumber'] == 2}.each do |k,v|
  secondary = v['parentjob']
  primary = jobs[secondary]['parentjob']
  jtree = job_tree[primary]['advancements'][secondary]['advancements']
  jtree[k] = {
    'jobname' => v['jobname'],
    'identifier' => v['englishname']
  }
end

JSON_DIRECTORY.gsub!(/[\/\\]/, File::SEPARATOR)
mkdir_p(JSON_DIRECTORY)

##############################################################################
# WRITE: weapon types
##############################################################################
path = '%s%s%s.json' % [JSON_DIRECTORY, File::SEPARATOR, 'weapon_types']
stream = open(path, 'w')
stream.write(JSON.pretty_generate(DN_WEAPON_TYPES))
stream.close()

path = '%s%s%s.min.json' % [JSON_DIRECTORY, File::SEPARATOR, 'weapon_types']
stream = open(path, 'w')
stream.write(DN_WEAPON_TYPES.to_json)
stream.close()

##############################################################################
# WRITE: skill types
##############################################################################
path = '%s%s%s.json' % [JSON_DIRECTORY, File::SEPARATOR, 'skill_types']
stream = open(path, 'w')
stream.write(JSON.pretty_generate(DN_SKILL_TYPES))
stream.close()
puts '%s created' % path

path = '%s%s%s.min.json' % [JSON_DIRECTORY, File::SEPARATOR, 'skill_types']
stream = open(path, 'w')
stream.write(DN_SKILL_TYPES.to_json)
stream.close()
puts '%s created' % path

##############################################################################
# WRITE: all jobs
##############################################################################
jobs.each_value do |job|
  englishname = job['englishname']

  # deletes unneeded fields
  ['englishname', 'jobnumber', 'parentjob', 'jobname'].each {|a| job.delete(a)}

  path = '%s%s%s.json' % [JSON_DIRECTORY, File::SEPARATOR, englishname]
  stream = open(path, 'w')
  stream.write(JSON.pretty_generate(job))
  stream.close()
  puts '%s created' % path

  path = '%s%s%s.min.json' % [JSON_DIRECTORY, File::SEPARATOR, englishname]
  stream = open(path, 'w')
  stream.write(job.to_json)
  stream.close()
  puts '%s created' % path
end

##############################################################################
# WRITE: job tree
##############################################################################
path = '%s%s%s.json' % [JSON_DIRECTORY, File::SEPARATOR, 'job_tree']
stream = open(path, 'w')
stream.write(JSON.pretty_generate(job_tree))
stream.close()
puts '%s created' % path

path = '%s%s%s.min.json' % [JSON_DIRECTORY, File::SEPARATOR, 'job_tree']
stream = open(path, 'w')
stream.write(job_tree.to_json)
stream.close()
puts '%s created' % path

@conn.close()