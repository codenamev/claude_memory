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
        @server.mount_proc("/api/facts") { |req, res| handle_facts(api, req, res) }
        @server.mount_proc("/api/efficacy") { |req, res| json_response(res, api.efficacy(req.query)) }
        @server.mount_proc("/api/session") { |req, res|
          session_id = req.query["session_id"]
          json_response(res, api.session_summary(session_id))
        }
        @server.mount_proc("/api/timeline") { |_req, res| json_response(res, api.timeline) }
        @server.mount_proc("/api/recall") { |req, res| json_response(res, api.recall(req.query)) }
        @server.mount_proc("/api/conflicts") { |req, res| handle_conflicts(api, req, res) }
      end

      def handle_conflicts(api, req, res)
        reject_id = conflict_reject_id_from_path(req.path)
        detail_id = conflict_id_from_path(req.path)
        is_reject_similar = req.path == "/api/conflicts/reject_similar"

        if req.request_method == "POST" && is_reject_similar
          body = parse_json_body(req)
          keeper_id = body["keeper_fact_id"]
          reason = body["reason"]
          scope = body["scope"] || req.query["scope"] || "project"
          json_response(res, api.reject_similar_conflicts(keeper_id, reason: reason, scope: scope))
        elsif req.request_method == "POST" && reject_id
          body = parse_json_body(req)
          side = body["side"]
          reason = body["reason"]
          scope = body["scope"] || req.query["scope"] || "project"
          json_response(res, api.reject_conflict_fact(reject_id, side: side, reason: reason, scope: scope))
        elsif detail_id
          scope = req.query["scope"] || "project"
          json_response(res, api.conflict_detail(detail_id, scope))
        else
          json_response(res, api.conflicts(req.query))
        end
      end

      def parse_json_body(req)
        return {} if req.body.nil? || req.body.empty?
        JSON.parse(req.body)
      rescue JSON::ParserError
        {}
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

      def fact_id_from_path(path)
        match = path.match(%r{\A/api/facts/(\d+)\z})
        match && match[1]
      end

      def fact_action_from_path(path)
        match = path.match(%r{\A/api/facts/(\d+)/(reject|promote)\z})
        match ? [match[1], match[2]] : nil
      end

      def handle_facts(api, req, res)
        action = fact_action_from_path(req.path)
        detail_id = fact_id_from_path(req.path)

        if req.request_method == "POST" && action
          fact_id, verb = action
          body = parse_json_body(req)
          scope = body["scope"] || req.query["scope"] || "project"
          case verb
          when "reject"
            json_response(res, api.reject_fact(fact_id, reason: body["reason"], scope: scope))
          when "promote"
            json_response(res, api.promote_fact(fact_id))
          end
        elsif detail_id
          scope = req.query["scope"] || "project"
          json_response(res, api.fact_detail(detail_id, scope))
        else
          json_response(res, api.facts(req.query))
        end
      end

      def conflict_id_from_path(path)
        match = path.match(%r{\A/api/conflicts/(\d+)\z})
        match && match[1]
      end

      def conflict_reject_id_from_path(path)
        match = path.match(%r{\A/api/conflicts/(\d+)/reject\z})
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
