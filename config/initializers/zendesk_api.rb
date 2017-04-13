def connectToZendesk(desk)
  client = ZendeskAPI::Client.new do |config|
    config.url = "https://#{desk.domain}/api/v2" # e.g. https://mydesk.zendesk.com/api/v2
    config.username = desk.user
    config.token = desk.token
    config.retry = false
  end

  client.insert_callback do |env|
    if env[:status] == 429
      DB.query("UPDATE `desks` SET `wait_till` = '#{(env[:response_headers][:retry_after] || 10).to_i + Time.now.to_i}' WHERE `domain` = '#{desk["domain"]}';")
    end
  end

  return client

end


def createTableIfNeeded(domain)

  tables = GitHub::SQL.results <<-SQL
  SELECT
  table_schema || '.' || table_name
  FROM
  information_schema.tables
  WHERE
  table_type = 'BASE TABLE'
  AND
  table_schema NOT IN ('pg_catalog', 'information_schema');
  SQL
  tbls =[]

  tables.each do |table|
    tbls << table[0].gsub!('.','_').gsub("public_","")
  end

  if !tbls.include? domain.gsub('.','_')

    GitHub::SQL.results <<-SQL
    CREATE TABLE #{domain.gsub('.','_')} (ID INT PRIMARY KEY NOT NULL);
    SQL
  end

end
