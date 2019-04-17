Facter.add('hive_schemas') {
  setcode {
    dir = '/usr/lib/hive/scripts/metastore/upgrade'
    if Dir.exists?(dir)
      schemas = {}
      Dir.entries("#{dir}")
        .select { |f| f =~ /^[^\.]/ }
        .each do |db|
          # print "#{db}\n"
          file = Dir.entries("#{dir}/#{db}")
                 .select { |f| f =~ /^hive-schema-.*\.sql$/ }
                 .max do |a, b|
                   a =~ /^hive-schema-(.*)\.sql$/
                   v1 = $1
                   b =~ /^hive-schema-(.*)\.sql$/
                   v2 = $1
                   # print "  #{v1} #{v2}\n"
                   Gem::Version.new(v1) <=> Gem::Version.new(v2)
                 end
          schemas[db] = File.join(dir, db, file)
        end
      schemas
    else
      nil
    end
  }
}
