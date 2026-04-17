# frozen_string_literal: true

require "webrick"
require "json"

module ClaudeMemory
  module Dashboard
    class Server
      DEFAULT_PORT = 3377

      def initialize(manager:, port: DEFAULT_PORT, open_browser: true)
        @manager = manager
        @port = port
        @open_browser = open_browser
        @server = nil
      end

      def start
        @server = WEBrick::HTTPServer.new(
          Port: @port,
          Logger: WEBrick::Log.new(File::NULL),
          AccessLog: []
        )

        mount_routes

        trap("INT") { @server.shutdown }
        trap("TERM") { @server.shutdown }

        open_browser if @open_browser
        @server.start
      end

      def stop
        @server&.shutdown
      end

      private

      def mount_routes
        api = API.new(@manager)

        @server.mount_proc("/") { |_req, res| serve_html(res) }
        @server.mount_proc("/api/health") { |_req, res| json_response(res, api.health) }
        @server.mount_proc("/api/stats") { |_req, res| json_response(res, api.stats) }
        @server.mount_proc("/api/activity") { |req, res|
          if (id = activity_id_from_path(req.path))
            json_response(res, api.activity_detail(id))
          else
            json_response(res, api.activity(req.query))
          end
        }
        @server.mount_proc("/api/facts") { |req, res| json_response(res, api.facts(req.query)) }
        @server.mount_proc("/api/efficacy") { |_req, res| json_response(res, api.efficacy) }
        @server.mount_proc("/api/timeline") { |_req, res| json_response(res, api.timeline) }
      end

      def serve_html(res)
        html_path = File.expand_path("index.html", __dir__)
        res["Content-Type"] = "text/html; charset=utf-8"
        res.body = File.read(html_path)
      end

      def activity_id_from_path(path)
        match = path.match(%r{\A/api/activity/(\d+)\z})
        match && match[1]
      end

      def json_response(res, data)
        res["Content-Type"] = "application/json; charset=utf-8"
        res["Access-Control-Allow-Origin"] = "*"
        res.body = JSON.generate(data)
      end

      def open_browser
        url = "http://localhost:#{@port}"
        Thread.new do
          sleep 0.5
          system("open", url) || system("xdg-open", url) || system("start", url)
        end
      end
    end
  end
end
