# frozen_string_literal: true

require 'sqlite3'
require 'time'

# AutoHCK module
module AutoHCK
  # Id Generator class
  class Idgen
    def initialize(range, timeout)
      @db = './id_gen.db'
      @range = range
      @conn = SQLite3::Database.new @db.to_s
      @threshold = timeout * 24 * 60 * 60
    end

    def load_data
      ids = Array.new(@range.last + 1 - @range.first, true)
      @conn.execute 'CREATE TABLE IF NOT EXISTS ActiveIds('\
                  'IdNumber INT PRIMARY KEY NOT NULL, PID INT NOT NULL,'\
                  'Time TIMESTAMP NOT NULL)'
      fetch_data(ids)
      ids
    rescue SQLite3::Exception
      -1
    end

    def gen_id
      ids = load_data
      return -1 if ids == -1
      return -1 unless ids.index(true)

      release_timeouts
      ids.index(true) + @range.first
    end

    def allocate
      id = gen_id
      return -1 if id.negative?

      time = Time.now.to_i
      @conn.execute "INSERT INTO ActiveIds VALUES(#{id},#{Process.pid},#{time})"
      id
    rescue SQLite3::ConstraintException
      retry
    rescue SQLite3::Exception
      -1
    end

    def release(id)
      @conn.execute "DELETE FROM ActiveIds WHERE IdNumber=#{id}"
      1
    rescue SQLite3::Exception
      -1
    ensure
      @conn&.close
    end

    private

    def release_timeouts
      now = Time.now.to_i
      kill_if_alive(now)
      @conn.execute "DELETE FROM ActiveIds WHERE (#{now} - Time) > #{@threshold}"
    rescue SQLite3::Exception
      -1
    end

    def fetch_data(ids)
      res = @conn.execute 'SELECT IdNumber FROM ActiveIds'
      res.each do |row|
        ids[row[0].to_i - @range.first] = false
      end
    end

    def kill_if_alive(now)
      res = @conn.execute 'SELECT PID FROM ActiveIds WHERE'\
                          "(#{now} - Time) > #{@threshold}"
      res.each do |row|
        pid = row[0].to_i
        check_cmd = "sudo ps -ef | grep #{pid} | grep auto_hck | grep -v grep"
        Process.kill('TERM', pid) unless `#{check_cmd}`.empty?
      end
    end
  end
end
