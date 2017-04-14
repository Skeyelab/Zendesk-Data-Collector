class IncrementalTicketWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'data_collector_default'

  def perform(desk_id)
    # Do something
    desk = Desk.find(desk_id)
    client = connectToZendesk(desk)
    starttime = desk.last_timestamp
    begin


      tix = client.tickets.incremental_export(starttime);

      tix.each do |tic|

        #      results = DB.query("SHOW COLUMNS FROM `#{desk["domain"].gsub('.','_')}`");
        results = GitHub::SQL.results <<-SQL
        select column_name, data_type, character_maximum_length
        from INFORMATION_SCHEMA.COLUMNS where table_name = '#{desk["domain"].gsub('.','_')}';

        SQL
        cols = []

        results.each do |col|
          cols << col[0]
        end

        apicols = []
        neededcols = []

        tic.keys.each do |key|
          apicols << key
        end

        neededcols = apicols - cols

        if neededcols.count > 0

          querypairs = []

          neededcols.each do |col|
            if (col.include? "req_external_id") || (col.include? "_name")
              pair = {:field => col, :type => "varchar(64)"}
              querypairs << pair
            elsif (col.include? "minutes")
              pair = {:field => col, :type => "int"}
              querypairs << pair
            elsif (col.include? "id")
              pair = {:field => col, :type => "bigint"}
              querypairs << pair
            elsif (tix.included["field_headers"][col]) && (tix.included["field_headers"][col].include? "[int]")
              pair = {:field => col, :type => "int"}
              querypairs << pair
            elsif (col.include? "generated_timestamp")
              pair = {:field => col, :type => "int"}
              querypairs << pair
            elsif (col.include? "_at") || (col.include? "timestamp")
              pair = {:field => col, :type => "TIMESTAMP WITH TIME ZONE"}
              querypairs << pair
            elsif col.include? "current_tags"
              pair = {:field => col, :type => "varchar(1024)"}
              querypairs << pair
            else
              pair = {:field => col, :type => "VARCHAR(255)"}
              querypairs << pair
            end
          end

          query = "ALTER TABLE #{desk["domain"].gsub('.','_')} "

          querypairs.each do |pair|
            query = query +" ADD COLUMN " +pair[:field] + " " + pair[:type]+","
          end

          query = query.chomp(",")

          GitHub::SQL.results query

        end

        querypairs = {}
        tic.each do |field|

          # if (field[0].include? "_at")
          #   if (field[1] != nil && field[1] != "")
          #     field[1] = Time.parse(field[1]).utc.strftime("%Y-%m-%d %H:%M:%S")
          #   end
          # end

          querypairs[field[0].to_s] = field[1]
        end

        q1 = "INSERT INTO #{desk["domain"].gsub('.','_')} ("
        q2 = ") VALUES ("
        querypairs.each do |key, value|
          q1 = q1 + key.to_s + ", "
          q2 = q2 + "'" + value.to_s + "', "
        end
        q1 = q1.chomp(", ")
        q2 = q2.chomp(", ")
        q2 = q2 + ")"
        query = q1+q2
        begin
          GitHub::SQL.results query.gsub("''", "NULL")

        rescue Exception => e
          next
        end

      end
      oldstarttime = starttime
      if tix.included
        if tix.included['end_time']
          starttime = tix.included['end_time']
        else
          starttime = 0
        end

        if starttime != 0
          GitHub::SQL.results "UPDATE desks SET last_timestamp = '#{starttime}' WHERE domain = '#{desk["domain"]}';"
        end
      end
    end while ((oldstarttime < starttime) && (oldstarttime < Time.now.to_i))
  end
end
