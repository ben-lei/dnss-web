#!/bin/ruby
require 'json'
require 'pg'
require 'nokogiri'
require_relative 'common'


##############################################################################
# Hopefully only thing you have to edit
##############################################################################
BEAN_DIRECTORY = 'C:\\Users\\Ben\\IdeaProjects\\dn-skill-sim\\dnss-web\\src\\main\\webapp\\WEB-INF'
LEVEL_CAP = 80

##############################################################################
# get sp required of all classes [write]
##############################################################################
sp_by_level = Array.new
sp_by_level << 0
query = <<sql_query
  SELECT _id, _skillpoint
  FROM player_level
  WHERE _id <= %d
  ORDER BY _id ASC
sql_query
@conn.exec(query % LEVEL_CAP).each_dnt {|level| sp_by_level << sp_by_level[level['id'] - 1] + level['skillpoint']}

##############################################################################
# gets all the jobs [write]
# notes:
#   jobnumber => 0 = base, 1 = first advancement, etc.
#   maxspjobx => # ratio to max SP (floored); at the moment 3 and 4 are unused
##############################################################################
jobs = Hash.new
query = <<sql_query
  SELECT j._id,
         m._data as jobname,
         LOWER(_englishname) as identifier,
         _jobnumber as advancement,
         _parentjob,
         _maxspjob0, _maxspjob1, _maxspjob2
  FROM jobs j
  INNER JOIN messages m
    ON _jobname = m._id
  WHERE _service is TRUE
  ORDER BY _id ASC
sql_query
@conn.exec(query).each_dnt do |job|
  job['skilltree'] = Array.new
  jobs[job['id']] = job
  job['spRatio'] = [job['maxspjob0'], job['maxspjob1'], job['maxspjob2']]
  ['maxspjob0', 'maxspjob1', 'maxspjob2'].each {|a| job.delete(a)}
  jobs[job['id']].delete('id')
end

##############################################################################
# get the skill tree for each class
##############################################################################
query = <<sql_query
  SELECT _needjob,
         _skilltableid as skillid,
         _treeslotindex
  FROM skill_tree
  INNER JOIN skills
    ON _skilltableid = skills._id
sql_query

@conn.exec(query).each_dnt do |tree|
  job = jobs[tree['needjob']]
  jobs[tree['needjob']]['skilltree'][tree['treeslotindex']] = tree['skillid']
end


##############################################################################
# generate the bean file
##############################################################################
beans = {'xmlns' => 'http://www.springframework.org/schema/beans',
         'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
         'xmlns:util' => 'http://www.springframework.org/schema/util',
         'xsi:schemaLocation' => ['http://www.springframework.org/schema/beans',
                                  'http://www.springframework.org/schema/beans/spring-beans.xsd',
                                  'http://www.springframework.org/schema/util',
                                  'http://www.springframework.org/schema/util/spring-util.xsd'
                                 ].join(' ')}

builder = Nokogiri::XML::Builder.new do |xml|
  xml.beans(beans) do
    jobs.each_value do |job|
      job['skilltree'] = job['skilltree'].partition(4)
      xml.bean('id' => 'job_%s' % job['identifier'], 'class' => 'dnss.model.Job') do
        xml.property('name' => 'name', 'value' => job['jobname'])
        xml.property('name' => 'identifier', 'value' => job['identifier'])
        xml.property('name' => 'advancement', 'value' => job['advancement'])
        xml.property('name' => 'parent', 'ref' => 'job_%s' % jobs[job['parentjob']]['identifier']) unless job['parentjob'] == 0
        xml.property('name' => 'spRatio') {xml.list {job['spRatio'].each {|spRatio| xml.value_ spRatio}}}
        xml.property('name' => 'skillTree') {xml.list {job['skilltree'].each {|skillblock| xml.list {skillblock.each {|skill| xml.value_ skill.to_i}}}}}
      end
    end

    xml['util'].list('id' => 'levels', 'value-type' => 'int') {sp_by_level.each {|sp| xml.value_ sp}}
  end
end

BEAN_DIRECTORY.gsub!(/[\/\\]/, File::SEPARATOR)
mkdir_p(BEAN_DIRECTORY)
##############################################################################
# WRITE: Bean
##############################################################################
path = '%s%s%s.xml' % [BEAN_DIRECTORY, File::SEPARATOR, 'spring-context']
stream = open(path, 'w')
stream.write(builder.to_xml)
stream.close()

puts "%s has been created." % path

@conn.close()
